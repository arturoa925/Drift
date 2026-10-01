//
//  WorldView.swift
//  Dritft
//
//  Created by Arturo Ayala on 5/28/26.
//

import CoreLocation
import SwiftUI

/// Renders `roads` and `buildings` from a street-level, third-person
/// camera — standing a few meters behind and above the user, looking down
/// the street they're facing — instead of the old tilted top-down view.
/// Every point is still recomputed from its real-world offset to `origin`
/// on every frame, so "the user stands still and the world moves around
/// them" holds exactly as before: the camera is fixed relative to the
/// user, and the world is what moves.
///
/// The ground is a sphere the user stands on top of (radius
/// `planetRadiusMeters`), kept deliberately tiny so the street visibly
/// rolls away over a curved horizon — the 3D successor to the old
/// screen-space "spinning ball underfoot" sag. Anything past that horizon
/// is clipped to the sky above it, so far buildings rise up from behind
/// the curve rather than floating in front of it.
///
/// `heading` turns the whole scene so the direction the user is physically
/// facing always renders as "into the screen" — turning your body sweeps
/// the street around you the same way looking around a room does.
struct WorldView: View {
    let origin: CLLocationCoordinate2D?
    /// True compass heading, 0–360°. `nil` (no reading yet, or heading
    /// unavailable) renders facing north.
    let heading: CLLocationDirection?
    let movementState: MovementState
    let roads: [RoadSegment]
    let buildings: [BuildingShape]
    /// How far out `roads`/`buildings` were generated — buildings fade out
    /// approaching it so the edge of the generated area never pops.
    let renderRadiusMeters: Double

    /// Fraction of screen height (from the top) where the user's own ground
    /// position lands. Shared with `MapView` so `UserPulseView` sits exactly
    /// where the camera says the user is standing — low on screen, so most
    /// of it is spent on the street ahead rather than the road underfoot.
    static let userScreenAnchorY: CGFloat = 0.7

    /// How far behind the user the camera floats, in meters.
    private let cameraBackMeters: Double = 9
    /// How far above the ground the camera floats, in meters — a little
    /// over head height, so the user reads as standing *in* the street
    /// rather than being looked down on from a balcony.
    private let cameraHeightMeters: Double = 4.5
    /// Horizontal field of view across the screen's width. Wide enough that
    /// buildings right beside the user still make it on screen in portrait.
    private let horizontalFieldOfViewDegrees: Double = 78
    /// Geometry closer to the camera than this (in depth) is clipped away —
    /// keeps perspective division away from zero.
    private let nearPlaneMeters: Double = 0.5
    /// Radius of the little planet the user walks on. Smaller = more
    /// dramatic curve, and a closer horizon.
    private let planetRadiusMeters: Double = 170
    /// Buildings start fading at this fraction of `renderRadiusMeters` and
    /// are fully gone at the radius itself.
    private let fadeStartFraction: Double = 0.6

    /// Real road width (meters) — two 3.5m lanes, curb to curb. The
    /// placeholder grid keeps every building at least ~7m from a street's
    /// center line, so this leaves a sidewalk of 3.5m or more on each side.
    private let roadWidthMeters: Double = 7
    /// Dashed center line, real meters — the one road marking that gives
    /// the eye a true sense of scale at street level.
    private let centerDashLengthMeters: Double = 3
    private let centerDashWidthMeters: Double = 0.15
    /// Real-world meters between samples along a road. Each sample gets its
    /// own height on the curved ground, so this is what keeps a long street
    /// following the planet's curve instead of cutting straight through it.
    private let roadSampleMeters: Double = 6

    /// Real-world floor height — one window row per story.
    private let floorHeightMeters: Double = 3.5
    /// Real-world spacing between window columns along a wall.
    private let windowColumnMeters: Double = 4
    private let maxWindowRows = 20
    private let maxWindowColumns = 8
    private let windowWidthFraction: Double = 0.55
    private let windowHeightFraction: Double = 0.6
    /// Walls smaller than this on screen (longest side, in points) skip
    /// windows entirely — they'd just be sub-pixel noise.
    private let minWindowedWallPoints: CGFloat = 14
    /// Fraction of windows that render "lit" — deterministic per window
    /// (seeded from building id + wall), not animated.
    private let litWindowProbability: Double = 0.32

