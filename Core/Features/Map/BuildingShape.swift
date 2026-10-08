//
//  BuildingShape.swift
//  Dritft
//
//  Created by Arturo Ayala on 5/28/26.
//

import CoreLocation
import Foundation

/// What a building is actually used for, as far as OSM's tagging says —
/// lets `WorldView` read as "homes vs. businesses vs. everything else"
/// instead of an undifferentiated field of identical blocks.
enum BuildingCategory {
    /// Houses, apartments, residential blocks — `building=house`,
    /// `=residential`, `=apartments`, `=detached`, etc.
    case residential
    /// Anything with a `shop`, `office`, or business-flavored `amenity`/
    /// `building` tag — shops, restaurants, offices, retail.
    case commercial
    /// Schools, hospitals, warehouses, or a bare `building=yes` with
    /// nothing else to go on.
    case other
}

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

    /// How tall this building is, in meters. `WorldView` turns this into a
    /// vertical screen-space extrusion (the roof floats this "high" above
    /// the footprint) to give buildings a pseudo-3D block appearance
    /// instead of a flat silhouette.
    let height: Double

    /// 0..<1, chosen once at generation time (not derived from `id`, since
    /// Swift's string hashing is randomized per process and wouldn't stay
    /// deterministic across launches). Gives each building its own
    /// animation phase and speed so a field of them sways like grass,
    /// rather than in lockstep.
    let swayPhase: Double

    /// `.other` for `PlaceholderCityGenerator` output, which has no tags to
    /// classify from. Real, `BuildingNetworkService`-sourced buildings get
    /// this from OSM's `building`/`shop`/`amenity`/`office` tags.
    var category: BuildingCategory = .other
}
