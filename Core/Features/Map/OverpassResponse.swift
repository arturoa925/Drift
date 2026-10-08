//
//  OverpassResponse.swift
//  Dritft
//
//  Created by Arturo Ayala on 10/7/26.
//

import Foundation

/// Decodes the JSON `RoadNetworkService` gets back from the Overpass API —
/// mirrors `WeatherResponse.swift`'s role for Open-Meteo. The query always
/// asks for `out geom;`, so every way's `geometry` arrives inline and no
/// separate node lookup is ever needed.
struct OverpassResponse: Decodable {
    let elements: [OverpassElement]
}

struct OverpassElement: Decodable {
    let type: String
    let id: Int
    let tags: [String: String]?
    let geometry: [OverpassPoint]?

    /// The query filters to `[highway][name]`, so this should always be
    /// present on a real result — `nil` only guards a malformed/unexpected
    /// element rather than something callers need to handle as normal.
    var name: String? { tags?["name"] }
}

struct OverpassPoint: Decodable {
    let lat: Double
    let lon: Double
}