    var body: some View {
        TimelineView(.animation) { timeline in
            Canvas { context, size in
                guard let origin else { return }
                let camera = makeCamera(size: size)
                let time = timeline.date.timeIntervalSinceReferenceDate

                // Roads first, buildings on top — streets sit at ground
                // level, buildings stand on top of them.
                drawRoads(origin: origin, camera: camera, in: &context)

                let skyClip = skyRegion(camera: camera, size: size)
                for item in sortedBuildings(origin: origin, camera: camera) {
                    if item.isPastHorizon, let skyClip {
                        // Past the horizon, the planet itself hides the
                        // building's lower part — only what pokes up into
                        // the sky above the horizon line is visible. A
                        // clipped copy of the context, not a separate
                        // layer: it still draws straight onto the canvas,
                        // which the occlusion knock-out in `draw` needs.
                        var clipped = context
                        clipped.clip(to: skyClip)
                        draw(item, camera: camera, time: time, in: &clipped)
                    } else {
                        draw(item, camera: camera, time: time, in: &context)
                    }
                }
            }
        }
    }

    // MARK: - Camera

    private func makeCamera(size: CGSize) -> StreetCamera {
        let position = Vector3(x: 0, y: -cameraBackMeters, z: cameraHeightMeters)
        // Pitched down exactly enough to look straight at the user's feet,
        // which is what lands the user on `principalPoint` below.
        let pitch = atan2(cameraHeightMeters, cameraBackMeters)
        let focalLength = Double(size.width) / 2 / tan(horizontalFieldOfViewDegrees * .pi / 360)
        return StreetCamera(
            position: position,
            forward: Vector3(x: 0, y: cos(pitch), z: -sin(pitch)),
            up: Vector3(x: 0, y: sin(pitch), z: cos(pitch)),
            focalLength: focalLength,
            principalPoint: CGPoint(x: size.width / 2, y: size.height * Self.userScreenAnchorY),
            nearPlane: nearPlaneMeters
        )
    }

    /// Radians to rotate every raw (east, north) offset by so that facing
    /// `heading` always points "forward" (+y). A unit vector at compass
    /// bearing θ is (sin θ, cos θ) in (east, north); rotating it CCW by θ
    /// lands it on (0, 1).
    private var headingRotation: Double {
        (heading ?? 0) * .pi / 180
    }

    /// Ground offset (meters, heading-rotated: x right, y forward) lifted
    /// onto the planet's surface, plus `height` meters straight up.
    private func worldPoint(_ offset: Vector2, height: Double = 0) -> Vector3 {
        Vector3(x: offset.dx, y: offset.dy, z: groundHeight(at: offset) + height)
    }

    /// Height of the planet's surface below the flat tangent plane the user
    /// stands on — 0 underfoot, curving away (negative) with distance.
    private func groundHeight(at offset: Vector2) -> Double {
        let distanceSquared = offset.dx * offset.dx + offset.dy * offset.dy
        let r = planetRadiusMeters
        return (max(r * r - distanceSquared, 0)).squareRoot() - r
    }

    private var planetCenter: Vector3 {
        Vector3(x: 0, y: 0, z: -planetRadiusMeters)
    }

    /// Whether a point on the ground is hidden over the horizon: true when
    /// the camera sits below that point's tangent plane.
    private func isPastHorizon(_ groundPoint: Vector3, camera: StreetCamera) -> Bool {
        let normal = groundPoint - planetCenter
        return normal.dot(camera.position - groundPoint) < 0
    }

