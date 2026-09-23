//
//  PlaceholderCityGenerator.swift
//  Dritft
//
//  Created by Arturo Ayala on 5/28/26.
//

import CoreLocation
import Foundation

/// Stand-in for real building data. Generates a plausible, but entirely
/// made-up, field of building footprints around a coordinate — enough to
/// prove out `WorldView`'s rendering, sway, and proximity-scale mechanics
/// before wiring up a real geometry source (OpenStreetMap/Overpass, most
/// likely — see MapView's doc comment for why that's a deliberate later
/// step, not this one).
///
/// Buildings are seeded per grid cell, not per call. Without that, the same
/// patch of "city" would reshuffle into different shapes on every tiny GPS
/// update, which would read as flicker rather than a stable world — the
/// same cell must always produce the same buildings.
enum PlaceholderCityGenerator {
    private static let cellSizeDegrees = 0.0006 // ~65m per cell
    private static let buildingsPerCell = 3
    private static let footprintRadiusMeters: ClosedRange<Double> = 8...20
    private static let metersPerDegreeLatitude = 111_320.0

    static func buildings(near origin: CLLocationCoordinate2D, radiusMeters: Double) -> [BuildingShape] {
        let cellSpan = Int(ceil(radiusMeters / (cellSizeDegrees * metersPerDegreeLatitude))) + 1
        let originCell = cell(for: origin)

        var candidates: [BuildingShape] = []
        for latIndex in -cellSpan...cellSpan {
            for lngIndex in -cellSpan...cellSpan {
                let cellCoordinate = (lat: originCell.lat + latIndex, lng: originCell.lng + lngIndex)
                candidates.append(contentsOf: buildingsInCell(cellCoordinate))
            }
        }

        return candidates.filter { building in
            guard let center = centroid(of: building.footprint) else { return false }
            let offset = WorldProjection.offset(from: origin, to: center)
            return hypot(offset.dx, offset.dy) <= radiusMeters
        }
    }

    private static func cell(for coordinate: CLLocationCoordinate2D) -> (lat: Int, lng: Int) {
        (
            Int(floor(coordinate.latitude / cellSizeDegrees)),
            Int(floor(coordinate.longitude / cellSizeDegrees))
        )
    }

    private static func buildingsInCell(_ cell: (lat: Int, lng: Int)) -> [BuildingShape] {
        var rng = SeededGenerator(seed: seed(for: cell))
        let cellOrigin = CLLocationCoordinate2D(
            latitude: Double(cell.lat) * cellSizeDegrees,
            longitude: Double(cell.lng) * cellSizeDegrees
        )

        return (0..<buildingsPerCell).map { index in
            let center = CLLocationCoordinate2D(
                latitude: cellOrigin.latitude + Double.random(in: 0...cellSizeDegrees, using: &rng),
                longitude: cellOrigin.longitude + Double.random(in: 0...cellSizeDegrees, using: &rng)
            )
            return BuildingShape(
                id: "\(cell.lat)_\(cell.lng)_\(index)",
                footprint: randomFootprint(center: center, rng: &rng),
                swayPhase: Double.random(in: 0..<1, using: &rng)
            )
        }
    }

    /// Builds an irregular polygon (4-6 vertices, jittered angle and
    /// radius) around `center`, rather than a plain rectangle — real
    /// building footprints aren't rectangles either, and the variety
    /// matters for the "different shapes" the renderer is meant to show.
    private static func randomFootprint(
        center: CLLocationCoordinate2D,
        rng: inout SeededGenerator
    ) -> [CLLocationCoordinate2D] {
        let vertexCount = Int.random(in: 4...6, using: &rng)
        let baseRadius = Double.random(in: footprintRadiusMeters, using: &rng)
        let metersPerDegreeLongitude = metersPerDegreeLatitude * cos(center.latitude * .pi / 180)

        return (0..<vertexCount).map { index in
            let angle = (Double(index) / Double(vertexCount)) * 2 * .pi
            let jitteredAngle = angle + Double.random(in: -0.35...0.35, using: &rng)
            let jitteredRadius = baseRadius * Double.random(in: 0.7...1.15, using: &rng)

            let dx = cos(jitteredAngle) * jitteredRadius
            let dy = sin(jitteredAngle) * jitteredRadius

            return CLLocationCoordinate2D(
                latitude: center.latitude + dy / metersPerDegreeLatitude,
                longitude: center.longitude + dx / metersPerDegreeLongitude
            )
        }
    }

    private static func centroid(of points: [CLLocationCoordinate2D]) -> CLLocationCoordinate2D? {
        guard !points.isEmpty else { return nil }
        let latitude = points.reduce(0) { $0 + $1.latitude } / Double(points.count)
        let longitude = points.reduce(0) { $0 + $1.longitude } / Double(points.count)
        return CLLocationCoordinate2D(latitude: latitude, longitude: longitude)
    }

    /// Cheap integer hash (FNV-1a) — doesn't need to be cryptographic, just
    /// stable across launches and well-mixed enough that adjacent cells
    /// don't produce visually similar building patterns.
    private static func seed(for cell: (lat: Int, lng: Int)) -> UInt64 {
        var hash: UInt64 = 0xcbf29ce484222325
        for value in [cell.lat, cell.lng] {
            hash ^= UInt64(bitPattern: Int64(value))
            hash = hash &* 0x100000001b3
        }
        return hash
    }
}

/// Deterministic `RandomNumberGenerator` (SplitMix64). Swift's default
/// `Random` is seeded from system entropy and can't be reproduced, which is
/// exactly what `PlaceholderCityGenerator` needs to avoid — the same cell
/// must generate the same buildings every time it's asked.
struct SeededGenerator: RandomNumberGenerator {
    private var state: UInt64

    init(seed: UInt64) {
        self.state = seed
    }

    mutating func next() -> UInt64 {
        state &+= 0x9E3779B97F4A7C15
        var z = state
        z = (z ^ (z >> 30)) &* 0xBF58476D1CE4E5B9
        z = (z ^ (z >> 27)) &* 0x94D049BB133111EB
        return z ^ (z >> 31)
    }
}
