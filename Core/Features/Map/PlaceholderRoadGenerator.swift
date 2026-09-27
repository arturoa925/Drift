//
//  PlaceholderRoadGenerator.swift
//  Dritft
//
//  Created by Arturo Ayala on 5/28/26.
//

import CoreLocation
import Foundation

/// Stand-in for real road data. Draws the street grid buildings sit
/// inside — straight lines along `CityGrid`'s cell boundaries — as a
/// placeholder for real geometry later (OpenStreetMap/Overpass, same
/// story as `PlaceholderCityGenerator`).
///
/// Unlike buildings, roads need no randomness at all: a city block grid is
/// just the grid itself, so every line is derived directly from
/// `CityGrid.cellSizeDegrees` rather than seeded per cell.
enum PlaceholderRoadGenerator {
    static func roads(near origin: CLLocationCoordinate2D, radiusMeters: Double) -> [RoadSegment] {
        let cellSpan = CityGrid.cellSpan(forRadiusMeters: radiusMeters)
        let originCell = CityGrid.cell(for: origin)

        let minLatIndex = originCell.lat - cellSpan
        let maxLatIndex = originCell.lat + cellSpan
        let minLngIndex = originCell.lng - cellSpan
        let maxLngIndex = originCell.lng + cellSpan

        // Bounds each line spans, in degrees — one cell past the scan
        // radius on every side so lines run off-screen rather than
        // visibly stopping right at the edge of the rendered area.
        let minLat = Double(minLatIndex) * CityGrid.cellSizeDegrees
        let maxLat = Double(maxLatIndex + 1) * CityGrid.cellSizeDegrees
        let minLng = Double(minLngIndex) * CityGrid.cellSizeDegrees
        let maxLng = Double(maxLngIndex + 1) * CityGrid.cellSizeDegrees

        var roads: [RoadSegment] = []

        // Horizontal (east-west) streets: one per latitude gridline, each
        // spanning the full scanned longitude range in a single segment —
        // this (rather than one segment per cell edge) is what keeps every
        // shared cell boundary from being drawn twice.
        for latIndex in minLatIndex...(maxLatIndex + 1) {
            let latitude = Double(latIndex) * CityGrid.cellSizeDegrees
            roads.append(RoadSegment(
                id: "h_\(latIndex)",
                start: CLLocationCoordinate2D(latitude: latitude, longitude: minLng),
                end: CLLocationCoordinate2D(latitude: latitude, longitude: maxLng),
                orientation: .horizontal
            ))
        }

        // Vertical (north-south) streets: one per longitude gridline, each
        // spanning the full scanned latitude range.
        for lngIndex in minLngIndex...(maxLngIndex + 1) {
            let longitude = Double(lngIndex) * CityGrid.cellSizeDegrees
            roads.append(RoadSegment(
                id: "v_\(lngIndex)",
                start: CLLocationCoordinate2D(latitude: minLat, longitude: longitude),
                end: CLLocationCoordinate2D(latitude: maxLat, longitude: longitude),
                orientation: .vertical
            ))
        }

        return roads
    }
}
