//
//  WeatherService.swift
//  Dritft
//
//  Created by Arturo Ayala on 5/28/26.
//

import Combine
import Foundation

/// Fetches current weather from Open-Meteo (free, no API key, no auth) and
/// exposes it as Drift's own `WeatherCondition`. This is the piece
/// `MapModel` is still missing — once wired in, `weatherCondition` stops
/// being pinned to `.sunny` and the theme can actually reflect rain, snow,
/// storm, or fog.
///
/// Deliberately doesn't poll on its own — weather doesn't need per-minute
/// freshness the way `SunCalculator`'s time-of-day bucketing does, and a
/// free API with no key is the kind of thing you don't want to hammer.
/// Whatever owns this (eventually `MapModel`) decides when to call
/// `refresh`.
@MainActor
final class WeatherService: ObservableObject {
    @Published private(set) var condition: WeatherCondition = .sunny
    @Published private(set) var error: Error?

    private let session: URLSession

    init(session: URLSession = .shared) {
        self.session = session
    }

    /// Convenience for the common case: refresh straight from a
    /// `LocationManager` snapshot.
    func refresh(for location: DeviceLocation) async {
        await refresh(latitude: location.latitude, longitude: location.longitude)
    }

    func refresh(latitude: Double, longitude: Double) async {
        do {
            let url = try Self.forecastURL(latitude: latitude, longitude: longitude)
            let (data, response) = try await session.data(from: url)

            guard let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode == 200 else {
                throw WeatherServiceError.requestFailed
            }

            let decoded = try JSONDecoder().decode(WeatherResponse.self, from: data)
            condition = decoded.condition
            error = nil
        } catch {
            self.error = error
        }
    }

    private static func forecastURL(latitude: Double, longitude: Double) throws -> URL {
        var components = URLComponents(string: "https://api.open-meteo.com/v1/forecast")
        components?.queryItems = [
            URLQueryItem(name: "latitude", value: String(latitude)),
            URLQueryItem(name: "longitude", value: String(longitude)),
            URLQueryItem(name: "current", value: "weather_code"),
        ]
        guard let url = components?.url else {
            throw WeatherServiceError.invalidCoordinates
        }
        return url
    }
}

enum WeatherServiceError: LocalizedError {
    case invalidCoordinates
    case requestFailed

    var errorDescription: String? {
        switch self {
        case .invalidCoordinates:
            return "Couldn't build a weather request for this location."
        case .requestFailed:
            return "Couldn't reach the weather service."
        }
    }
}
