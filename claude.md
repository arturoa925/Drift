# Drift · Project Context for Claude

> Paste this file at the start of any new conversation to give Claude full context on the Drift app.

---

## What is Drift?

Drift is an iOS map app built with SwiftUI. The core idea: the map is alive. Instead of a static, utilitarian map, Drift presents the world through a continuously shifting atmospheric gradient that responds to time of day, weather conditions, location, and the user's movement. Buildings and roads are rendered at low opacity (~15–18%) so they feel like whispers on the canvas rather than solid objects. The gradient underneath does all the emotional work.

The name "Drift" was chosen because it signals motion without urgency — poetic, dreamy, no destination pressure. It's the opposite of Google Maps or Apple Maps in feeling.

---

## Design Identity

**Name:** Drift  
**Tagline:** the world, beautifully alive  
**Feeling:** Poetic and dreamy — like the world is beautiful  
**Font:** DM Sans — weights 200 (wordmark), 300/400/500 (UI)  
**Wordmark:** lowercase · font-weight 200 · letter-spacing -0.03em

### App Icon
- Shape: Abstract geometric — three parallel wave strokes
- Gradient direction: top-left → bottom-right (135°)
- Gradient stops: #6D28D9 (0%) → #C026D3 (38%) → #F97316 (72%) → #FDE68A (100%)
- Wave 1: rgba(255,255,255,.92) · 4.5px stroke · round linecap
- Wave 2: rgba(255,255,255,.55) · 3.5px stroke
- Wave 3: rgba(255,255,255,.26) · 2.5px stroke
- SVG viewBox: 0 0 120 120
- Wave paths: M22 42 C46 22, 74 58, 98 38 / M22 58 C46 38, 74 74, 98 54 / M22 74 C46 54, 74 90, 98 70

---

## Theme System

Drift's visual identity is driven by one function that takes two inputs — **time of day** and **weather condition** — and outputs a `MapTheme` (gradient colors + layer opacities). The gradient runs full screen height, top to bottom, with no hard stops.

### Theme priority stack (highest → lowest)
1. Weather condition (when strong: rain, snow, storm, fog override time)
2. Time of day (always available, the baseline)
3. Location/district (future: subtle tint modifier)
4. Speed/motion (controls animation behavior, not color)

### Theme gradients (all linear, top → bottom, full height)

| Condition | Stop 0% | Stop ~30% | Stop ~55% | Stop ~80% | Stop 100% |
|-----------|---------|-----------|-----------|-----------|-----------|
| Sunrise | #6D28D9 | #C026D3 | #F97316 | #FDE68A | — |
| Sunny/Clear | #FDE68A | #FBBF24 | #FB923C | #BAE6FD | #E0F2FE |
| Sunset | #1E1B4B | #4C1D95 | #BE185D | #F97316 | #FECACA |
| Night | #1E3A5F | #2D5282 | #3B6FA0 | #C7DCF5 | #E8F2FC |
| Rain | #6B7A8D | #8D9DAD | #A8B8C4 | #D4DDE5 | #E8EEF3 |
| Snow | #93C5FD | #BFDBFE | #DBEAFE | #EFF6FF | #FFFFFF |
| Fog | #94A3B8 | #B0BEC5 | #CBD5DC | #DFE6EC | #EEF2F5 |
| Storm | #5B4E7E | #7C6A9E | #9B82B5 | #C8B8D8 | #E8DFF4 |

**Design rule:** Even at night or in a storm, themes never go fully dark. The bottom of the gradient always fades to a light, pale tone. The goal is atmospheric, never oppressive.

**Snow exception:** Snow uses near-white at the bottom, so all text on snow themes flips to dark: `rgba(30, 80, 160, .75)` instead of white.

### Map layer opacities (constant regardless of theme)
- Roads (horizontal): `rgba(180, 180, 190, 0.16)` · 7–8px height · radius 2px
- Roads (vertical): `rgba(180, 180, 190, 0.13)` · 7–8px width
- Buildings: `rgba(180, 185, 195, 0.15)` · radius 3px
- These never change color with weather. Low opacity means the gradient bleeds through, creating a natural "lit from within" effect.

---

## Heatmap

Activity density shown as three concentric circles. Color inherits from the active theme.

| Theme | Outer (r=30) | Mid (r=19) | Core (r=10) |
|-------|-------------|------------|-------------|
| Sunny | rgba(251,146,60,.20) | rgba(251,146,60,.32) | rgba(251,146,60,.45) |
| Night | rgba(59,111,160,.25) | rgba(59,111,160,.38) | rgba(186,230,253,.50) |
| Storm | rgba(124,106,158,.28) | rgba(124,106,158,.42) | rgba(200,184,216,.55) |
| Rain | rgba(160,175,190,.22) | rgba(160,175,190,.34) | rgba(200,215,225,.48) |
| Snow | rgba(147,197,253,.22) | rgba(147,197,253,.35) | rgba(219,234,254,.52) |
| Sunrise | rgba(217,70,119,.20) | rgba(217,70,119,.32) | rgba(249,168,212,.48) |

