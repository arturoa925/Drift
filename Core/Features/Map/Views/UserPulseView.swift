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

            ZStack {
                Circle()
                    .stroke(Color.white.opacity(0.45), lineWidth: pulseRingLineWidth)
                    .frame(width: pulseRingDiameter, height: pulseRingDiameter)
                    .scaleEffect(1 + pulse * 0.22)
                    .opacity(0.40 + pulse * 0.48)

                // Reproduces the spec's `0 0 0 3px rgba(255,255,255,.30)`
                // shadow ring: CSS's zero-blur spread shadow is just a
                // solid ring exactly `shadowRingWidth` wide around the
                // shape, which a same-color circle underneath (sized up by
                // the spread on both sides) draws directly.
                Circle()
                    .fill(Color.white.opacity(0.30))
                    .frame(width: dotDiameter + shadowRingWidth * 2, height: dotDiameter + shadowRingWidth * 2)

                Circle()
                    .fill(dotColor)
                    .frame(width: dotDiameter, height: dotDiameter)
            }
        }
    }

    /// Storm and night are the only themes with a non-white dot — everything
    /// else (including snow, called out explicitly in claude.md) stays
    /// white. Storm is checked first since weather always outranks time of
    /// day whenever it's strong enough to override it.
    private var dotColor: Color {
        if weatherCondition == .storm {
            return Color(hex: "D8B4FE")
        }
        if !weatherCondition.overridesTimeOfDay && timeOfDayCondition == .night {
            return Color(hex: "BAE6FD")
        }
        return .white
    }
}

#Preview {
    ZStack {
        Color.black
        UserPulseView(weatherCondition: .sunny, timeOfDayCondition: .night, movementState: .walking)
    }
}
