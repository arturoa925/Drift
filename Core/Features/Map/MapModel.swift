//
//  MapModel.swift
//  Dritft
//
//  Created by Arturo Ayala on 5/28/26.
//

import Combine
import Foundation

/// The map screen's single source of truth. Every other piece of the map —
/// gradient, sway, pulse dot, speed pill, weather/time pill — is a dumb
/// reader of state this object computes and owns. Its one real job is
/// keeping `theme` correct as the inputs that determine it (location, time,
/// weather) drift over time, without every view on screen having to
/// separately watch those inputs and recompute it themselves.
@MainActor
final class MapModel: ObservableObject {
    /// What every view on the map screen actually renders. This is the
    /// whole reason MapModel exists — a single computed answer to "what
    /// should the screen look like right now" that views just observe
    /// instead of each re-deriving it from raw sensor data.
    @Published private(set) var theme: MapTheme

    /// The half of the theme's recipe that's always available locally
    /// (unlike weather, no network call needed). Exposed on its own, not
    /// just folded into `theme`, because the weather/time pill needs to
    /// show it as text ("2:14pm") independent of the gradient it produces.
    @Published private(set) var timeOfDayCondition: TimeOfDayCondition

    /// Raw sensor/service sources. MapModel doesn't wrap or hide these — it
    /// exposes them directly so views/modifiers that need something
    /// MapModel doesn't already surface (e.g. a future SwayModifier reading
    /// raw heading, or a pill showing `weatherService.error`) can go
    /// straight to the source instead of MapModel growing a pass-through
    /// property for every single thing they might need.
    let locationManager: LocationManager
    let motionManager: MotionManager
    let weatherService: WeatherService

    var currentLocation: DeviceLocation? { locationManager.currentLocation }
    var movementState: MovementState { motionManager.movementState }

    /// The theme's other input, live off `weatherService`. Computed rather
    /// than its own `@Published` copy — same reasoning as `movementState`
    /// below: one source of truth, no risk of this drifting out of sync
    /// with what `weatherService` actually last fetched.
    var weatherCondition: WeatherCondition { weatherService.condition }

    private var cancellables: Set<AnyCancellable> = []
    private var clockTimer: Timer?
    private var weatherTimer: Timer?

    init(
        locationManager: LocationManager? = nil,
        motionManager: MotionManager? = nil,
        weatherService: WeatherService? = nil
    ) {
        // `nil` defaults instead of `= LocationManager()` — a default
        // argument expression runs outside this init's @MainActor context,
        // so it can't call these types' isolated initializers directly.
        self.locationManager = locationManager ?? LocationManager()
        self.motionManager = motionManager ?? MotionManager()
        self.weatherService = weatherService ?? WeatherService()

        // There's no GPS fix yet at launch, so neither SunCalculator nor
        // WeatherService has anything to work with. Opening on a guess
        // (midday/sunny — WeatherService's own starting value) rather than
        // leaving theme uninitialized means the screen is never in an
        // invalid state — refreshTheme() corrects it the instant a real fix
        // arrives.
        let initialTimeOfDay = TimeOfDayCondition.midday
        let initialWeather = WeatherCondition.sunny
        timeOfDayCondition = initialTimeOfDay
        theme = ThemeEngine.theme(weather: initialWeather, timeOfDay: initialTimeOfDay)

        // Everything from here on is what keeps `theme` from going stale
        // for the rest of this object's life.
        observeLocation()
        observeMotion()
        observeWeather()
        startClock()
        startWeatherClock()
    }

    /// Turns the sensors on. Kept separate from `init` because construction
    /// should stay cheap and side-effect-free — starting hardware updates
    /// belongs to the view's lifecycle (`.onAppear`), not object creation.
    ///
    /// TODO: this starts both managers unconditionally. Per claude.md's
    /// onboarding permission table, motion should only be requested in
    /// "Automatic" theme mode — that gating belongs here once
    /// UserPreferences/onboarding exist to inform the decision.
    func start() {
        locationManager.requestPermission()
        locationManager.startUpdating()
        motionManager.requestPermission()
    }

    /// The other half of the view lifecycle pairing — call from
    /// `.onDisappear` so sensors (and the clock below) don't keep running
    /// once nothing on screen needs them.
    func stop() {
        locationManager.stopUpdating()
        motionManager.stopUpdating()
        clockTimer?.invalidate()
        weatherTimer?.invalidate()
    }

    /// First of four reasons `theme` can go stale: the user moved. A new
    /// GPS fix is the most common trigger for a theme change in practice
    /// (new sunrise/sunset math for the new coordinates), so route it
    /// straight into a recompute — and it's also the only thing
    /// `WeatherService` needs to make its network call, so a fresh fix
    /// kicks off a weather refresh too.
    private func observeLocation() {
        locationManager.$currentLocation
            .sink { [weak self] location in
                self?.refreshTheme()
                guard let location else { return }
                Task { [weak self] in
                    await self?.weatherService.refresh(for: location)
                }
            }
            .store(in: &cancellables)
    }

    /// Movement doesn't change *what* the theme is — per claude.md, speed
    /// only drives animation, never color — so this never calls
    /// refreshTheme(). It exists purely so views bound to MapModel (not
    /// motionManager directly) still redraw when movementState changes,
    /// since that property is computed from motionManager rather than
    /// `@Published` on MapModel itself.
    private func observeMotion() {
        motionManager.$movementState
            .sink { [weak self] _ in self?.objectWillChange.send() }
            .store(in: &cancellables)
    }

    /// Third reason `theme` can go stale: a weather fetch completed. Unlike
    /// motion, weather really does feed `theme` (it's the condition that
    /// can override time-of-day entirely), so this recomputes for real
    /// rather than just poking `objectWillChange`.
    private func observeWeather() {
        weatherService.$condition
            .sink { [weak self] _ in self?.refreshTheme() }
            .store(in: &cancellables)
    }

    /// Second reason `theme` can go stale, time-based: the sun keeps moving
    /// even when the user doesn't. `LocationManager` only reports a new fix
    /// after 5+ meters of movement, so someone sitting still through a
    /// sunset would otherwise never see night arrive. Polling once a
    /// minute is enough to catch that — matches SunCalculator's own
    /// one-hour sunrise/sunset transition window, so there's no benefit to
    /// checking more often.
    private func startClock() {
        clockTimer = Timer.scheduledTimer(withTimeInterval: 60, repeats: true) { [weak self] _ in
            guard let self else { return }
            Task { @MainActor in self.refreshTheme() }
        }
    }

    /// Fourth reason `theme` can go stale, also time-based but far
    /// coarser: real weather can change (rain starting) with no new GPS fix
    /// at all. Polled far less often than the theme clock, though — it's a
    /// live network call against a free, unauthenticated API, and
    /// conditions don't shift minute to minute the way sun position does.
    private func startWeatherClock() {
        weatherTimer = Timer.scheduledTimer(withTimeInterval: 15 * 60, repeats: true) { [weak self] _ in
            guard let self, let location = self.currentLocation else { return }
            Task { @MainActor in
                await self.weatherService.refresh(for: location)
            }
        }
    }

    /// The one place `theme` actually gets computed — everything above
    /// exists just to call this at the right moments. Recomputes
    /// `timeOfDayCondition` only when there's a real fix to compute it
    /// from; otherwise leaves it alone rather than reverting to a
    /// placeholder.
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
        // Belt-and-suspenders: guarantees both timers die even if a view
        // disappears without ever calling `stop()`.
        clockTimer?.invalidate()
        weatherTimer?.invalidate()
    }
}
