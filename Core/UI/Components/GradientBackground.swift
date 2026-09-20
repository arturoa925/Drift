//
//  GradientBackground.swift
//  Dritft
//
//  Created by Arturo Ayala on 5/28/26.
//

import SwiftUI

/// Full-screen background driven by the active `MapTheme`. Layers two kinds
/// of motion on top of the static gradient: a slow ambient sway that runs
/// continuously (`.gradientDrift`), and a smooth cross-fade whenever `theme`
/// itself changes (`.themeTransition`).
///
/// The gradient always runs top-to-bottom, matching claude.md's spec. The
/// sway scales every stop's location toward and away from the gradient's
/// center together, paired with a matching whole-view scale — color and
/// size expanding and contracting in sync reads as breathing rather than
/// just color drift. No seam or reset either way: top and bottom move
/// evenly instead of the motion concentrating at one end.
struct GradientBackground: View {
    let theme: MapTheme

    @State private var swayAmount: Double = 0

    var body: some View {
        LinearGradient(gradient: swayedGradient, startPoint: .top, endPoint: .bottom)
            .scaleEffect(1 + swayAmount * 0.015)
            .ignoresSafeArea()
            .animation(.themeTransition, value: theme)
            .onAppear {
                withAnimation(.gradientDrift) {
                    swayAmount = 1
                }
            }
    }

    private var swayedGradient: Gradient {
        // Ranges from 0.92 to 1.08 as swayAmount eases between 0 and 1.
        let scale = 1 + (swayAmount - 0.5) * 0.16
        let stops = theme.gradientStops.map { stop in
            Gradient.Stop(color: stop.color, location: 0.5 + (stop.location - 0.5) * scale)
        }
        return Gradient(stops: stops)
    }
}

#Preview {
    GradientBackground(theme: ThemeEngine.theme(weather: .sunny, timeOfDay: .sunset))
}
