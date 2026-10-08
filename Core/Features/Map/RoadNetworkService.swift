//
//  RoadNetworkService.swift
//  Dritft
//
//  Created by Arturo Ayala on 10/7/26.
//

import Combine
import CoreLocation
import Foundation

/// Fetches real road geometry + names from OpenStreetMap, via the Overpass
/// API — same free/no-key pattern `WeatherService` uses for Open-Meteo.
/// Replaces `PlaceholderRoadGenerator` as `MapView`'s live road source;
/// `PlaceholderRoadGenerator` still exists for `WorldView`'s offline
/// `#Preview`.
///
/// Doesn't refetch on every GPS fix — Overpass is a free, shared, rate-aware
/// API, the same reason `WeatherService` doesn't poll on its own. Instead
/// `refresh` tracks the bounding circle its last successful fetch actually
/// covered, and only calls out again once the requested area has moved
/// outside it.
@MainActor
final class RoadNetworkService: ObservableObject {
    @Published private(set) var roads: [RoadSegment] = []
    @Published private(set) var error: Error?

    /// Real fetch radius is `requestedRadius * fetchPadding` — the buffer
    /// that lets nearby fixes reuse the same cached fetch, the same spirit
    /// as `PlaceholderRoadGenerator`'s one-cell-past-the-scan-edge padding.
    private let fetchPadding: Double = 2.0

    private var lastFetchOrigin: CLLocationCoordinate2D?
    private var lastFetchRadiusMeters: Double = 0
    private var inFlightTask: Task<Void, Never>?

    private let session: URLSession

    init(session: URLSession = .shared) {
        self.session = session
    }

    /// Called on every GPS fix from `LocationManager`'s unthrottled stream —
    /// `isCovered`/`inFlightTask` make almost every one of those calls a
    /// same-run no-op, so they stay silent; only an actual outbound fetch
    /// logs, to keep the console readable.
    func refresh(near origin: CLLocationCoordinate2D, radiusMeters: Double) async {
        guard inFlightTask == nil else { return }
        guard !isCovered(origin: origin, radiusMeters: radiusMeters) else { return }

        let fetchRadius = radiusMeters * fetchPadding
        print("RoadNetworkService: fetching near \(origin.latitude), \(origin.longitude), radius \(fetchRadius)m")
        let task = Task { [weak self] in
            guard let self else { return }
            await self.fetch(near: origin, radiusMeters: fetchRadius)
        }
        inFlightTask = task
        await task.value
        inFlightTask = nil
    }

    /// True when the last successful fetch's circle already fully contains
    /// the circle this request needs — i.e. the user hasn't walked far
    /// enough from where that fetch was centered to risk falling outside
    /// its edge.
    private func isCovered(origin: CLLocationCoordinate2D, radiusMeters: Double) -> Bool {
        guard let lastFetchOrigin else { return false }
        let distanceMoved = hypot(
            WorldProjection.offset(from: lastFetchOrigin, to: origin).dx,
            WorldProjection.offset(from: lastFetchOrigin, to: origin).dy
        )
        return distanceMoved + radiusMeters <= lastFetchRadiusMeters
    }

    /// Public Overpass instances, raced against each other rather than
    /// tried in sequence — `overpass-api.de` and `kumi.systems` fail under
    /// load often enough in practice that waiting out each one in turn
    /// before reaching `openstreetmap.fr` was adding real, visible latency
    /// to every single fetch. Racing means paying only the latency of
    /// whichever one actually answers, not the sum of the dead ones first.
    private static let endpoints = [
        "https://overpass-api.de/api/interpreter",
        "https://overpass.kumi.systems/api/interpreter",
        "https://overpass.openstreetmap.fr/api/interpreter",
    ]

