//
//  SpeedPillView.swift
//  Dritft
//
//  Created by Arturo Ayala on 5/28/26.
//

import SwiftUI

/// Tesla-style speed readout: a large, light-weight number with a quiet
/// unit label, and the travel-mode glyph once the user is moving.
struct SpeedPillView: View {
    /// Meters per second; negative when CoreLocation can't determine it.
    let speedMetersPerSecond: Double
    let movementState: MovementState

    private var kilometersPerHour: Int {
        guard speedMetersPerSecond > 0.3 else { return 0 }
        return Int((speedMetersPerSecond * 3.6).rounded())
    }

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 6) {
            Text("\(kilometersPerHour)")
                .font(.system(size: 54, weight: .light, design: .default))
                .monospacedDigit()
                .foregroundStyle(TeslaStyle.textPrimary)
                .contentTransition(.numericText())
                .animation(.easeOut(duration: 0.25), value: kilometersPerHour)

            VStack(alignment: .leading, spacing: 4) {
                if let icon = movementState.iconName {
                    Image(systemName: icon)
                        .font(.system(size: 13, weight: .regular))
                        .foregroundStyle(TeslaStyle.accentGlow)
                }
                Text("km/h")
                    .font(.system(size: 11, weight: .medium))
                    .tracking(0.8)
                    .foregroundStyle(TeslaStyle.textSecondary)
            }
        }
    }
}

#Preview {
    ZStack {
        Color.black
        SpeedPillView(speedMetersPerSecond: 1.6, movementState: .walking)
    }
}
