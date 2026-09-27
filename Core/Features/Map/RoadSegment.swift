//
//  RoadSegment.swift
//  Dritft
//
//  Created by Arturo Ayala on 5/28/26.
//

import CoreLocation
import Foundation

/// A single straight street segment. For now every instance comes from
/// `PlaceholderRoadGenerator` — always perfectly axis-aligned, running the
/// full length of one `CityGrid` line rather than a real street's actual
/// path — but structured so a real road-geometry source could replace the
/// generator later without `WorldView` changing.
struct RoadSegment: Identifiable {
    /// claude.md gives horizontal and vertical roads different opacities,
    /// so `WorldView` needs to know which one this is at render time.
    enum Orientation {
        case horizontal
        case vertical
    }

    let id: String
    let start: CLLocationCoordinate2D
    let end: CLLocationCoordinate2D
    let orientation: Orientation
}
