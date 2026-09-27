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
    /// Meters per degree of latitude — constant everywhere, since lines of
    /// latitude are evenly spaced parallel circles from equator to pole.
    /// Longitude isn't this simple (see `offset`/`coordinate` below), which
    /// is the one real subtlety in this whole file.
    ///
    /// This is the WGS84 *average*; the true value varies slightly (~110,574m
    /// at the equator to ~111,694m at the poles, since Earth is an oblate
    /// spheroid, not a sphere). That variation is far below rendering-visible
    /// error at the city-block distances this module deals with.
    ///
    /// Shared by anything else that needs to convert between degrees and
    /// meters at that scale (e.g. `PlaceholderCityGenerator`'s cell sizing)
    /// — kept in one place so it can't drift out of sync between call sites.
    static let metersPerDegreeLatitude = 111_320.0

    /// Offset of `point` from `origin`, in meters — east/north, not screen
    /// space yet.
    ///
    /// Unlike latitude, a degree of longitude does *not* cover a constant
    /// distance — lines of longitude converge at the poles, so the same 1°
    /// spans less real distance the further you get from the equator. The
    /// `cos(latitude)` factor corrects for that (the standard equirectangular
    /// projection): at the equator it's 1, and it shrinks toward 0 near the
    /// poles. At San Francisco's ~37.7°N, `cos(37.7°) ≈ 0.79` — a degree of
    /// longitude there is only ~79% as many meters as a degree of latitude.
    static func offset(from origin: CLLocationCoordinate2D, to point: CLLocationCoordinate2D) -> Vector2 {
        let metersPerDegreeLongitude = metersPerDegreeLatitude * cos(origin.latitude * .pi / 180)
        let dx = (point.longitude - origin.longitude) * metersPerDegreeLongitude
        let dy = (point.latitude - origin.latitude) * metersPerDegreeLatitude
        return Vector2(dx: dx, dy: dy)
    }

    /// Inverse of `offset(from:to:)` — the coordinate `offset` meters
    /// east/north of `origin`.
    static func coordinate(from origin: CLLocationCoordinate2D, offset: Vector2) -> CLLocationCoordinate2D {
        let metersPerDegreeLongitude = metersPerDegreeLatitude * cos(origin.latitude * .pi / 180)
        return CLLocationCoordinate2D(
            latitude: origin.latitude + offset.dy / metersPerDegreeLatitude,
            longitude: origin.longitude + offset.dx / metersPerDegreeLongitude
        )
    }
}
