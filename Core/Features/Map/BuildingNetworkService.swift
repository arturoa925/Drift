//
//  BuildingNetworkService.swift
//  Dritft
//
//  Created by Arturo Ayala on 10/8/26.
//

import Combine
import CoreLocation
import Foundation

/// Fetches real building footprints + use tags from OpenStreetMap, via the
/// Overpass API — same pattern as `RoadNetworkService`, and deliberately
/// structured almost identically to it. Replaces `PlaceholderCityGenerator`
/// as `MapView`'s live building source; `PlaceholderCityGenerator` still
/// exists for `WorldView`'s offline `#Preview`.
///
/// Placeholder buildings were seeded independently of real road geometry,
/// so they'd routinely land in the middle of an actual street — this is
/// what fixes that, by using the same real-world footprints OSM has for
/// roads.
@MainActor
final class BuildingNetworkService: ObservableObject {
    @Published private(set) var buildings: [BuildingShape] = []
    @Published private(set) var error: Error?

    private let fetchPadding: Double = 2.0

    private var lastFetchOrigin: CLLocationCoordinate2D?
    private var lastFetchRadiusMeters: Double = 0
    private var inFlightTask: Task<Void, Never>?

    private let session: URLSession

    init(session: URLSession = .shared) {
        self.session = session
    }

    /// Called on every GPS fix — see `RoadNetworkService.refresh` for why
    /// this stays silent on the (overwhelmingly common) no-op path.
    func refresh(near origin: CLLocationCoordinate2D, radiusMeters: Double) async {
        guard inFlightTask == nil else { return }
        guard !isCovered(origin: origin, radiusMeters: radiusMeters) else { return }

        let fetchRadius = radiusMeters * fetchPadding
        print("BuildingNetworkService: fetching near \(origin.latitude), \(origin.longitude), radius \(fetchRadius)m")
        let task = Task { [weak self] in
            guard let self else { return }
            await self.fetch(near: origin, radiusMeters: fetchRadius)
        }
        inFlightTask = task
        await task.value
        inFlightTask = nil
    }

    private func isCovered(origin: CLLocationCoordinate2D, radiusMeters: Double) -> Bool {
        guard let lastFetchOrigin else { return false }
        let distanceMoved = hypot(
            WorldProjection.offset(from: lastFetchOrigin, to: origin).dx,
            WorldProjection.offset(from: lastFetchOrigin, to: origin).dy
        )
        return distanceMoved + radiusMeters <= lastFetchRadiusMeters
    }

    /// Same public mirrors `RoadNetworkService` uses, raced the same way —
    /// see its `endpoints` doc comment for why racing instead of trying
    /// them in sequence is what actually saves wall-clock time here.
    private static let endpoints = [
        "https://overpass-api.de/api/interpreter",
        "https://overpass.kumi.systems/api/interpreter",
        "https://overpass.openstreetmap.fr/api/interpreter",
    ]

    private static let maxAttempts = 3
    private static let retryDelaySeconds: UInt64 = 2
    private static let requestTimeoutSeconds: TimeInterval = 10

    private func fetch(near origin: CLLocationCoordinate2D, radiusMeters: Double) async {
        var lastError: Error = BuildingNetworkServiceError.requestFailed
        for attempt in 1...Self.maxAttempts {
            do {
                let (data, endpoint) = try await raceEndpoints(near: origin, radiusMeters: radiusMeters)
                let decoded = try JSONDecoder().decode(OverpassResponse.self, from: data)
                buildings = Self.buildings(from: decoded.elements)
                lastFetchOrigin = origin
                lastFetchRadiusMeters = radiusMeters
                error = nil
                print("BuildingNetworkService: fetched \(decoded.elements.count) ways, \(buildings.count) buildings from \(endpoint)")
                return
            } catch {
                lastError = error
            }
            if attempt < Self.maxAttempts {
                try? await Task.sleep(nanoseconds: Self.retryDelaySeconds * 1_000_000_000)
            }
        }
        // Leave `buildings` as the last successful fetch rather than
        // clearing it — same reasoning as `RoadNetworkService.fetch`.
        error = lastError
    }

