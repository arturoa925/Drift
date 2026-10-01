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

    /// Which way a placeholder street runs.
    enum StreetAxis {
        case northSouth
        case eastWest

        /// The axis closest to a compass bearing (0–360°, 0 = north).
        init(bearing: Double) {
            let axisBearing = bearing.truncatingRemainder(dividingBy: 180)
            let normalized = axisBearing < 0 ? axisBearing + 180 : axisBearing
            self = normalized < 45 || normalized >= 135 ? .northSouth : .eastWest
        }
    }

    /// Slides `coordinate` sideways onto the center line of the nearest
    /// grid street running along `axis`. Its position *along* that street
    /// is left untouched.
    ///
    /// This keeps `WorldView`'s street-level camera standing in the middle
    /// of a road with buildings on either side, rather than wherever raw
    /// GPS lands inside a placeholder block. It only makes sense while the
    /// streets are this made-up grid; real road data would snap to the
    /// nearest real street instead.
    static func streetCenter(near coordinate: CLLocationCoordinate2D, along axis: StreetAxis) -> CLLocationCoordinate2D {
        func snapped(_ degrees: Double) -> Double {
            (degrees / cellSizeDegrees).rounded() * cellSizeDegrees
        }
        switch axis {
        case .northSouth:
            return CLLocationCoordinate2D(latitude: coordinate.latitude, longitude: snapped(coordinate.longitude))
        case .eastWest:
            return CLLocationCoordinate2D(latitude: snapped(coordinate.latitude), longitude: coordinate.longitude)
        }
    }
}
