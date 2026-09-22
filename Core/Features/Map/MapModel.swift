//
//  MapModel.swift
//  Dritft
//
//  Created by Arturo Ayala on 5/28/26.
//

import Combine
import Foundation

/// Owns the map screen's state: the active `MapTheme`, and the
/// `LocationManager`/`MotionManager` instances everything else on screen
/// (gradient, sway, pulse dot, speed pill) reads from. Doesn't own weather
/// fetching itself — `WeatherService` isn't built yet, so `weatherCondition`
/// stays pinned to `.sunny` (time-of-day-only theming) until that lands.
@MainActor
final class MapModel: ObservableObject {
    @Published private(set) var theme: MapTheme
    @Published private(set) var timeOfDayCondition: TimeOfDayCondition
    @Published private(set) var weatherCondition: WeatherCondition

    let locationManager: LocationManager
    let motionManager: MotionManager

    var currentLocation: DeviceLocation? { locationManager.currentLocation }
    var movementState: MovementState { motionManager.movementState }

    private var cancellables: Set<AnyCancellable> = []
    private var clockTimer: Timer?

    // Default parameter *expressions* are evaluated in a nonisolated
    // context even though this init's body is @MainActor, so `LocationManager()`
    // can't be a default argument directly — nil defaults sidestep that.
    init(locationManager: LocationManager? = nil, motionManager: MotionManager? = nil) {
        self.locationManager = locationManager ?? LocationManager()
        self.motionManager = motionManager ?? MotionManager()

        // No location fix exists yet at launch, so there's nothing to feed
        // SunCalculator. Midday is the least jarring guess — closer to
        // "no theme yet" than opening on night or sunset would be. Computed
        // as locals rather than through `self`, since `self` isn't fully
        // initialized until `theme` itself is assigned below.
        let initialTimeOfDay = TimeOfDayCondition.midday
        let initialWeather = WeatherCondition.sunny
        timeOfDayCondition = initialTimeOfDay
        weatherCondition = initialWeather
        theme = ThemeEngine.theme(weather: initialWeather, timeOfDay: initialTimeOfDay)

        observeLocation()
        observeMotion()
        startClock()
    }

    /// Call once the map screen appears. Permission gating by theme mode
    /// (see claude.md's onboarding table) belongs to whatever calls this —
    /// this just starts both managers unconditionally.
    func start() {
        locationManager.requestPermission()
        locationManager.startUpdating()
        motionManager.requestPermission()
    }

    func stop() {
        locationManager.stopUpdating()
        motionManager.stopUpdating()
        clockTimer?.invalidate()
    }

    private func observeLocation() {
        locationManager.$currentLocation
            .sink { [weak self] _ in self?.refreshTheme() }
            .store(in: &cancellables)
    }

    private func observeMotion() {
        // MapView's sway/pulse modifiers read motionManager.movementState
        // directly, but MapModel still needs to republish so anything bound
        // to *this* object (like a theme-driven overlay) redraws too.
        motionManager.$movementState
            .sink { [weak self] _ in self?.objectWillChange.send() }
            .store(in: &cancellables)
    }

    private func startClock() {
        // The theme can drift (sunset → night) with no new location fix at
        // all — e.g. sitting still on a park bench — so recompute on a timer
        // too. One minute matches SunCalculator's transition-window
        // granularity; no point polling faster than that.
        clockTimer = Timer.scheduledTimer(withTimeInterval: 60, repeats: true) { [weak self] _ in
            guard let self else { return }
            Task { @MainActor in self.refreshTheme() }
        }
    }

    private func refreshTheme() {
        if let location = currentLocation {
            timeOfDayCondition = SunCalculator.condition(
                at: Date(),
                latitude: location.latitude,
                longitude: location.longitude
            )
        }
        theme = ThemeEngine.theme(weather: weatherCondition, timeOfDay: timeOfDayCondition)
    }

    deinit {
        clockTimer?.invalidate()
    }
}
