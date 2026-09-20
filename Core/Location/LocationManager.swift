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
    @Published private(set) var error: Error?

    private let manager = CLLocationManager()

    override init() {
        authorizationStatus = manager.authorizationStatus
        super.init()
        manager.delegate = self
        manager.desiredAccuracy = kCLLocationAccuracyBest
        manager.distanceFilter = 5
    }

    func requestPermission() {
        manager.requestWhenInUseAuthorization()
    }

    func startUpdating() {
        manager.startUpdatingLocation()
    }

    func stopUpdating() {
        manager.stopUpdatingLocation()
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
}
