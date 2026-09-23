//
//  MapView.swift
//  Dritft
//
//  Created by Arturo Ayala on 5/28/26.
//

import SwiftUI

/// The map screen's root container — stacks every visual layer per
/// claude.md's order (gradient → map overlay → heatmap → trail → pulse dot
/// → floating controls) and owns the `MapModel` that drives all of them.
///
/// MapKit has been dropped entirely as a rendering surface — `WorldView`
/// draws its own building geometry instead, always relative to the user's
/// live location. That's what makes "the user stands still and the world
/// moves around them" possible: there's no camera to manage here at all,
/// since nothing is drawn in fixed map coordinates to begin with. MapKit
/// may come back later purely as a utility (e.g. `MKLocalSearch` for place
/// lookup), but never again as what's actually rendered on screen.
///
/// Buildings are still `PlaceholderCityGenerator` output, not real
/// geometry — proving out this renderer's sway/scale/rotation feel first,
/// then swapping in real data (OpenStreetMap/Overpass, most likely) is a
/// deliberate, separate next step. `MapOverlayView` (now superseded by
/// `WorldView`), `HeatmapOverlayView`, `TrailOverlay`, `UserPulseView` (the
/// fixed center dot the user should see themselves as), and the floating
/// pill controls are all still unbuilt.
struct MapView: View {
    @StateObject private var model = MapModel()

    /// How far out buildings get generated/rendered. Kept modest — this is
    /// placeholder geometry computed fresh on every location update, not
    /// cached, so there's no reason to ask for more than the screen can
    /// actually show.
    private let renderRadiusMeters: Double = 220

    var body: some View {
        ZStack {
            MapGradientLayer(model: model)
            WorldView(origin: model.currentLocation?.coordinate, buildings: buildings)
        }
        .onAppear { model.start() }
        .onDisappear { model.stop() }
    }

    private var buildings: [BuildingShape] {
        guard let origin = model.currentLocation?.coordinate else { return [] }
        return PlaceholderCityGenerator.buildings(near: origin, radiusMeters: renderRadiusMeters)
    }
}

#Preview {
    MapView()
}