    /// Screen region above the horizon line — the circle of tangent points
    /// where the camera's line of sight just grazes the planet, projected
    /// and closed off upward. `nil` if none of that circle is in front of
    /// the camera.
    private func skyRegion(camera: StreetCamera, size: CGSize) -> Path? {
        let toCamera = camera.position - planetCenter
        let distance = toCamera.length
        let r = planetRadiusMeters
        guard distance > r else { return nil }

        let axis = toCamera * (1 / distance)
        let circleCenter = planetCenter + axis * (r * r / distance)
        let circleRadius = r * (1 - (r * r) / (distance * distance)).squareRoot()
        // Any two unit vectors perpendicular to `axis` span the circle.
        let tangentA = Vector3(x: 1, y: 0, z: 0).cross(axis).normalized
        let tangentB = axis.cross(tangentA)

        let samples = 128
        var points: [CGPoint] = []
        for index in 0..<samples {
            let angle = Double(index) / Double(samples) * 2 * .pi
            let world = circleCenter + tangentA * (cos(angle) * circleRadius) + tangentB * (sin(angle) * circleRadius)
            let local = camera.toCamera(world)
            guard local.z > camera.nearPlane else { continue }
            points.append(camera.project(local))
        }
        guard points.count >= 2 else { return nil }
        points.sort { $0.x < $1.x }

        let far: CGFloat = 100_000
        var path = Path()
        path.move(to: CGPoint(x: -far, y: -far))
        path.addLine(to: CGPoint(x: -far, y: points[0].y))
        for point in points { path.addLine(to: point) }
        path.addLine(to: CGPoint(x: far, y: points[points.count - 1].y))
        path.addLine(to: CGPoint(x: far, y: -far))
        path.closeSubpath()
        return path
    }

    // MARK: - Roads

    private func drawRoads(origin: CLLocationCoordinate2D, camera: StreetCamera, in context: inout GraphicsContext) {
        // One path per orientation, filled once — overlapping quads (at
        // intersections, and where a road's own segments meet) then fill
        // as a single shape instead of stacking their opacity.
        var horizontal = Path()
        var vertical = Path()
        var centerDashes = Path()

        for road in roads {
            let start = rotate(WorldProjection.offset(from: origin, to: road.start), by: headingRotation)
            let end = rotate(WorldProjection.offset(from: origin, to: road.end), by: headingRotation)
            let length = hypot(end.dx - start.dx, end.dy - start.dy)
            guard length > 0 else { continue }

            // Unit vector pointing across the road.
            let across = Vector2(dx: -(end.dy - start.dy) / length, dy: (end.dx - start.dx) / length)
            let steps = max(1, Int((length / roadSampleMeters).rounded(.up)))

            /// Point at fraction `t` along the road, `offset` meters across
            /// it from the center line.
            func along(_ t: Double, _ offset: Double) -> Vector2 {
                Vector2(
                    dx: start.dx + (end.dx - start.dx) * t + across.dx * offset,
                    dy: start.dy + (end.dy - start.dy) * t + across.dy * offset
                )
            }
            let halfWidth = roadWidthMeters / 2
            let halfDash = centerDashWidthMeters / 2
            let dashFraction = min(centerDashLengthMeters / (length / Double(steps)), 1)

            for step in 0..<steps {
                let t0 = Double(step) / Double(steps)
                let t1 = Double(step + 1) / Double(steps)
                let middle = worldPoint(along((t0 + t1) / 2, 0))
                guard !isPastHorizon(middle, camera: camera) else { continue }

                let quad = [along(t0, -halfWidth), along(t1, -halfWidth), along(t1, halfWidth), along(t0, halfWidth)]
                guard let screen = camera.projectPolygon(quad.map { worldPoint($0) }) else { continue }
                let polygon = Path.polygon(screen)
                if road.orientation == .horizontal {
                    horizontal.addPath(polygon)
                } else {
                    vertical.addPath(polygon)
                }

                // One dash at the start of each sample, so dash spacing is
                // exactly `roadSampleMeters`.
                let dashEnd = t0 + (t1 - t0) * dashFraction
                let dash = [along(t0, -halfDash), along(dashEnd, -halfDash), along(dashEnd, halfDash), along(t0, halfDash)]
                if let dashScreen = camera.projectPolygon(dash.map { worldPoint($0, height: 0.02) }) {
                    centerDashes.addPath(Path.polygon(dashScreen))
                }
            }
        }

        // Ground-level surfaces fill a lot more of the screen from street
        // level than they did from overhead, so these sit back closer to
        // claude.md's "whisper" opacities than the old 0.42/0.34 strokes.
        let color = Color(hex: "B4B4BE")
        context.fill(horizontal, with: .color(color.opacity(0.30)))
        context.fill(vertical, with: .color(color.opacity(0.24)))
        context.fill(centerDashes, with: .color(.white.opacity(0.45)))
    }

    // MARK: - Buildings

