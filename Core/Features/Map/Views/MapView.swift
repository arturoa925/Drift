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
/// Roads come from `RoadNetworkService` and buildings from
/// `BuildingNetworkService` — both real OpenStreetMap geometry fetched via
/// Overpass, so a building's footprint actually lines up with where the
/// street it's next to really runs, rather than `PlaceholderCityGenerator`'s
/// made-up grid landing buildings in the middle of the road.
/// `MapOverlayView` (now superseded by `WorldView`), `TrailOverlay`, and the
/// floating pill controls are all still unbuilt; the heatmap layer
/// claude.md originally described has been dropped from scope entirely.
struct MapView: View {
    @StateObject private var model = MapModel()
    /// Real road geometry + names, fetched from OpenStreetMap — replaces
    /// `PlaceholderRoadGenerator` as the live source `roads` draws from.
    @StateObject private var roadNetwork = RoadNetworkService()
    /// Real building footprints + use tags, fetched from OpenStreetMap —
    /// replaces `PlaceholderCityGenerator` as the live source `buildings`
    /// draws from.
    @StateObject private var buildingNetwork = BuildingNetworkService()

    /// How far out buildings/roads get generated/rendered. `WorldView`'s
    /// planet radius sets the real ceiling here — at 1,200m, the geometric
    /// horizon from the camera's height is ~104m, and an ordinary building
    /// needs a lot of extra distance past that before it's tall enough to
    /// peek back up over the curve. 3 `CityGrid` blocks (~200m) covers that
    /// horizon with some margin for taller buildings that do clear it a
    /// little further out, without fetching/fading a radius most of which
    /// could never be visible anyway.
    private var renderRadiusMeters: Double {
        CityGrid.cellSizeDegrees * WorldProjection.metersPerDegreeLatitude * 3.0
    }

    var body: some View {
        ZStack {
            MapGradientLayer(model: model)
            WorldView(
                origin: streetOrigin,
                heading: model.heading,
                velocity: streetVelocity,
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
            guard let location else { return }
            Task {
                await roadNetwork.refresh(near: location.coordinate, radiusMeters: renderRadiusMeters)
            }
            Task {
                await buildingNetwork.refresh(near: location.coordinate, radiusMeters: renderRadiusMeters)
            }
        }
        .onAppear { model.start() }
        .onDisappear { model.stop() }
    }

    /// Closest point on the closest real road to the user, plus that road's
    /// own direction — `nil` before the first successful fetch, or when
    /// nothing real is close enough (e.g. no network yet, or genuinely off
    /// any mapped street) to snap to.
    private var nearestRoadSnap: (point: CLLocationCoordinate2D, direction: Vector2)? {
        guard let coordinate = model.currentLocation?.coordinate else { return nil }
        // 25m, not 15 — plain GPS (no Wi-Fi/cell assist, e.g. indoors) can
        // easily drift that far from the actual street, and snapping is
        // meant to correct exactly that kind of drift, not just the last
        // few meters of normal fix noise.
        return RoadNetworkService.nearestPoint(to: coordinate, in: roads, maxDistanceMeters: 25)
    }

    /// The user's location, slid onto the nearest real street when one's
    /// close enough to snap to, so the camera stands in the road rather
    /// than wherever raw GPS happens to land — falls back to the raw fix
    /// when there's nothing nearby to snap to yet.
    private var streetOrigin: CLLocationCoordinate2D? {
        guard let coordinate = model.currentLocation?.coordinate else { return nil }
        return nearestRoadSnap?.point ?? coordinate
    }

    /// The user's velocity, (east, north) m/s, projected onto the nearest
    /// street's own direction (whatever angle it actually runs at) so
    /// `WorldMotion`'s dead reckoning between fixes slides them down the
    /// road instead of drifting off it into the buildings. Passed through
    /// unprojected when there's no nearby street to project onto yet.
    private var streetVelocity: Vector2 {
        guard let location = model.currentLocation,
              location.speed >= minimumCourseSpeed,
              location.heading >= 0 else { return Vector2(dx: 0, dy: 0) }
        let course = location.heading * .pi / 180
        let east = location.speed * sin(course)
        let north = location.speed * cos(course)
        guard let direction = nearestRoadSnap?.direction else { return Vector2(dx: east, dy: north) }
        let along = east * direction.dx + north * direction.dy
        return Vector2(dx: direction.dx * along, dy: direction.dy * along)
    }

    /// Below this speed (m/s), GPS course is too noisy to trust.
    private let minimumCourseSpeed: Double = 0.7

    private var roads: [RoadSegment] {
        roadNetwork.roads
    }

    private var buildings: [BuildingShape] {
        buildingNetwork.buildings
    }
}

#Preview {
    MapView()
}
