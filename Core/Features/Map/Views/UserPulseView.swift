//
//  UserPulseView.swift
//  Dritft
//
//  Created by Arturo Ayala on 5/28/26.
//

import SwiftUI

/// The fixed dot at screen center representing the user — drawn instead of
/// MapKit's default blue dot, and the one thing on the map screen that
/// never moves, per `WorldView`'s whole design (the world drifts around a
/// stationary user).
///
/// Per claude.md, color comes from the active theme (never movement) and
/// animation speed comes from `movementState` (never color) — the two
/// inputs are deliberately independent.
struct UserPulseView: View {
    let weatherCondition: WeatherCondition
    let timeOfDayCondition: TimeOfDayCondition
    let movementState: MovementState

    private let dotDiameter: CGFloat = 10
    private let shadowRingWidth: CGFloat = 3
    private let pulseRingDiameter: CGFloat = 26
    private let pulseRingLineWidth: CGFloat = 1.5

    var body: some View {
        TimelineView(.animation) { timeline in
            // A driven-by-time wave rather than an implicit SwiftUI
            // animation, matching WorldView's pattern — this way a change
            // in `movementState.pulseDuration` (e.g. still -> walking)
            // takes effect on the very next frame, with no restart/replay
            // logic needed to re-trigger an `.animation(_:).repeatForever`.
            let duration = movementState.pulseDuration
            let time = timeline.date.timeIntervalSinceReferenceDate
            let phase = (time.truncatingRemainder(dividingBy: duration)) / duration
            // sin(0...π) traces one full 0 -> 1 -> 0 hump per `duration` —
            // the same up-then-back-down shape an autoreversing animation
            // would produce, with the easing built in for free.
            let pulse = sin(phase * .pi)

            // FSD-style ego marker: a soft blue glow, a thin pulsing ring,
            // and a crisp white core — the one bright thing on a dark map.
            ZStack {
                Circle()
                    .fill(
                        RadialGradient(
                            colors: [TeslaStyle.accentGlow.opacity(0.45), .clear],
                            center: .center,
                            startRadius: 2,
                            endRadius: 30
                        )
                    )
                    .frame(width: 60, height: 60)
                    .opacity(0.55 + pulse * 0.45)

                Circle()
                    .stroke(TeslaStyle.accentGlow.opacity(0.7), lineWidth: pulseRingLineWidth)
                    .frame(width: pulseRingDiameter, height: pulseRingDiameter)
                    .scaleEffect(1 + pulse * 0.22)
                    .opacity(0.40 + pulse * 0.48)

                Circle()
                    .fill(TeslaStyle.accent.opacity(0.9))
                    .frame(width: dotDiameter + shadowRingWidth * 2, height: dotDiameter + shadowRingWidth * 2)

                Circle()
                    .fill(Color.white)
                    .frame(width: dotDiameter, height: dotDiameter)
            }
        }
    }
}

#Preview {
    ZStack {
        Color.black
        UserPulseView(weatherCondition: .sunny, timeOfDayCondition: .night, movementState: .walking)
    }
}
