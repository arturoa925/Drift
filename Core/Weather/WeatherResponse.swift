//
//  WeatherResponse.swift
//  Dritft
//
//  Created by Arturo Ayala on 5/28/26.
//

import Foundation

/// Decodes Open-Meteo's `/v1/forecast` response. Only pulls the `current`
/// block's WMO weather code — that's the only field `WeatherService` needs
/// to answer "what's the `WeatherCondition` right now."
struct WeatherResponse: Decodable {
    let current: Current

    struct Current: Decodable {
        let weatherCode: Int

        enum CodingKeys: String, CodingKey {
            case weatherCode = "weather_code"
        }
    }
}

extension WeatherResponse {
    /// Maps Open-Meteo's WMO weather interpretation codes
    /// (https://open-meteo.com/en/docs, "WMO Weather interpretation codes")
    /// down to Drift's own four-condition model. `WeatherCondition` only
    /// distinguishes "strong" conditions from clear/cloudy, so most of
    /// Open-Meteo's codes collapse into far fewer buckets than it reports.
    var condition: WeatherCondition {
        switch current.weatherCode {
        case 45, 48:
            return .fog
        case 51, 53, 55, 56, 57, 61, 63, 65, 66, 67, 80, 81, 82:
            return .rain
        case 71, 73, 75, 77, 85, 86:
            return .snow
        case 95, 96, 99:
            return .storm
        default:
            // 0-3 (clear through overcast) and any code Open-Meteo adds
            // later that we don't recognize both fall back to sunny — the
            // same "don't override time-of-day" behavior as .sunny itself.
            return .sunny
        }
    }
}