    private struct PlacedBuilding {
        let building: BuildingShape
        /// Heading-rotated footprint offsets, meters.
        let footprint: [Vector2]
        let distanceFromCamera: Double
        let opacity: Double
        let isPastHorizon: Bool
    }

    /// Back-to-front (painter's order), so nearer buildings draw over the
    /// ones behind them.
    private func sortedBuildings(origin: CLLocationCoordinate2D, camera: StreetCamera) -> [PlacedBuilding] {
        let fadeStart = renderRadiusMeters * fadeStartFraction
        let fadeLength = max(renderRadiusMeters - fadeStart, 1)

        return buildings.compactMap { building -> PlacedBuilding? in
            let footprint = building.footprint.map { rotate(WorldProjection.offset(from: origin, to: $0), by: headingRotation) }
            guard let centroid = centroid(of: footprint) else { return nil }

            let distanceFromUser = hypot(centroid.dx, centroid.dy)
            let fade = 1 - min(max((distanceFromUser - fadeStart) / fadeLength, 0), 1)
            guard fade > 0 else { return nil }

            let base = worldPoint(centroid)
            return PlacedBuilding(
                building: building,
                footprint: footprint,
                distanceFromCamera: (base - camera.position).length,
                opacity: fade,
                isPastHorizon: isPastHorizon(base, camera: camera)
            )
        }
        .sorted { $0.distanceFromCamera > $1.distanceFromCamera }
    }

    private func draw(_ item: PlacedBuilding, camera: StreetCamera, time: TimeInterval, in context: inout GraphicsContext) {
        let building = item.building
        let opacity = item.opacity

        // Sway leans the whole building sideways from its base, like grass
        // in wind. Each building's own phase/speed keeps the field out of
        // lockstep; amplitude comes from `movementState` (still = none,
        // walking = 1.5°, biking = 3°).
        let swaySpeed = 0.6 + building.swayPhase * 0.4
        let swayAmplitudeRadians = movementState.swayAngle * .pi / 180
        let swayAngle = sin(time * swaySpeed + building.swayPhase * 2 * .pi) * swayAmplitudeRadians
        let lean = Vector3(x: tan(swayAngle) * building.height, y: 0, z: building.height)

        let base = item.footprint.map { worldPoint($0) }
        let roof = base.map { $0 + lean }

        struct VisibleWall {
            let index: Int
            let corners: [Vector3]
            let path: Path
            let edgeMeters: Double
        }

        let count = base.count
        let walls: [VisibleWall] = (0..<count).compactMap { index in
            let next = (index + 1) % count
            let edge = item.footprint[next] - item.footprint[index]

            // Footprints wind counter-clockwise, so (edge.dy, -edge.dx)
            // points outward. A wall is only visible when it faces the
            // camera — a cheap backface cull that's exact for these convex
            // boxes.
            let toCamera = Vector2(
                dx: camera.position.x - item.footprint[index].dx,
                dy: camera.position.y - item.footprint[index].dy
            )
            guard edge.dy * toCamera.dx - edge.dx * toCamera.dy > 0 else { return nil }

            let corners = [base[index], base[next], roof[next], roof[index]]
            guard let screen = camera.projectPolygon(corners) else { return nil }
            return VisibleWall(index: index, corners: corners, path: Path.polygon(screen), edgeMeters: hypot(edge.dx, edge.dy))
        }

        // Roofs only show for buildings the camera is looking down onto.
        var roofPath: Path?
        if camera.position.z > roof.map(\.z).min() ?? .infinity, let screen = camera.projectPolygon(roof) {
            roofPath = Path.polygon(screen)
        }

        // Occlusion: buildings are see-through, so painter's order alone
        // would leave everything behind this one (other buildings' walls,
        // windows, rooftops, the street) showing through it. Knocking its
        // silhouette out of the canvas first — the union of its visible
        // faces, which for a convex box is exactly its outline — means only
        // the gradient sky shows through instead. Scaled by `opacity` so a
        // building fading in at the edge of the render radius doesn't
        // abruptly punch a hole.
        var silhouette = Path()
        for wall in walls { silhouette.addPath(wall.path) }
        if let roofPath { silhouette.addPath(roofPath) }
        var knockout = context
        knockout.blendMode = .destinationOut
        knockout.fill(silhouette, with: .color(.black.opacity(opacity)))

        for wall in walls {
            // Walls read as "in shadow" relative to the roof — a flat,
            // cheap stand-in for real per-face lighting.
            context.fill(wall.path, with: .color(.white.opacity(0.14 * opacity)))
            context.stroke(wall.path, with: .color(.white.opacity(0.24 * opacity)), lineWidth: 1)

            drawWindows(
                on: wall.corners,
                screenBounds: wall.path.boundingRect,
                edgeMeters: wall.edgeMeters,
                heightMeters: building.height,
                buildingID: building.id,
                wallIndex: wall.index,
                camera: camera,
                opacity: opacity,
                in: &context
            )
        }

        if let roofPath {
            context.fill(roofPath, with: .color(.white.opacity(0.30 * opacity)))
            context.stroke(roofPath, with: .color(.white.opacity(0.45 * opacity)), lineWidth: 1)
        }
    }

