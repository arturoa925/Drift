//
//  BuildingShape.swift
//  Dritft
//
//  Created by Arturo Ayala on 5/28/26.
//

import CoreLocation
import Foundation

/// A single building's real-world footprint. For now every instance comes
/// from `PlaceholderCityGenerator` — `footprint` is a made-up polygon, not
/// an actual building outline — but it's structured exactly like real
/// building data (e.g. from OpenStreetMap/Overpass) would be, so swapping
/// the source later shouldn't require changing `WorldView` at all.
struct BuildingShape: Identifiable {
    let id: String

    /// Polygon vertices, absolute lat/lng — not pre-projected. `WorldView`
    /// reprojects every building relative to wherever the user currently
    /// is, every time it redraws.
    let footprint: [CLLocationCoordinate2D]

    /// 0..<1, chosen once at generation time (not derived from `id`, since
    /// Swift's string hashing is randomized per process and wouldn't stay
    /// deterministic across launches). Gives each building its own
    /// animation phase and speed so a field of them sways like grass,
    /// rather than in lockstep.
    let swayPhase: Double
}
