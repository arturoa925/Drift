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
    private static let buildingsPerCell = 3
    // Width/depth drawn independently, so a cell can produce anything from
    // a small square kiosk to a long rectangular block — "shapes of all
    // sizes" without abandoning the rectangular footprint real buildings
    // actually have.
    private static let widthMeters: ClosedRange<Double> = 6...26
    private static let depthMeters: ClosedRange<Double> = 6...26
    // A small rotation jitter so a field of buildings doesn't read as a
    // perfectly regular grid of identical boxes.
    private static let rotationRadians: ClosedRange<Double> = -0.3...0.3
    private static let heightMeters: ClosedRange<Double> = 8...70
    // Flat clearance (beyond the worst-case footprint extent) kept between
    // a building's edge and the road line running along its cell's
    // boundary, so buildings never visually overlap the street grid.
    private static let roadClearanceMeters = 3.0

    static func buildings(near origin: CLLocationCoordinate2D, radiusMeters: Double) -> [BuildingShape] {
        let cellSpan = CityGrid.cellSpan(forRadiusMeters: radiusMeters)
        let originCell = CityGrid.cell(for: origin)

        // Scans a square block of cells around the origin — simple, but a
        // circle doesn't tile into squares, so this necessarily generates
        // some buildings past the corners that are farther than
        // `radiusMeters` away. The filter below trims those back out.
        var candidates: [BuildingShape] = []
        for latIndex in -cellSpan...cellSpan {
            for lngIndex in -cellSpan...cellSpan {
                let cellCoordinate = (lat: originCell.lat + latIndex, lng: originCell.lng + lngIndex)
                candidates.append(contentsOf: buildingsInCell(cellCoordinate))
            }
        }

        // Inscribes the true circle inside the square scan above: keep only
        // buildings whose centroid is really within `radiusMeters` in real
        // (Euclidean) meters, not grid cells.
        return candidates.filter { building in
            guard let center = centroid(of: building.footprint) else { return false }
            let offset = WorldProjection.offset(from: origin, to: center)
            return hypot(offset.dx, offset.dy) <= radiusMeters
        }
    }

    private static func buildingsInCell(_ cell: (lat: Int, lng: Int)) -> [BuildingShape] {
        // Same seed in, same `rng` sequence out, every time this cell is
        // asked about — `rng` is threaded (`inout`) through every building
        // and every random draw below, so the seed alone determines this
        // cell's entire output.
        var rng = SeededGenerator(seed: seed(for: cell))

        // `CityGrid.cell(for:)` used `floor`, so multiplying the index back
        // out recovers the cell's southwest corner, not its center.
        let cellOrigin = CLLocationCoordinate2D(
            latitude: Double(cell.lat) * CityGrid.cellSizeDegrees,
            longitude: Double(cell.lng) * CityGrid.cellSizeDegrees
        )
        let metersPerDegreeLongitude = WorldProjection.metersPerDegreeLongitude(atLatitude: cellOrigin.latitude)

        return (0..<buildingsPerCell).map { index in
            // Width/depth/rotation are drawn *before* the center, because
            // keeping a building clear of the road grid means knowing how
            // big its footprint could get before deciding where its center
            // is even allowed to land.
            let width = Double.random(in: widthMeters, using: &rng)
            let depth = Double.random(in: depthMeters, using: &rng)
            let rotation = Double.random(in: rotationRadians, using: &rng)
            let extentMeters = hypot(width / 2, depth / 2) + roadClearanceMeters

            let center = CLLocationCoordinate2D(
                latitude: cellOrigin.latitude + Double.random(
                    in: centerRange(extentMeters: extentMeters, metersPerDegree: WorldProjection.metersPerDegreeLatitude),
                    using: &rng
                ),
                longitude: cellOrigin.longitude + Double.random(
                    in: centerRange(extentMeters: extentMeters, metersPerDegree: metersPerDegreeLongitude),
                    using: &rng
                )
            )
            return BuildingShape(
                id: "\(cell.lat)_\(cell.lng)_\(index)",
                footprint: rectangleFootprint(center: center, width: width, depth: depth, rotation: rotation),
                height: Double.random(in: heightMeters, using: &rng),
                swayPhase: Double.random(in: 0..<1, using: &rng)
            )
        }
    }

    /// Where within a cell (as a degree offset from its southwest corner) a
    /// building's center is allowed to land, given how far its footprint
    /// could reach (`extentMeters`) from that center in the worst case.
    /// Collapses to the cell's exact midpoint if the footprint is too big
    /// to fit with any clearance at all, rather than producing an invalid
    /// (empty) range.
    private static func centerRange(extentMeters: Double, metersPerDegree: Double) -> ClosedRange<Double> {
        let extentDegrees = extentMeters / metersPerDegree
        let midpoint = CityGrid.cellSizeDegrees / 2
        let low = min(extentDegrees, midpoint)
        let high = max(CityGrid.cellSizeDegrees - extentDegrees, midpoint)
        return low...high
    }

    /// Builds a simple rectangular footprint (4 corners), gently rotated
    /// for variety — real city blocks are predominantly rectangular, and
    /// `WorldView`'s 3D extrusion (a roof + backface-culled side walls)
    /// only reads as a believable building when its base shape has flat,
    /// straight edges to extrude.
    private static func rectangleFootprint(
        center: CLLocationCoordinate2D,
        width: Double,
        depth: Double,
        rotation: Double
    ) -> [CLLocationCoordinate2D] {
        let halfWidth = width / 2
        let halfDepth = depth / 2
        // Corners in a local, unrotated frame centered on `center`, in
        // meters (east, north) — order matters here: it's what `WorldView`
        // relies on to know which edges are front-facing walls.
        let localCorners: [Vector2] = [
            Vector2(dx: -halfWidth, dy: -halfDepth),
            Vector2(dx: halfWidth, dy: -halfDepth),
            Vector2(dx: halfWidth, dy: halfDepth),
            Vector2(dx: -halfWidth, dy: halfDepth),
        ]

        let cosR = cos(rotation)
        let sinR = sin(rotation)
        return localCorners.map { local in
            let rotated = Vector2(
                dx: local.dx * cosR - local.dy * sinR,
                dy: local.dx * sinR + local.dy * cosR
            )
            return WorldProjection.coordinate(from: center, offset: rotated)
        }
    }

    /// Plain arithmetic mean of the vertices, not a true area-weighted
    /// polygon centroid — close enough for these small, roughly-regular
    /// jittered footprints, and not worth the extra complexity here.
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
