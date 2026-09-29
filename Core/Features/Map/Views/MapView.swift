//
//  MapView.swift
//  Dritft
//
//  Created by Arturo Ayala on 5/28/26.
//

import SwiftUI

/// The map screen's root container — stacks every visual layer per
/// claude.md's order (gradient → map overlay → trail → pulse dot → floating
/// controls) and owns the `MapModel` that drives all of them.
///
/// MapKit has been dropped entirely as a rendering surface — `WorldView`
/// draws its own road and building geometry instead, always relative to the
/// user's live location. That's what makes "the user stands still and the
/// world moves around them" possible: there's no camera to manage here at
/// all, since nothing is drawn in fixed map coordinates to begin with.
/// MapKit may come back later purely as a utility (e.g. `MKLocalSearch` for
/// place lookup), but never again as what's actually rendered on screen.
///
/// Roads and buildings are still `PlaceholderRoadGenerator`/
/// `PlaceholderCityGenerator` output, not real geometry — proving out this
/// renderer's sway/scale/rotation feel first, then swapping in real data
/// (OpenStreetMap/Overpass, most likely) is a deliberate, separate next
/// step. `MapOverlayView` (now superseded by `WorldView`), `TrailOverlay`,
/// and the floating pill controls are all still unbuilt; the heatmap layer
/// claude.md originally described has been dropped from scope entirely.
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
            WorldView(origin: model.currentLocation?.coordinate, roads: roads, buildings: buildings)
            UserPulseView(
                weatherCondition: model.weatherCondition,
                timeOfDayCondition: model.timeOfDayCondition,
                movementState: model.movementState
            )
        }
        // Full-bleed on purpose: `WorldView`'s Canvas and `UserPulseView`
        // both center on this ZStack's own bounds, so it needs to span the
        // entire screen (under the status bar/notch/home indicator too) —
        // otherwise safe-area insets would shrink its frame and pull the
        // pulse dot away from the screen's true visual center.
        .ignoresSafeArea()
        .onAppear { model.start() }
        .onDisappear { model.stop() }
    }

    private var roads: [RoadSegment] {
        guard let origin = model.currentLocation?.coordinate else { return [] }
        return PlaceholderRoadGenerator.roads(near: origin, radiusMeters: renderRadiusMeters)
    }

    private var buildings: [BuildingShape] {
        guard let origin = model.currentLocation?.coordinate else { return [] }
        return PlaceholderCityGenerator.buildings(near: origin, radiusMeters: renderRadiusMeters)
    }
}

#Preview {
    MapView()
}
