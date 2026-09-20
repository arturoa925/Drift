//
//  SunCalculator.swift
//  Dritft
//
//  Created by Arturo Ayala on 5/28/26.
//

import Foundation

/// Calculates sunrise/sunset for a location and date entirely offline (no
/// network needed), using the standard sunrise equation
/// (https://en.wikipedia.org/wiki/Sunrise_equation). Also owns bucketing
/// "now" into a `TimeOfDayCondition` — per the split agreed with
/// ThemeEngine, SunCalculator decides what time of day it *is*, ThemeEngine
/// only decides what a time of day (or weather) *looks like*.
///
/// Accurate to within a minute or two for most latitudes; not reliable
/// inside the polar circles, where the sun may not rise or set at all on
/// a given day (handled by falling back to solar noon so callers still get
/// sane, ordered Dates instead of crashing).
enum SunCalculator {
    /// How long the sunrise/sunset condition lingers around the actual
    /// sunrise/sunset moment before switching to midday/night.
    private static let transitionWindow: TimeInterval = 60 * 60

    static func condition(at date: Date, latitude: Double, longitude: Double) -> TimeOfDayCondition {
        let times = sunTimes(on: date, latitude: latitude, longitude: longitude)

        let sunriseWindow = (times.sunrise - transitionWindow)...(times.sunrise + transitionWindow)
        let sunsetWindow = (times.sunset - transitionWindow)...(times.sunset + transitionWindow)

        if sunriseWindow.contains(date) {
            return .sunrise
        }
        if sunsetWindow.contains(date) {
            return .sunset
        }
        if date > sunriseWindow.upperBound && date < sunsetWindow.lowerBound {
            return .midday
        }
        return .night
    }

    static func sunTimes(on date: Date, latitude: Double, longitude: Double) -> (sunrise: Date, sunset: Date) {
        let daysSinceJ2000 = julianDay(for: date) - 2451545.0 + 0.0008

        // Longitude here is east-positive (matching CLLocationCoordinate2D),
        // so subtracting it directly gives the mean solar noon in Julian
        // days: locations west of Greenwich see solar noon later in UTC.
        let meanSolarNoon = daysSinceJ2000 - longitude / 360

        let solarMeanAnomalyDegrees = (357.5291 + 0.98560028 * meanSolarNoon)
            .truncatingRemainder(dividingBy: 360)
        let solarMeanAnomaly = solarMeanAnomalyDegrees * .pi / 180

        let equationOfCenter = 1.9148 * sin(solarMeanAnomaly)
            + 0.0200 * sin(2 * solarMeanAnomaly)
            + 0.0003 * sin(3 * solarMeanAnomaly)

        let eclipticLongitudeDegrees = (solarMeanAnomalyDegrees + equationOfCenter + 180 + 102.9372)
            .truncatingRemainder(dividingBy: 360)
        let eclipticLongitude = eclipticLongitudeDegrees * .pi / 180

        let solarTransit = 2451545.0 + meanSolarNoon
            + 0.0053 * sin(solarMeanAnomaly)
            - 0.0069 * sin(2 * eclipticLongitude)

        let declination = asin(sin(eclipticLongitude) * sin(23.4397 * .pi / 180))
        let latitudeRadians = latitude * .pi / 180

        // -0.833° accounts for atmospheric refraction and the sun's radius.
        let sunriseElevation = -0.833 * .pi / 180
        let cosHourAngle = (sin(sunriseElevation) - sin(latitudeRadians) * sin(declination))
            / (cos(latitudeRadians) * cos(declination))

        guard cosHourAngle >= -1, cosHourAngle <= 1 else {
            // Polar day or polar night — the sun doesn't cross the horizon
            // today. Fall back to solar noon for both so callers still get
            // ordered, sane Dates.
            let noon = Self.date(fromJulianDay: solarTransit)
            return (sunrise: noon, sunset: noon)
        }

        let hourAngleDegrees = acos(cosHourAngle) * 180 / .pi

        return (
            sunrise: Self.date(fromJulianDay: solarTransit - hourAngleDegrees / 360),
            sunset: Self.date(fromJulianDay: solarTransit + hourAngleDegrees / 360)
        )
    }

    private static func julianDay(for date: Date) -> Double {
        date.timeIntervalSince1970 / 86400 + 2440587.5
    }

    private static func date(fromJulianDay julianDay: Double) -> Date {
        Date(timeIntervalSince1970: (julianDay - 2440587.5) * 86400)
    }
}
