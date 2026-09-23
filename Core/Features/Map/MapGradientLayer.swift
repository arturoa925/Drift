//
//  MapGradientLayer.swift
//  Dritft
//
//  Created by Arturo Ayala on 5/28/26.
//

import SwiftUI

/// The map screen's bottom-most layer, per claude.md's stacking order
/// (gradient → map overlay → heatmap → trail → pulse dot → controls).
/// Deliberately just a pass-through: `GradientBackground` already owns all
/// the actual rendering logic (sway animation, theme cross-fade) and stays
/// a "dumb" reusable component with no knowledge of `MapModel` or Combine.
/// This is the one piece that bridges the two — observing the live model
/// so the rest of the gradient system doesn't have to.
struct MapGradientLayer: View {
    @ObservedObject var model: MapModel

    var body: some View {
        GradientBackground(theme: model.theme)
    }
}

#Preview {
    MapGradientLayer(model: MapModel())
}
