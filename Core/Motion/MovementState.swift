//
//  MovementState.swift
//  Dritft
//
//  Created by Arturo Ayala on 5/28/26.
//

import Foundation

/// The user's current mode of travel, as classified by `MotionManager`.
/// Drives map sway angle and pulse-dot animation speed — never color,
/// which comes from `ThemeEngine` alone.
enum MovementState: String, CaseIterable {
    case still
    case walking
    case biking

    /// Map sway amplitude in degrees, per the design spec (still = no sway).
    var swayAngle: Double {
        switch self {
        case .still: return 0
        case .walking: return 1.5
        case .biking: return 3
        }
    }

    /// User pulse dot animation duration in seconds. Biking is specified as a
    /// 1.0–1.2s range in the design doc; this uses the midpoint.
    var pulseDuration: Double {
        switch self {
        case .still: return 3.4
        case .walking: return 2.2
        case .biking: return 1.1
        }
    }

    /// SF Symbol for the speed pill. `nil` while still, since the pill only
    /// shows a mode icon once the user is actually moving.
    var iconName: String? {
        switch self {
        case .still: return nil
        case .walking: return "figure.walk"
        case .biking: return "bicycle"
        }
    }
}
