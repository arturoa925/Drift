//
//  RoadNetworkServiceTests.swift
//  DritftTests
//
//  Created by Arturo Ayala on 10/7/26.
//

import CoreLocation
import Foundation
import Testing
@testable import Dritft

struct RoadNetworkServiceTests {
    // A short east-west segment near San Francisco, ~111m long (0.001° of
    // longitude at this latitude).
    private let segmentStart = CLLocationCoordinate2D(latitude: 37.7749, longitude: -122.4194)
    private let segmentEnd = CLLocationCoordinate2D(latitude: 37.7749, longitude: -122.4184)

    private func segment(name: String? = "Test St") -> RoadSegment {
        RoadSegment(id: "test", start: segmentStart, end: segmentEnd, name: name)
    }

    @Test func nearestPointOnSegmentProjectsCleanly() {
        // A point directly "above" (north of) the segment's midpoint should
        // project onto that midpoint.
        let midLongitude = (segmentStart.longitude + segmentEnd.longitude) / 2
        let probe = CLLocationCoordinate2D(latitude: segmentStart.latitude + 0.0002, longitude: midLongitude)

        let result = RoadNetworkService.nearestPoint(to: probe, in: [segment()], maxDistanceMeters: 50)

        #expect(result != nil)
        if let result {
            #expect(abs(result.point.longitude - midLongitude) < 0.00001)
            #expect(abs(result.point.latitude - segmentStart.latitude) < 0.00001)
        }
    }

    @Test func nearestPointClampsPastSegmentEnd() {
        // A point beyond the segment's east end should clamp to that end,
        // not extrapolate past it.
        let probe = CLLocationCoordinate2D(latitude: segmentEnd.latitude, longitude: segmentEnd.longitude + 0.0005)

        let result = RoadNetworkService.nearestPoint(to: probe, in: [segment()], maxDistanceMeters: 100)

        #expect(result != nil)
        if let result {
            #expect(abs(result.point.longitude - segmentEnd.longitude) < 0.00001)
        }
    }

    @Test func nearestPointReturnsNilBeyondMaxDistance() {
        let farAway = CLLocationCoordinate2D(latitude: segmentStart.latitude + 1, longitude: segmentStart.longitude)

        let result = RoadNetworkService.nearestPoint(to: farAway, in: [segment()], maxDistanceMeters: 50)

        #expect(result == nil)
    }
}

struct OverpassResponseDecodingTests {
    @Test func decodesWaysWithGeometryAndName() throws {
        let json = """
        {
            "elements": [
                {
                    "type": "way",
                    "id": 42,
                    "tags": { "name": "Market St", "highway": "primary" },
                    "geometry": [
                        { "lat": 37.7749, "lon": -122.4194 },
                        { "lat": 37.7750, "lon": -122.4184 }
                    ]
                }
            ]
        }
        """.data(using: .utf8)!

        let decoded = try JSONDecoder().decode(OverpassResponse.self, from: json)

        #expect(decoded.elements.count == 1)
        #expect(decoded.elements[0].name == "Market St")
        #expect(decoded.elements[0].geometry?.count == 2)
    }
}
