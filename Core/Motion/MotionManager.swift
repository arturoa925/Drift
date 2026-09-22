//
//  MotionManager.swift
//  Dritft
//
//  Created by Arturo Ayala on 5/28/26.
//

import Combine
import CoreMotion
import Foundation

/// Wraps `CMMotionActivityManager`, classifying the device's activity into a
/// `MovementState`. This is the API that actually requires the optional
/// "Motion" permission — plain `CMMotionManager` accelerometer/gyro access
/// doesn't need authorization, but activity classification does.
@MainActor
final class MotionManager: ObservableObject {
    @Published private(set) var authorizationStatus: CMAuthorizationStatus
    @Published private(set) var movementState: MovementState = .still
    @Published private(set) var error: Error?

    private let manager = CMMotionActivityManager()

    static var isAvailable: Bool {
        CMMotionActivityManager.isActivityAvailable()
    }

    init() {
        authorizationStatus = CMMotionActivityManager.authorizationStatus()
    }

    /// There's no standalone permission API for motion activity — the system
    /// prompt appears the first time updates are actually requested, so
    /// requesting permission and starting updates are the same call.
    func requestPermission() {
        startUpdating()
    }

    func startUpdating() {
        guard Self.isAvailable else {
            error = MotionManagerError.unavailable
            return
        }

        // startActivityUpdates's handler simply never fires if permission is
        // denied — no error, no crash, just silence. Catch that case up front
        // rather than starting updates that will never report anything.
        switch authorizationStatus {
        case .denied, .restricted:
            error = MotionManagerError.permissionDenied
            return
        default:
            break
        }

        manager.startActivityUpdates(to: .main) { [weak self] activity in
            guard let self, let activity else { return }
            movementState = Self.movementState(for: activity)
            authorizationStatus = CMMotionActivityManager.authorizationStatus()
            error = nil
        }
    }

    func stopUpdating() {
        manager.stopActivityUpdates()
    }

    private static func movementState(for activity: CMMotionActivity) -> MovementState {
        if activity.walking || activity.running {
            return .walking
        }
        // No dedicated "driving" state in the design yet, so automotive
        // shares biking's faster sway/pulse rather than falling back to still.
        if activity.cycling || activity.automotive {
            return .biking
        }
        return .still
    }
}

enum MotionManagerError: LocalizedError {
    case unavailable
    case permissionDenied

    var errorDescription: String? {
        switch self {
        case .unavailable:
            return "Motion activity isn't available on this device."
        case .permissionDenied:
            return "Motion & Fitness access is turned off for Drift."
        }
    }
}
