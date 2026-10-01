//
//  MapView.swift
//  Dritft
//
//  Created by Arturo Ayala on 5/28/26.
//

import CoreLocation
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
    /// Which placeholder street the user is standing in. Chosen from the
    /// direction they're *walking* (GPS course), never from which way
    /// they're facing — so turning on the spot spins the street around
    /// them instead of hopping them onto a cross street. `nil` until the
    /// first fix, then seeded from compass heading.
    @State private var streetAxis: CityGrid.StreetAxis?

    /// How far out buildings/roads get generated/rendered — roughly 2.5
    /// `CityGrid` blocks (~65m each) in every direction. Was 220m (~3.4
    /// blocks); pulled in further so the world reads as "what's actually
    /// nearby" rather than the full render radius the curved/scaled
    /// perspective can otherwise make visible all at once.
    private var renderRadiusMeters: Double {
        CityGrid.cellSizeDegrees * WorldProjection.metersPerDegreeLatitude * 2.5
    }

    var body: some View {
        ZStack {
            MapGradientLayer(model: model)
            WorldView(
                origin: streetOrigin,
                heading: model.heading,
                movementState: model.movementState,
                roads: roads,
                buildings: buildings,
                renderRadiusMeters: renderRadiusMeters
            )
            // Pinned to wherever `WorldView`'s camera projects the user's
            // feet — low on screen, not dead center.
            GeometryReader { proxy in
                UserPulseView(
                    weatherCondition: model.weatherCondition,
                    timeOfDayCondition: model.timeOfDayCondition,
                    movementState: model.movementState
                )
                .position(x: proxy.size.width / 2, y: proxy.size.height * WorldView.userScreenAnchorY)
            }
        }
        // Full-bleed on purpose: `WorldView`'s Canvas and `UserPulseView`
        // both position against this ZStack's own bounds, so it needs to
        // span the entire screen (under the status bar/notch/home indicator
        // too) — otherwise safe-area insets would shrink its frame and pull
        // the pulse dot off the user's projected position.
        .ignoresSafeArea()
        .onChange(of: model.currentLocation, initial: true) { _, location in
            updateStreetAxis(for: location)
        }
        .onAppear { model.start() }
        .onDisappear { model.stop() }
    }

    /// The user's location slid onto the middle of the nearest placeholder
    /// street along `streetAxis`, so the camera always stands in the road —
    /// see `CityGrid.streetCenter(near:along:)`.
    private var streetOrigin: CLLocationCoordinate2D? {
        guard let coordinate = model.currentLocation?.coordinate else { return nil }
        let axis = streetAxis ?? CityGrid.StreetAxis(bearing: model.heading ?? 0)
        return CityGrid.streetCenter(near: coordinate, along: axis)
    }

    /// Below this speed (m/s), GPS course is too noisy to trust — the axis
    /// just stays whatever it already was.
    private let minimumCourseSpeed: Double = 0.7

    private func updateStreetAxis(for location: DeviceLocation?) {
        guard let location else { return }
        if location.speed >= minimumCourseSpeed, location.heading >= 0 {
            streetAxis = CityGrid.StreetAxis(bearing: location.heading)
        } else if streetAxis == nil {
            streetAxis = CityGrid.StreetAxis(bearing: model.heading ?? 0)
        }
    }

    private var roads: [RoadSegment] {
        guard let origin = streetOrigin else { return [] }
        return PlaceholderRoadGenerator.roads(near: origin, radiusMeters: renderRadiusMeters)
    }

    private var buildings: [BuildingShape] {
        guard let origin = streetOrigin else { return [] }
        return PlaceholderCityGenerator.buildings(near: origin, radiusMeters: renderRadiusMeters)
    }
}

#Preview {
    MapView()
}
