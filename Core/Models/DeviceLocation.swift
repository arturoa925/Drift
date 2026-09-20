//
//  DeviceLocation.swift
//  Dritft
//
//  Created by Arturo Ayala on 5/28/26.
//

import CoreLocation
import Foundation

/// A single snapshot of the device's current location, as reported by
/// `LocationManager`. Not a history — just "where is the user right now."
struct DeviceLocation: Codable, Equatable {
    let latitude: Double
    let longitude: Double
    /// Meters per second. -1 when CoreLocation can't determine speed.
    let speed: Double
    /// Degrees relative to true north, 0-360. -1 when unavailable.
    let heading: Double
    let timestamp: Date

    var coordinate: CLLocationCoordinate2D {
        CLLocationCoordinate2D(latitude: latitude, longitude: longitude)
    }
}