    /// How many times to race the whole set before giving up — the
    /// 500s/504s these free mirrors occasionally return are usually load
    /// spikes that clear within seconds, not persistent outages, so it's
    /// worth riding those out here rather than surfacing a gap in the
    /// roads and waiting on the next GPS fix to try again.
    private static let maxAttempts = 3
    /// Backoff between attempt cycles, seconds — only reached if every
    /// endpoint failed the same race, short enough that a transient outage
    /// doesn't leave the user road-less for long.
    private static let retryDelaySeconds: UInt64 = 2
    /// Per-request timeout, seconds — short enough that one slow/hanging
    /// mirror can't drag the whole race out; a healthy mirror answers this
    /// query well within it.
    private static let requestTimeoutSeconds: TimeInterval = 10

    private func fetch(near origin: CLLocationCoordinate2D, radiusMeters: Double) async {
        var lastError: Error = RoadNetworkServiceError.requestFailed
        for attempt in 1...Self.maxAttempts {
            do {
                let (data, endpoint) = try await raceEndpoints(near: origin, radiusMeters: radiusMeters)
                let decoded = try JSONDecoder().decode(OverpassResponse.self, from: data)
                roads = Self.segments(from: decoded.elements)
                lastFetchOrigin = origin
                lastFetchRadiusMeters = radiusMeters
                error = nil
                print("RoadNetworkService: fetched \(decoded.elements.count) ways, \(roads.count) segments from \(endpoint)")
                return
            } catch {
                lastError = error
            }
            if attempt < Self.maxAttempts {
                try? await Task.sleep(nanoseconds: Self.retryDelaySeconds * 1_000_000_000)
            }
        }
        // Every endpoint failed on every attempt — leave `roads` as whatever
        // the last successful fetch returned rather than clearing it, so a
        // stretch of bad network doesn't blank the street names the user is
        // currently standing among; it just stops updating until the next
        // successful refresh.
        error = lastError
    }

    /// Fires every endpoint at once and returns the first successful
    /// response, cancelling the rest — the actual speedup over trying them
    /// one at a time. Throws only if every endpoint in the race failed.
    private func raceEndpoints(near origin: CLLocationCoordinate2D, radiusMeters: Double) async throws -> (Data, String) {
        try await withThrowingTaskGroup(of: (Data, String).self) { group in
            for endpoint in Self.endpoints {
                group.addTask {
                    let data = try await self.fetch(endpoint: endpoint, near: origin, radiusMeters: radiusMeters)
                    return (data, endpoint)
                }
            }

            var lastError: Error = RoadNetworkServiceError.requestFailed
            while let outcome = await group.nextResult() {
                switch outcome {
                case .success(let result):
                    group.cancelAll()
                    return result
                case .failure(let error):
                    lastError = error
                }
            }
            throw lastError
        }
    }

    private func fetch(endpoint: String, near origin: CLLocationCoordinate2D, radiusMeters: Double) async throws -> Data {
        let url = try Self.overpassURL(endpoint: endpoint, near: origin, radiusMeters: radiusMeters)
        var request = URLRequest(url: url)
        // Overpass's public instances 406 requests carrying a generic/
        // default User-Agent (curl's, and iOS's own CFNetwork default
        // alike) — identifying the client is actually what their usage
        // policy asks for, not an incidental workaround.
        request.setValue("Dritft/1.0 (iOS)", forHTTPHeaderField: "User-Agent")
        request.timeoutInterval = Self.requestTimeoutSeconds
        let (data, response) = try await session.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode == 200 else {
            let status = (response as? HTTPURLResponse)?.statusCode ?? -1
            print("RoadNetworkService: non-200 response from \(endpoint), status \(status)")
            throw RoadNetworkServiceError.requestFailed
        }
        return data
    }

    private static func overpassURL(endpoint: String, near origin: CLLocationCoordinate2D, radiusMeters: Double) throws -> URL {
        // Dropped the `[name]` filter that used to limit this to named
        // streets only — it was silently discarding every unnamed service
        // road, alley, footway, and cycleway in the area, which is most of
        // what makes a real street grid read as dense/detailed up close.
        // `RoadSegment.name` stays optional, so `drawStreetLabels` already
        // skips labeling these; they just render as geometry.
        let query = """
        [out:json][timeout:25];
        way(around:\(radiusMeters),\(origin.latitude),\(origin.longitude))[highway];
        out geom;
        """
        var components = URLComponents(string: endpoint)
        components?.queryItems = [URLQueryItem(name: "data", value: query)]
        guard let url = components?.url else {
            throw RoadNetworkServiceError.invalidCoordinates
        }
        return url
    }