    /// See `RoadNetworkService.raceEndpoints` — identical strategy, fires
    /// every endpoint at once and returns whichever answers first.
    private func raceEndpoints(near origin: CLLocationCoordinate2D, radiusMeters: Double) async throws -> (Data, String) {
        try await withThrowingTaskGroup(of: (Data, String).self) { group in
            for endpoint in Self.endpoints {
                group.addTask {
                    let data = try await self.fetch(endpoint: endpoint, near: origin, radiusMeters: radiusMeters)
                    return (data, endpoint)
                }
            }

            var lastError: Error = BuildingNetworkServiceError.requestFailed
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
        request.setValue("Dritft/1.0 (iOS)", forHTTPHeaderField: "User-Agent")
        request.timeoutInterval = Self.requestTimeoutSeconds
        let (data, response) = try await session.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode == 200 else {
            let status = (response as? HTTPURLResponse)?.statusCode ?? -1
            print("BuildingNetworkService: non-200 response from \(endpoint), status \(status)")
            throw BuildingNetworkServiceError.requestFailed
        }
        return data
    }

    /// Minor structures, excluded at the query level so Overpass never
    /// sends them down in the first place — sheds, garages, carports, and
    /// the like, which are "a building" by OSM's tagging but not what
    /// "most major or important buildings" means.
    private static let minorBuildingValues = "shed|garage|garages|carport|roof|greenhouse|hut|cabin|static_caravan|houseboat|toilets|service|ruins|construction|bunker|silo|stable|barn|allotment_house"

    private static func overpassURL(endpoint: String, near origin: CLLocationCoordinate2D, radiusMeters: Double) throws -> URL {
        let query = """
        [out:json][timeout:25];
        way(around:\(radiusMeters),\(origin.latitude),\(origin.longitude))[building][building!~"^(\(minorBuildingValues))$"];
        out geom;
        """
        var components = URLComponents(string: endpoint)
        components?.queryItems = [URLQueryItem(name: "data", value: query)]
        guard let url = components?.url else {
            throw BuildingNetworkServiceError.invalidCoordinates
        }
        return url
    }

    /// Building footprints only come as closed ways here — no relations
    /// (multipolygons with holes), which covers the vast majority of OSM
    /// buildings and keeps this matching `RoadSegment`'s "ways only" scope.
    private static func buildings(from elements: [OverpassElement]) -> [BuildingShape] {
        var result: [BuildingShape] = []
        for element in elements {
            guard let geometry = element.geometry, geometry.count >= 4 else { continue }
            var points = geometry.map { CLLocationCoordinate2D(latitude: $0.lat, longitude: $0.lon) }
            // A closed way repeats its first node as its last — drop the
            // duplicate so `footprint` is a plain polygon vertex list, the
            // same shape `PlaceholderCityGenerator.rectangleFootprint`
            // already hands `WorldView`.
            if let first = points.first, let last = points.last,
               first.latitude == last.latitude, first.longitude == last.longitude {
                points.removeLast()
            }
            guard points.count >= 3 else { continue }
            // Catches small structures that don't carry one of the
            // `minorBuildingValues` tags the query already excludes — e.g.
            // an untagged/generic `building=yes` shed. 20sqm sits below a
            // real single-car garage (~15-20sqm) and well below even a
            // small home's footprint, so this is a floor on "not a shed,"
            // not a judgment on house size.
            guard footprintAreaMeters(points) >= 20 else { continue }

            let tags = element.tags ?? [:]
            result.append(BuildingShape(
                id: "\(element.id)",
                footprint: counterClockwise(points),
                height: height(from: tags),
                swayPhase: swayPhase(for: element.id),
                category: category(from: tags)
            ))
        }
        return result
    }

    /// `WorldView.draw` backface-culls each wall assuming the footprint
    /// winds counter-clockwise (east=+x, north=+y) — true by construction
    /// for `PlaceholderCityGenerator`'s rectangles, but OSM way geometry
    /// has no guaranteed winding direction at all. Left as-is, a
    /// clockwise-wound building has every wall's cull test inverted,
    /// which can mean every wall (and the roof) gets skipped — the
    /// building fetches fine and just silently draws nothing. The
    /// shoelace formula's sign says which way `points` already winds;
    /// reverse it when that sign says clockwise.
    private static func counterClockwise(_ points: [CLLocationCoordinate2D]) -> [CLLocationCoordinate2D] {
        var signedArea = 0.0
        for index in 0..<points.count {
            let next = (index + 1) % points.count
            signedArea += points[index].longitude * points[next].latitude
            signedArea -= points[next].longitude * points[index].latitude
        }
        return signedArea < 0 ? points.reversed() : points
    }

    /// Shoelace area in real square meters — same degree-space formula
    /// `counterClockwise` uses for its sign, but converted to meters via
    /// the two independent per-axis scale factors (longitude's and
    /// latitude's meters-per-degree). Scaling x and y independently by
    /// positive constants scales area by their product, so this is exact,
    /// not an approximation.
    private static func footprintAreaMeters(_ points: [CLLocationCoordinate2D]) -> Double {
        guard let first = points.first else { return 0 }
        var signedArea = 0.0
        for index in 0..<points.count {
            let next = (index + 1) % points.count
            signedArea += points[index].longitude * points[next].latitude
            signedArea -= points[next].longitude * points[index].latitude
        }
        let degreeArea = abs(signedArea) / 2
        let metersPerDegreeLongitude = WorldProjection.metersPerDegreeLongitude(atLatitude: first.latitude)
        return degreeArea * metersPerDegreeLongitude * WorldProjection.metersPerDegreeLatitude
    }

    /// Prefers an explicit `height` tag (meters, sometimes suffixed like
    /// "12 m" — trimmed before parsing); falls back to `building:levels` *
    /// an assumed 3m-per-floor; falls back again to a flat category-based
    /// guess when OSM has neither, which is common for residential ways.
    private static func height(from tags: [String: String]) -> Double {
        if let heightTag = tags["height"],
           let value = Double(heightTag.trimmingCharacters(in: CharacterSet.letters.union(.whitespaces))) {
            return value
        }
        if let levelsTag = tags["building:levels"], let levels = Double(levelsTag) {
            return levels * 3
        }
        switch category(from: tags) {
        case .residential: return 9
        case .commercial: return 14
        case .other: return 11
        }
    }

    /// Residential vs. commercial vs. everything else, read off whichever
    /// OSM tag actually says so. `shop`/`office` and a business-flavored
    /// `amenity` are the strongest signal (a building can be tagged
    /// `building=yes` but still clearly be a business by what's inside
    /// it), checked before falling back to the `building` tag itself.
    private static func category(from tags: [String: String]) -> BuildingCategory {
        if tags["shop"] != nil || tags["office"] != nil {
            return .commercial
        }
        if let amenity = tags["amenity"], Self.commercialAmenities.contains(amenity) {
            return .commercial
        }
        if let building = tags["building"] {
            if Self.residentialBuildingValues.contains(building) {
                return .residential
            }
            if Self.commercialBuildingValues.contains(building) {
                return .commercial
            }
        }
        return .other
    }

    private static let residentialBuildingValues: Set<String> = [
        "house", "residential", "apartments", "detached", "semidetached_house",
        "terrace", "bungalow", "dormitory", "houseboat", "static_caravan", "yes",
    ]

    private static let commercialBuildingValues: Set<String> = [
        "commercial", "retail", "office", "supermarket", "kiosk", "warehouse",
    ]

    private static let commercialAmenities: Set<String> = [
        "restaurant", "cafe", "bar", "pub", "fast_food", "bank", "pharmacy",
        "fuel", "cinema", "theatre", "marketplace", "nightclub", "food_court",
    ]

    /// Same determinism requirement `PlaceholderCityGenerator.swayPhase`
    /// has — a stable value per building ID, not per-launch randomness,
    /// derived from the OSM way ID itself rather than a separate RNG.
    private static func swayPhase(for elementID: Int) -> Double {
        var rng = SeededGenerator(seed: UInt64(bitPattern: Int64(elementID)))
        return Double.random(in: 0..<1, using: &rng)
    }
}

enum BuildingNetworkServiceError: LocalizedError {
    case invalidCoordinates
    case requestFailed

    var errorDescription: String? {
        switch self {
        case .invalidCoordinates:
            return "Couldn't build a building data request for this location."
        case .requestFailed:
            return "Couldn't reach the building data service."
        }
    }
}