---

## Movement Trail

A fading dashed path that traces behind the user for ~3 seconds then dissolves.

- Segment 1 (fresh): 2.5px stroke · dash 4px gap 3px · opacity 0.85
- Segment 2 (fading): 2px stroke · dash 3px gap 4px · opacity 0.38
- Trail color inherits theme: sunny=rgba(251,191,36,.68) · night=rgba(186,230,253,.75) · storm=rgba(200,180,230,.80) · snow=rgba(186,210,240,.72) · rain=rgba(180,195,210,.65) · sunrise=rgba(254,240,138,.70)

---

## User Pulse Dot

- Dot size: 10×10px · border-radius 50%
- Color: white on most themes · #BAE6FD (night) · #D8B4FE (storm) · white (snow)
- Shadow ring: `0 0 0 3px rgba(255,255,255,.30)`
- Pulse ring: 26×26px · 1.5px border rgba(255,255,255,.45)
- Animation: scale 1.0→1.22, opacity 0.40→0.88
- Speed-aware duration: still=3.4s · walking=2.2s · biking=1.0–1.2s

---

## Map Sway

The map subtly rotates/tilts in the direction of travel.

- Driven by `CMMotionManager` heading + `CLLocationManager` speed
- Walking: gentle sway ±1.5°
- Biking: faster sway ±3°
- Still: no sway
- Implementation: `SwayModifier.swift` using `.rotationEffect()`

---

## Floating Pill (UI Component)

All controls on the map float as frosted glass pills.

- Background: `rgba(255,255,255, 0.16)`
- Border: `0.5px rgba(255,255,255, 0.28)`
- Border radius: 50px
- Backdrop blur: `blur(10px)` / `.ultraThinMaterial` in SwiftUI
- Text: 10px · weight 500 · rgba(255,255,255,.90)
- Sub/unit text: rgba(255,255,255,.48)
- Icon size: 11–12px

### Pill positions on main map
- Weather + time: top center · y=24px
- Settings: top right · y=22px · 30×30px circle
- Speed: bottom left · 28px from bottom
- Search: bottom center · flex fill
- Layers: bottom right · 32×32px
- Bottom row gap: 7px

---

## Screens

### Onboarding (3 screens)
1. **Welcome** — wordmark only ("drift") centered on gradient. No icon. Tagline: "the world, beautifully alive". CTA: "get started"
2. **Theme mode** — three options: Automatic / My preference / Surprise me. Radio select. CTA: "continue"
   - 2b. **Preference sub-screen** (if "My preference" selected) — toggle between "time of day" and "weather" tabs. Scrollable list of theme swatches.
3. **Permissions** — contextual based on theme mode chosen (see permission logic below)

### Permission logic
| Mode | Permissions | Screen |
|------|-------------|--------|
| Automatic | Location (needed) + Weather (needed) + Motion (optional) | Yes — 3 rows |
| Preference → time of day | None | No — "you're all set" screen |
| Preference → weather | Location (needed) + Weather (needed) | Yes — 2 rows + trust note |
| Surprise me | Location (optional) | Yes — 1 row + fallback note |

All permission screens have a quiet "skip for now" link below the CTA.

### Main map screen
- Full screen map
- Gradient layer (full height) → map overlay (roads + buildings at low opacity) → heatmap → trail → pulse dot → floating controls
- Top center pill: weather icon + condition + time
- Top right: settings icon pill
- Bottom row: speed pill (left) + search bar (flex) + layers button (right)
- Search allows place search only — NO directions (requires paid Apple developer account)
- Speed pill icon auto-switches: 🚶 walking / 🚲 biking

### Settings screen
Three sections:
1. **Theme** — theme mode (tappable, goes to mode picker) · heatmap toggle (on) · movement trail toggle (on)
2. **Motion** — map sway toggle (on) · pulse animation toggle (on)
3. **Privacy** — pause location toggle (off, freezes theme in place) · hide trail toggle (off)
Footer: "about drift · v0.1 · made with care"

### Apple Watch face (planned, not in phase 1)
- Three elements only: time (top, weight 200) · pulse dot (center) · speed (bottom, weight 300)
- No condition label — the gradient communicates weather visually
- Same gradient system as iPhone, matching active theme
- Pulse ring speed matches motion state

---

## Technical Stack

- **Platform:** iOS (iPhone first, Watch later)
- **Framework:** SwiftUI only
- **Architecture:** MVVM
- **Maps:** MapKit (free with Apple developer account, no routing on free account)
- **Location:** CoreLocation (`CLLocationManager`)
- **Motion:** CoreMotion (`CMMotionManager`)
- **Weather:** Open-Meteo API (free, no auth required) for phase 1. WeatherKit (requires paid account) for later.
- **Sun times:** Calculated locally from lat/lng + date (no API needed)
- **Persistence:** `@AppStorage` for user preferences

