//
//  CityGrid.swift
//  Dritft
//
//  Created by Arturo Ayala on 5/28/26.
//

import CoreLocation
import Foundation

/// The shared coordinate grid `PlaceholderCityGenerator` (buildings) and
/// `PlaceholderRoadGenerator` (streets) both snap to — kept in one place so
/// a street always runs exactly along the boundary a building's cell sits
/// inside, rather than each generator picking its own, potentially
/// mismatched, grid.
enum CityGrid {
    static let cellSizeDegrees = 0.0006 // ~65m per cell

    /// Snaps a coordinate to its containing grid cell (floor division), so
    /// every point within the same ~65m patch maps to the same cell index.
    static func cell(for coordinate: CLLocationCoordinate2D) -> (lat: Int, lng: Int) {
        (
            Int(floor(coordinate.latitude / cellSizeDegrees)),
            Int(floor(coordinate.longitude / cellSizeDegrees))
        )
    }

    /// How many cells out (in each direction) a `radiusMeters` query could
    /// possibly reach: convert one cell's side length to meters, divide it
    /// into the radius, round up, then pad by one extra cell so nothing
    /// near a cell's far edge gets missed.
    static func cellSpan(forRadiusMeters radiusMeters: Double) -> Int {
        Int(ceil(radiusMeters / (cellSizeDegrees * WorldProjection.metersPerDegreeLatitude))) + 1
    }
}