    /// Flattens each way's node list into one `RoadSegment` per consecutive
    /// pair — `WorldView.drawRoads` already samples a segment along its own
    /// length, so a multi-node street reads correctly as several segments
    /// sharing one name rather than needing any renderer change.
    private static func segments(from elements: [OverpassElement]) -> [RoadSegment] {
        var result: [RoadSegment] = []
        for element in elements {
            guard let geometry = element.geometry, geometry.count >= 2 else { continue }
            let name = element.name
            let roadClass = roadClass(from: element.tags ?? [:])
            let points = geometry.map { CLLocationCoordinate2D(latitude: $0.lat, longitude: $0.lon) }
            for index in 0..<(points.count - 1) {
                result.append(RoadSegment(
                    id: "\(element.id)_\(index)",
                    start: points[index],
                    end: points[index + 1],
                    name: name,
                    roadClass: roadClass
                ))
            }
        }
        return result
    }

    private static let majorHighwayValues: Set<String> = ["motorway", "motorway_link", "trunk", "trunk_link", "primary", "primary_link"]
    private static let secondaryHighwayValues: Set<String> = ["secondary", "secondary_link", "tertiary", "tertiary_link"]
    private static let residentialHighwayValues: Set<String> = ["residential", "unclassified", "living_street"]

    private static func roadClass(from tags: [String: String]) -> RoadClass {
        guard let highway = tags["highway"] else { return .minor }
        if majorHighwayValues.contains(highway) { return .major }
        if secondaryHighwayValues.contains(highway) { return .secondary }
        if residentialHighwayValues.contains(highway) { return .residential }
        return .minor
    }

    /// Finds the closest point on the closest segment in `roads` to
    /// `coordinate`, within `maxDistanceMeters` — standard point-to-segment
    /// projection done in local meters (via `WorldProjection`), clamped to
    /// each segment's own `[0, 1]` so the result always lands on the
    /// segment itself, never past one of its ends.
    nonisolated static func nearestPoint(
        to coordinate: CLLocationCoordinate2D,
        in roads: [RoadSegment],
        maxDistanceMeters: Double
    ) -> (point: CLLocationCoordinate2D, direction: Vector2)? {
        var best: (distance: Double, point: CLLocationCoordinate2D, direction: Vector2)?

        for road in roads {
            let start = WorldProjection.offset(from: coordinate, to: road.start)
            let end = WorldProjection.offset(from: coordinate, to: road.end)
            let edge = Vector2(dx: end.dx - start.dx, dy: end.dy - start.dy)
            let lengthSquared = edge.dx * edge.dx + edge.dy * edge.dy
            guard lengthSquared > 0 else { continue }

            // Project the origin (0,0, since `start`/`end` are already
            // relative to `coordinate`) onto the segment, clamped to it.
            let t = max(0, min(1, -(start.dx * edge.dx + start.dy * edge.dy) / lengthSquared))
            let closest = Vector2(dx: start.dx + edge.dx * t, dy: start.dy + edge.dy * t)
            let distance = hypot(closest.dx, closest.dy)
            guard distance <= maxDistanceMeters else { continue }
            guard best == nil || distance < best!.distance else { continue }

            let length = lengthSquared.squareRoot()
            let direction = Vector2(dx: edge.dx / length, dy: edge.dy / length)
            let point = WorldProjection.coordinate(from: coordinate, offset: closest)
            best = (distance, point, direction)
        }

        guard let best else { return nil }
        return (best.point, best.direction)
    }
}

enum RoadNetworkServiceError: LocalizedError {
    case invalidCoordinates
    case requestFailed

    var errorDescription: String? {
        switch self {
        case .invalidCoordinates:
            return "Couldn't build a road data request for this location."
        case .requestFailed:
            return "Couldn't reach the road data service."
        }
    }
}
