# drift

**the world, beautifully alive**

Drift is an iOS map app that treats the map as something alive rather than a utility. Instead of a flat, static map, it shows the world from street level over a full-screen atmospheric gradient that shifts with the **time of day**, the **weather**, and your **movement**. Real streets and buildings from OpenStreetMap are drawn as soft, low-opacity shapes, so the gradient does most of the emotional work.

It's built to feel like the opposite of Google Maps: motion without urgency and no pressure to get anywhere.

> 🤖 **My first project built entirely by prompting AI.** See [Built with AI](#built-with-ai) below.

> 🚧 **Work in progress.** The theme engine, sensors, weather, and street-level renderer are working. Onboarding, settings, and the floating controls are still stubs. See [Status](#status).

---

## Built with AI

Drift is the first project I've built **entirely through AI prompting**. In my other apps ([Launch Control](https://github.com/arturoa925/Daily-Protocol), [Axis](https://github.com/arturoa925/Axis)) I wrote the code myself and used AI for specific tasks like tests, debugging, and UI tweaks. With Drift I wanted to see how far I could get by directing instead of typing.

**What I did**
- Came up with the concept, the name, and the feel of the app
- Worked out the design system with Claude: the gradient for each condition, the floating "pill" controls, the motion rules, the app icon, and the screen flow
- Wrote all of it into [`claude.md`](claude.md), a living design spec that gives Claude the full project context at the start of every session
- Decided the build order, reviewed each change, tested it on device, and pushed back or changed direction when something didn't feel right. For example, I dropped MapKit for a custom renderer and replaced the placeholder geometry with real OpenStreetMap data.

**What the AI did**
- Wrote the Swift implementation from my prompts and the spec
- Explained its reasoning in detailed doc comments throughout the code, so every file says *why* it works the way it does, not just *what* it does

What I took away is that prompting well is mostly product and engineering judgment: being precise about what you want, catching where the AI's output drifts from your vision, and knowing when to change the plan.

---

## How it works

### The theme engine
The screen's look comes from one function, `ThemeEngine.theme(weather:timeOfDay:)`, which turns two inputs into a gradient:

| Priority | Input | Source |
| --- | --- | --- |
| 1 | **Weather**: rain, snow, storm, and fog override the time of day | [Open-Meteo](https://open-meteo.com) (free, no API key) |
| 2 | **Time of day**: sunrise, midday, sunset, night | `SunCalculator`, offline using the sunrise equation |
| — | **Movement**: still, walking, biking | CoreMotion activity data. Drives animation only, never color |

There are 8 hand-tuned gradients in all. One design rule holds for every theme: **it never goes fully dark.** Even at night or in a storm, the bottom of the gradient fades to a pale tone, so the mood is atmospheric rather than gloomy. Snow is the one theme that switches the text to a dark color.

`MapModel` keeps the theme current for four reasons: a new GPS fix, a once-a-minute clock tick (the sun keeps moving even when you don't), a finished weather fetch, and a weather refresh every 15 minutes.

### The street-level world
Drift doesn't use MapKit for rendering. `WorldView` draws everything itself in a SwiftUI `Canvas`, from a third-person camera placed a few meters behind and above you, looking down the street you're facing.

- **You stay still and the world moves.** Every road and building is positioned relative to your live location and recalculated each frame, and the whole scene turns with your compass heading.
- **A tiny planet.** The ground is a small sphere, so the street visibly curves away over a horizon and distant buildings rise up from behind it.
- **Smooth motion between GPS fixes.** GPS updates about once a second. `WorldMotion` estimates your position along your velocity between fixes and eases toward each new one, so the world glides instead of jumping.
- **Buildings that sway.** Buildings lean with how fast the world is passing you and how fast you're turning. That lean runs through springs that slightly overshoot, so they swing back past upright and settle when you stop.
- **Road snapping.** Your position snaps to the nearest real street (within 25 m), and your velocity is projected along that street, so GPS drift doesn't put you inside a building.

### Real map data
`RoadNetworkService` and `BuildingNetworkService` fetch real road geometry, street names, and building footprints from **OpenStreetMap** through the free **Overpass API**. Each fetch covers twice the area being drawn, and the services only fetch again once you've moved outside it, so they stay well within a shared free API's limits. The placeholder generators are still around for offline SwiftUI previews.

---

## Status

| Area | State |
| --- | --- |
| Theme engine + 8 gradients | ✅ |
| Offline sunrise/sunset calculation | ✅ |
| Live weather (Open-Meteo) | ✅ |
| Location, compass heading, motion activity | ✅ |
| Street-level 3D renderer (`WorldView`) | ✅ |
| Real OSM roads + buildings (Overpass) | ✅ |
| User pulse dot (speed-aware) | ✅ |
| Onboarding (welcome, theme mode, contextual permissions) | 🔲 stubbed |
| Settings | 🔲 stubbed |
| Floating controls (weather/time pill, speed pill, place search) | 🔲 stubbed |
| Fading movement trail | 🔲 stubbed |
| Preferences (`@AppStorage`) | 🔲 stubbed |

### Planned later
- Apple Watch face: time, pulse dot, and speed over the same live gradient
- Gradient tints for specific districts and venues
- WeatherKit in place of Open-Meteo
- CarPlay

---

## Tech Stack

SwiftUI (`Canvas`, `TimelineView`) · Combine · CoreLocation · CoreMotion · URLSession + async/await · Open-Meteo API · OpenStreetMap / Overpass API · Swift Testing

**Architecture:** MVVM. `MapModel` is the single source of truth for the map screen, and the views only read from it.

### Project structure

```
Dritft/                     # App entry + ContentView
Core/
├── Theme/                  # ThemeEngine, MapTheme, weather + time-of-day enums
├── Location/               # LocationManager, SunCalculator
├── Weather/                # WeatherService (Open-Meteo), response model
├── Motion/                 # MotionManager, MovementState
├── Features/
│   ├── Map/                # MapModel, WorldView, WorldMotion, WorldProjection,
│   │                       #   Road/BuildingNetworkService, Overpass models
│   ├── Onboarding/         # (stubbed)
│   ├── Controls/           # (stubbed)
│   └── Settings/           # (stubbed)
├── UI/                     # Components, modifiers, color + animation extensions
├── Models/  Persistence/
DritftTests/                # Swift Testing: road snapping + Overpass decoding
claude.md                   # Design spec / AI project context
```

---

## Getting Started

**Requirements:** Xcode 26 or later, iOS 26.5 or later. A real iPhone is recommended, since the compass, motion activity, and walking around don't work well in the simulator.

```bash
git clone https://github.com/arturoa925/Drift.git
cd Drift
open Dritft.xcodeproj
```

1. Set your **Team** under *Signing & Capabilities* and change the bundle ID (`AA.Dritft`).
2. Run on your iPhone and allow **Location** and **Motion & Fitness** access.
3. Go for a walk.

No API keys are needed. Open-Meteo and Overpass are both free and don't require authentication.

---

## Author

**Arturo Ayala**: [GitHub](https://github.com/arturoa925) · [LinkedIn](https://linkedin.com/in/arturo-ayala-775493187)
