//
//  TeslaBackdrop.swift
//  Dritft
//
//  The map's bottom layer. The theme gradient from `ThemeEngine` is shown
//  in full — same colors, same slow sway, same cross-fades — as the sky.
//  On top of it, a gentle ground plane below the renderer's real horizon
//  adds depth: slightly darker toward the viewer, with a pale haze right at
//  the horizon (aerial perspective), so streets and buildings sit on
//  something instead of floating. It never goes dark: even at its darkest
//  the gradient's own colors still read, per the "themes never go fully
//  dark" rule.
//

import SwiftUI

struct TeslaBackdrop: View {
    let theme: MapTheme

    /// How much the ground darkens at the very bottom of the screen.
    private let groundDarkening: Double = 0.24

    var body: some View {
        GeometryReader { proxy in
            let horizon = WorldView.horizonFraction(width: proxy.size.width, height: proxy.size.height)

            ZStack {
                // The original theme gradient, untouched.
                GradientBackground(theme: theme)

                // Ground plane: starts clear at the horizon, deepens toward
                // the viewer.
                LinearGradient(
                    stops: [
                        .init(color: .black.opacity(0), location: horizon),
                        .init(color: .black.opacity(groundDarkening * 0.45), location: horizon + (1 - horizon) * 0.25),
                        .init(color: .black.opacity(groundDarkening), location: 1),
                    ],
                    startPoint: .top,
                    endPoint: .bottom
                )

                // Atmospheric haze hugging the horizon line.
                LinearGradient(
                    stops: [
                        .init(color: .white.opacity(0), location: max(horizon - 0.05, 0)),
                        .init(color: .white.opacity(0.22), location: horizon),
                        .init(color: .white.opacity(0), location: min(horizon + 0.10, 1)),
                    ],
                    startPoint: .top,
                    endPoint: .bottom
                )
            }
        }
        .ignoresSafeArea()
        .allowsHitTesting(false)
    }
}

#Preview {
    TeslaBackdrop(theme: ThemeEngine.theme(weather: .sunny, timeOfDay: .sunset))
}