    /// Fills a grid of window quads across one wall, every corner placed in
    /// 3D (bilinear across the wall's four corners) and then projected, so
    /// windows foreshorten with the wall instead of being pasted flat on
    /// it. Counts come from the wall's real size, not its on-screen size,
    /// so they never flicker as the wall moves.
    private func drawWindows(
        on wall: [Vector3],
        screenBounds: CGRect,
        edgeMeters: Double,
        heightMeters: Double,
        buildingID: String,
        wallIndex: Int,
        camera: StreetCamera,
        opacity: Double,
        in context: inout GraphicsContext
    ) {
        guard max(screenBounds.width, screenBounds.height) >= minWindowedWallPoints else { return }

        let columns = min(maxWindowColumns, max(1, Int((edgeMeters / windowColumnMeters).rounded())))
        let rows = min(maxWindowRows, max(1, Int((heightMeters / floorHeightMeters).rounded())))

        // wall = [baseA, baseB, roofB, roofA]
        func point(_ u: Double, _ v: Double) -> Vector3 {
            let bottom = wall[0] + (wall[1] - wall[0]) * u
            let top = wall[3] + (wall[2] - wall[3]) * u
            return bottom + (top - bottom) * v
        }

        var rng = SeededGenerator(seed: windowSeed(buildingID: buildingID, wallIndex: wallIndex))
        var lit = Path()
        var unlit = Path()
        let halfWidth = windowWidthFraction / Double(columns) / 2
        let halfHeight = windowHeightFraction / Double(rows) / 2

        for row in 0..<rows {
            for column in 0..<columns {
                // Drawn before any early-out, so each window's lit/unlit
                // state stays tied to its grid slot no matter which other
                // windows get clipped this frame.
                let isLit = Double.random(in: 0..<1, using: &rng) < litWindowProbability

                let u = (Double(column) + 0.5) / Double(columns)
                let v = (Double(row) + 0.5) / Double(rows)
                let corners = [
                    point(u - halfWidth, v - halfHeight),
                    point(u + halfWidth, v - halfHeight),
                    point(u + halfWidth, v + halfHeight),
                    point(u - halfWidth, v + halfHeight),
                ].map(camera.toCamera)
                guard corners.allSatisfy({ $0.z > camera.nearPlane }) else { continue }

                let window = Path.polygon(corners.map(camera.project))
                if isLit {
                    lit.addPath(window)
                } else {
                    unlit.addPath(window)
                }
            }
        }

        context.fill(lit, with: .color(Color(hex: "FDE68A").opacity(0.55 * opacity)))
        context.fill(unlit, with: .color(.white.opacity(0.10 * opacity)))
    }

    /// Same FNV-1a mixing `PlaceholderCityGenerator.seed(for:)` uses for
    /// grid cells, applied to a building+wall pair instead — keeps each
    /// wall's window pattern stable across redraws without tying it to
    /// Swift's per-process string hashing.
    private func windowSeed(buildingID: String, wallIndex: Int) -> UInt64 {
        var hash: UInt64 = 0xcbf29ce484222325
        for byte in buildingID.utf8 {
            hash ^= UInt64(byte)
            hash = hash &* 0x100000001b3
        }
        hash ^= UInt64(wallIndex)
        hash = hash &* 0x100000001b3
        return hash
    }

    private func rotate(_ vector: Vector2, by angle: Double) -> Vector2 {
        let cosA = cos(angle)
        let sinA = sin(angle)
        return Vector2(
            dx: vector.dx * cosA - vector.dy * sinA,
            dy: vector.dx * sinA + vector.dy * cosA
        )
    }