---

## File Architecture

```
Drift/
├── DriftApp.swift                    — @main entry point
├── ContentView.swift                 — root routing (onboarding vs map)
│
├── Core/
│   ├── Theme/
│   │   ├── ThemeEngine.swift         — computes MapTheme from inputs
│   │   ├── ThemeModel.swift          — MapTheme struct
│   │   ├── WeatherCondition.swift    — enum: sunny, rain, snow, storm, fog
│   │   └── TimeOfDayCondition.swift  — enum: sunrise, midday, sunset, night
│   ├── Location/
│   │   ├── LocationManager.swift     — CLLocationManager wrapper
│   │   └── SunCalculator.swift       — sunrise/sunset for location + date
│   ├── Weather/
│   │   ├── WeatherService.swift      — fetches condition from Open-Meteo
│   │   └── WeatherResponse.swift     — decodable API model
│   ├── Motion/
│   │   ├── MotionManager.swift       — CMMotionManager wrapper
│   │   └── MovementState.swift       — enum: still, walking, biking
│   └── Persistence/
│       └── UserPreferences.swift     — @AppStorage keys + theme mode
│
├── Features/
│   ├── Onboarding/
│   │   ├── OnboardingViewModel.swift
│   │   ├── OnboardingView.swift      — page container + dot indicator
│   │   ├── WelcomeView.swift         — screen 01
│   │   ├── ThemeModeView.swift       — screen 02
│   │   ├── PreferencePickerView.swift — screen 02b
│   │   └── PermissionsView.swift     — screen 03 (contextual)
│   ├── Map/
│   │   ├── MapViewModel.swift        — owns theme, location, motion
│   │   ├── MapView.swift             — root map screen
│   │   ├── MapGradientLayer.swift    — full-screen animated gradient
│   │   ├── MapOverlayView.swift      — roads + buildings (low opacity)
│   │   ├── HeatmapOverlay.swift      — themed concentric circles
│   │   ├── TrailOverlay.swift        — fading dashed movement path
│   │   └── UserPulseView.swift       — dot + speed-aware ring
│   ├── Controls/
│   │   ├── TopPillView.swift         — weather + time pill
│   │   ├── BottomControlsView.swift  — speed + search + layers
│   │   ├── SpeedPillView.swift       — walk/bike + km/h
│   │   └── SearchBarView.swift       — place search only
│   └── Settings/
│       ├── SettingsViewModel.swift
│       └── SettingsView.swift
│
├── UI/
│   ├── Components/
│   │   ├── FloatingPill.swift        — base frosted glass pill
│   │   ├── DriftToggle.swift         — custom toggle
│   │   ├── GradientBackground.swift  — animated LinearGradient view
│   │   └── PageIndicator.swift       — onboarding dots
│   ├── Modifiers/
│   │   ├── SwayModifier.swift        — map rotation from heading
│   │   └── PulseModifier.swift       — scale + opacity animation
│   └── Extensions/
│       ├── Color+Theme.swift         — Color helpers for gradient stops
│       └── Animation+Drift.swift     — shared animation curves
│
└── Resources/
    ├── Assets.xcassets
    ├── Info.plist                    — location + motion usage strings
    └── Localizable.strings
```

---

## Phase 1 Build Order

1. Project scaffold — DriftApp, ContentView, UserPreferences
2. Theme engine — ThemeModel, enums, ThemeEngine
3. Gradient UI — GradientBackground, MapGradientLayer, Color+Theme
4. Onboarding — all 5 onboarding views + ViewModel
5. Location & sun — LocationManager, SunCalculator, MotionManager
6. Map screen — MapViewModel, MapView, overlays, FloatingPill, controls
7. Animations — SwayModifier, PulseModifier, TrailOverlay
8. Weather & heatmap — WeatherService, HeatmapOverlay, SearchBar

---

## Key Design Decisions & Rationale

- **No app icon on welcome screen** — wordmark only, more confident and dreamy
- **No routing/directions** — requires paid Apple developer account, excluded from phase 1
- **Themes never go fully dark** — even night/storm always fade to a pale bottom tone
- **Buildings/roads constant opacity** — they never change color, only the gradient changes
- **Heatmap color inherits theme** — same activity data, different emotional expression per condition
- **Trail fades in 2 segments** — bright close segment + dim far segment, total ~3 seconds
- **Motion is optional permission** — app works beautifully without it, just no sway
- **Pause location freezes theme in place** — more respectful than reverting to a default
- **Open-Meteo for weather** — free, no auth, good enough for condition + precipitation type
- **@AppStorage for preferences** — simple, no CoreData needed for v0.1

---

## What's Planned But Not In Phase 1

- Apple Watch companion app
- Location-based district themes (e.g. entering London City shifts to modern blue)
- Business/venue custom themes when nearby
- WeatherKit integration (requires paid account)
- CarPlay support
