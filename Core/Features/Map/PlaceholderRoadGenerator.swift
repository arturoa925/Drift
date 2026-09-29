//
//  PlaceholderRoadGenerator.swift
//  Dritft
//
//  Created by Arturo Ayala on 5/28/26.
//

import CoreLocation
import Foundation

/// Stand-in for real road data. Draws the street grid buildings sit
/// inside — straight lines along `CityGrid`'s cell boundaries — as a
/// placeholder for real geometry later (OpenStreetMap/Overpass, same
/// story as `PlaceholderCityGenerator`).
///
/// Unlike buildings, roads need no randomness at all: a city block grid is
/// just the grid itself, so every line is derived directly from
/// `CityGrid.cellSizeDegrees` rather than seeded per cell.
enum PlaceholderRoadGenerator {
    static func roads(near origin: CLLocationCoordinate2D, radiusMeters: Double) -> [RoadSegment] {
        let cellSpan = CityGrid.cellSpan(forRadiusMeters: radiusMeters)
        let originCell = CityGrid.cell(for: origin)

        let minLatIndex = originCell.lat - cellSpan
        let maxLatIndex = originCell.lat + cellSpan
        let minLngIndex = originCell.lng - cellSpan
        let maxLngIndex = originCell.lng + cellSpan

        // Bounds each line spans, in degrees — one cell past the scan
        // radius on every side so lines run off-screen rather than
        // visibly stopping right at the edge of the rendered area.
        let minLat = Double(minLatIndex) * CityGrid.cellSizeDegrees
        let maxLat = Double(maxLatIndex + 1) * CityGrid.cellSizeDegrees
        let minLng = Double(minLngIndex) * CityGrid.cellSizeDegrees
        let maxLng = Double(maxLngIndex + 1) * CityGrid.cellSizeDegrees

        var roads: [RoadSegment] = []

        // Horizontal (east-west) streets: one per latitude gridline, each
        // spanning the full scanned longitude range in a single segment —
        // this (rather than one segment per cell edge) is what keeps every
        // shared cell boundary from being drawn twice.
        for latIndex in minLatIndex...(maxLatIndex + 1) {
            let latitude = Double(latIndex) * CityGrid.cellSizeDegrees
            if let clipped = clip(
                start: CLLocationCoordinate2D(latitude: latitude, longitude: minLng),
                end: CLLocationCoordinate2D(latitude: latitude, longitude: maxLng),
                origin: origin,
                radiusMeters: radiusMeters
            ) {
                roads.append(RoadSegment(id: "h_\(latIndex)", start: clipped.start, end: clipped.end, orientation: .horizontal))
            }
        }

        // Vertical (north-south) streets: one per longitude gridline, each
        // spanning the full scanned latitude range.
        for lngIndex in minLngIndex...(maxLngIndex + 1) {
            let longitude = Double(lngIndex) * CityGrid.cellSizeDegrees
            if let clipped = clip(
                start: CLLocationCoordinate2D(latitude: minLat, longitude: longitude),
                end: CLLocationCoordinate2D(latitude: maxLat, longitude: longitude),
                origin: origin,
                radiusMeters: radiusMeters
            ) {
                roads.append(RoadSegment(id: "v_\(lngIndex)", start: clipped.start, end: clipped.end, orientation: .vertical))
            }
        }

        return roads
    }

    /// Trims a line segment down to the portion that actually falls within
    /// `radiusMeters` of `origin`, `nil` if none of it does. Every generated
    /// line spans the entire square scan area (out to each corner, ~1.4x
    /// `radiusMeters`) so the shared-boundary dedup logic above stays
    /// simple — but nothing downstream should actually see the part outside
    /// the circle buildings are already filtered to, or a straight,
    /// full-length line rendered through `WorldView`'s curved, heading-
    /// rotated projection reads as a chaotic tangle of far-flung segments
    /// rather than the tidy local grid it's meant to be.
    ///
    /// Solved as a standard line-circle intersection in flat local meters
    /// (fine at this scale): parametrize the segment as `start + t*(end -
    /// start)`, solve `|point(t)|² = radius²` for t, then clip `[0, 1]` down
    /// to wherever that's satisfied.
    private static func clip(
        start: CLLocationCoordinate2D,
        end: CLLocationCoordinate2D,
        origin: CLLocationCoordinate2D,
        radiusMeters: Double
    ) -> (start: CLLocationCoordinate2D, end: CLLocationCoordinate2D)? {
        let a = WorldProjection.offset(from: origin, to: start)
        let b = WorldProjection.offset(from: origin, to: end)
        let d = Vector2(dx: b.dx - a.dx, dy: b.dy - a.dy)

        let coefficientA = d.dx * d.dx + d.dy * d.dy
        let coefficientB = 2 * (a.dx * d.dx + a.dy * d.dy)
        let coefficientC = a.dx * a.dx + a.dy * a.dy - radiusMeters * radiusMeters

        let discriminant = coefficientB * coefficientB - 4 * coefficientA * coefficientC
        guard discriminant >= 0, coefficientA > 0 else { return nil }

        let sqrtDiscriminant = discriminant.squareRoot()
        let t0 = max(0, (-coefficientB - sqrtDiscriminant) / (2 * coefficientA))
        let t1 = min(1, (-coefficientB + sqrtDiscriminant) / (2 * coefficientA))
        guard t0 < t1 else { return nil }

        func point(at t: Double) -> CLLocationCoordinate2D {
            WorldProjection.coordinate(from: origin, offset: Vector2(dx: a.dx + d.dx * t, dy: a.dy + d.dy * t))
        }
        return (point(at: t0), point(at: t1))
    }
}