    private func centroid(of offsets: [Vector2]) -> Vector2? {
        guard !offsets.isEmpty else { return nil }
        let dx = offsets.reduce(0) { $0 + $1.dx } / Double(offsets.count)
        let dy = offsets.reduce(0) { $0 + $1.dy } / Double(offsets.count)
        return Vector2(dx: dx, dy: dy)
    }
}

// MARK: - 3D helpers

/// A point/direction in the camera's world frame, meters: x = right,
/// y = forward (the way the user is facing), z = up.
private struct Vector3 {
    var x: Double
    var y: Double
    var z: Double

    static func + (lhs: Vector3, rhs: Vector3) -> Vector3 { Vector3(x: lhs.x + rhs.x, y: lhs.y + rhs.y, z: lhs.z + rhs.z) }
    static func - (lhs: Vector3, rhs: Vector3) -> Vector3 { Vector3(x: lhs.x - rhs.x, y: lhs.y - rhs.y, z: lhs.z - rhs.z) }
    static func * (lhs: Vector3, rhs: Double) -> Vector3 { Vector3(x: lhs.x * rhs, y: lhs.y * rhs, z: lhs.z * rhs) }

    func dot(_ other: Vector3) -> Double { x * other.x + y * other.y + z * other.z }
    func cross(_ other: Vector3) -> Vector3 {
        Vector3(x: y * other.z - z * other.y, y: z * other.x - x * other.z, z: x * other.y - y * other.x)
    }
    var length: Double { dot(self).squareRoot() }
    var normalized: Vector3 { self * (1 / length) }
}

private extension Vector2 {
    static func - (lhs: Vector2, rhs: Vector2) -> Vector2 { Vector2(dx: lhs.dx - rhs.dx, dy: lhs.dy - rhs.dy) }
}

/// A simple pinhole camera with no roll or yaw — heading is already baked
/// into the world points it's handed, so it only ever pitches down.
private struct StreetCamera {
    let position: Vector3
    let forward: Vector3
    let up: Vector3
    let focalLength: Double
    let principalPoint: CGPoint
    let nearPlane: Double

    /// World point -> camera space: x = right, y = up, z = depth.
    func toCamera(_ point: Vector3) -> Vector3 {
        let v = point - position
        return Vector3(x: v.x, y: v.dot(up), z: v.dot(forward))
    }

    /// Camera-space point (in front of the near plane) -> screen point.
    func project(_ point: Vector3) -> CGPoint {
        CGPoint(
            x: principalPoint.x + CGFloat(focalLength * point.x / point.z),
            y: principalPoint.y - CGFloat(focalLength * point.y / point.z)
        )
    }

    /// Projects a world-space polygon, first clipping away whatever part of
    /// it is behind the near plane (Sutherland–Hodgman against that one
    /// plane). `nil` if nothing in front of the camera is left.
    func projectPolygon(_ world: [Vector3]) -> [CGPoint]? {
        let local = world.map(toCamera)
        var clipped: [Vector3] = []
        for index in local.indices {
            let a = local[index]
            let b = local[(index + 1) % local.count]
            let aInFront = a.z >= nearPlane
            if aInFront { clipped.append(a) }
            if aInFront != (b.z >= nearPlane) {
                let t = (nearPlane - a.z) / (b.z - a.z)
                clipped.append(a + (b - a) * t)
            }
        }
        guard clipped.count >= 3 else { return nil }
        return clipped.map(project)
    }
}

private extension Path {
    static func polygon(_ points: [CGPoint]) -> Path {
        var path = Path()
        path.addLines(points)
        path.closeSubpath()
        return path
    }
}

#Preview {
    let origin = CityGrid.streetCenter(near: CLLocationCoordinate2D(latitude: 37.7749, longitude: -122.4194), along: .northSouth)
    WorldView(
        origin: origin,
        heading: nil,
        movementState: .walking,
        roads: PlaceholderRoadGenerator.roads(near: origin, radiusMeters: 160),
        buildings: PlaceholderCityGenerator.buildings(near: origin, radiusMeters: 160),
        renderRadiusMeters: 160
    )
    .background(Color.black)
}
