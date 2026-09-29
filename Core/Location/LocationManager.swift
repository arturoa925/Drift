//
//  LocationManager.swift
//  Dritft
//
//  Created by Arturo Ayala on 5/28/26.
//

import Combine
import CoreLocation
import Foundation

/// Wraps `CLLocationManager`, publishing the device's authorization status
/// and the most recent `DeviceLocation` snapshot. Owns permission requests
/// and the update stream only — it doesn't interpret movement state or sun
/// times, that's `MotionManager` and `SunCalculator`.
@MainActor
final class LocationManager: NSObject, ObservableObject {
    // Declared explicitly because Swift's automatic `objectWillChange`
    // synthesis doesn't reliably trigger for an NSObject subclass marked
    // @MainActor — this satisfies the ObservableObject requirement directly.
    let objectWillChange = ObservableObjectPublisher()

    @Published private(set) var authorizationStatus: CLAuthorizationStatus
    @Published private(set) var currentLocation: DeviceLocation?
    /// True (magnetic-north-corrected) compass heading, 0-360°, `nil` until
    /// the first reading arrives or on a device without a magnetometer.
    /// Distinct from `DeviceLocation.heading` (GPS direction of travel,
    /// from `location.course`) — that one only updates while actually
    /// moving, so it can't drive a "turn your body while standing still"
    /// rotation the way this can.
    @Published private(set) var trueHeading: CLLocationDirection?
    @Published private(set) var error: Error?

    private let manager = CLLocationManager()

    override init() {
        authorizationStatus = manager.authorizationStatus
        super.init()
        manager.delegate = self
        manager.desiredAccuracy = kCLLocationAccuracyBest
        manager.distanceFilter = 5
        manager.headingFilter = 2
    }

    func requestPermission() {
        manager.requestWhenInUseAuthorization()
    }

    func startUpdating() {
        manager.startUpdatingLocation()
        if CLLocationManager.headingAvailable() {
            manager.startUpdatingHeading()
        }
    }

    func stopUpdating() {
        manager.stopUpdatingLocation()
        manager.stopUpdatingHeading()
    }
}

extension LocationManager: CLLocationManagerDelegate {
    // CLLocationManagerDelegate's requirements aren't main-actor isolated,
    // so each method here must be `nonisolated` to satisfy the protocol.
    // The actual state mutation still needs to happen on the main actor
    // (this class is @MainActor), so each one hops over with a Task.

    nonisolated func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        Task { @MainActor in
            authorizationStatus = manager.authorizationStatus
        }
    }

    nonisolated func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        guard let location = locations.last else { return }
        let snapshot = DeviceLocation(
            latitude: location.coordinate.latitude,
            longitude: location.coordinate.longitude,
            speed: location.speed,
            heading: location.course,
            timestamp: location.timestamp
        )
        Task { @MainActor in
            currentLocation = snapshot
            error = nil
        }
    }

    nonisolated func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {
        Task { @MainActor in
            self.error = error
        }
    }

    nonisolated func locationManager(_ manager: CLLocationManager, didUpdateHeading newHeading: CLHeading) {
        // A negative value means the reading is invalid (e.g. needs
        // calibration) — magneticHeading is the fallback for devices/
        // moments where true heading isn't available at all.
        guard newHeading.headingAccuracy >= 0 else { return }
        let heading = newHeading.trueHeading >= 0 ? newHeading.trueHeading : newHeading.magneticHeading
        Task { @MainActor in
            trueHeading = heading
        }
    }
}
