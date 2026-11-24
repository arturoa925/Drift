//
//  TeslaBackdrop.swift
//  Dritft
//
//  The map's bottom layer in the new look: a graphite ground with the
//  active theme's gradient demoted to a sky/horizon glow. Weather and time
//  still set the mood — they just tint the atmosphere instead of flooding
//  the whole screen.
//

import SwiftUI

struct TeslaBackdrop: View {
    let theme: MapTheme

    var body: some View {
        ZStack {
            LinearGradient(
                colors: [TeslaStyle.canvasTop, TeslaStyle.canvasBottom],
                startPoint: .top,
                endPoint: .bottom
            )

            // The theme gradient, kept in motion by the existing sway and
            // cross-fade, but faded out toward the ground so it reads as
            // sky.
            GradientBackground(theme: theme)
                .opacity(0.78)
                .mask(
                    LinearGradient(
                        stops: [
                            .init(color: .white, location: 0.0),
                            .init(color: .white.opacity(0.55), location: 0.28),
                            .init(color: .white.opacity(0.0), location: 0.52),
                        ],
                        startPoint: .top,
                        endPoint: .bottom
                    )
                )

            // Soft horizon haze where sky meets ground.
            LinearGradient(
                colors: [.clear, TeslaStyle.accent.opacity(0.07), .clear],
                startPoint: UnitPoint(x: 0.5, y: 0.30),
                endPoint: UnitPoint(x: 0.5, y: 0.60)
            )

            // Vignette keeps edges calm and focuses the eye on the road.
            RadialGradient(
                colors: [.clear, .black.opacity(0.45)],
                center: UnitPoint(x: 0.5, y: 0.65),
                startRadius: 180,
                endRadius: 620
            )
        }
        .ignoresSafeArea()
        .allowsHitTesting(false)
    }
}

#Preview {
    TeslaBackdrop(theme: ThemeEngine.theme(weather: .sunny, timeOfDay: .sunset))
}
