//
//  RoadSegment.swift
//  Dritft
//
//  Created by Arturo Ayala on 5/28/26.
//

import CoreLocation
import Foundation

/// How big/important a road actually is, from OSM's `highway` tag — lets
/// `WorldView` draw a wide, bright arterial differently from a narrow,
/// dim alley instead of every road in a dense grid looking identical.
/// Ordered roughly biggest-to-smallest.
enum RoadClass: Hashable {
    /// `motorway`, `trunk`, `primary` — the roads a city's traffic
    /// actually flows on.
    case major
    /// `secondary`, `tertiary` — one step down, still a real through-street.
    case secondary
    /// `residential`, `unclassified`, `living_street` — an ordinary street,
    /// the OSM default for "a normal road with no further classification."
    case residential
    /// `service`, `track`, `footway`, `path`, `cycleway`, `pedestrian`,
    /// `steps`, or anything else — alleys, driveways, sidewalks, trails.
    case minor
}

/// A single straight street segment. For now every instance comes from
/// `PlaceholderRoadGenerator` — always perfectly axis-aligned, running the
/// full length of one `CityGrid` line rather than a real street's actual
/// path — but structured so a real road-geometry source could replace the
/// generator later without `WorldView` changing.
struct RoadSegment: Identifiable {
    let id: String
    let start: CLLocationCoordinate2D
    let end: CLLocationCoordinate2D
    /// The street's real name, from OSM's `name` tag — `nil` for
    /// placeholder-generated segments, which have no such data.
    let name: String?
    /// `.residential` for `PlaceholderRoadGenerator` output (an ordinary
    /// street is the least surprising default for a made-up grid); real,
    /// `RoadNetworkService`-sourced segments get this from OSM's `highway`
    /// tag.
    var roadClass: RoadClass = .residential
}
