//
//  WorldProjection.swift
//  Dritft
//
//  Created by Arturo Ayala on 5/28/26.
//

import CoreLocation
import Foundation

/// A 2D offset in meters. Deliberately not CoreGraphics' `CGVector` — all
/// the projection math here stays in `Double` and only needs to become
/// `CGFloat` screen coordinates at the very last step, inside `WorldView`.
struct Vector2 {
    var dx: Double
    var dy: Double
}

/// Flat-earth approximation converting real-world coordinates into meters
/// relative to a moving origin — accurate enough at the city-block
/// distances `WorldView` renders (a few hundred meters), where Earth's
/// curvature is negligible.
///
/// This is what makes "the world moves around a fixed user" possible at
/// all: nothing here has a position in absolute map coordinates. Every
/// building's position is expressed relative to wherever the user
/// currently is, recomputed fresh each time `origin` changes — there's no
/// camera to pan, because there's no fixed frame for a camera to pan
/// across.
enum WorldProjection {
    private static let metersPerDegreeLatitude = 111_320.0

    /// Offset of `point` from `origin`, in meters — east/north, not screen
    /// space yet.
    static func offset(from origin: CLLocationCoordinate2D, to point: CLLocationCoordinate2D) -> Vector2 {
        let metersPerDegreeLongitude = metersPerDegreeLatitude * cos(origin.latitude * .pi / 180)
        let dx = (point.longitude - origin.longitude) * metersPerDegreeLongitude
        let dy = (point.latitude - origin.latitude) * metersPerDegreeLatitude
        return Vector2(dx: dx, dy: dy)
    }
}
