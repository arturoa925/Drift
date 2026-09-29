//
//  WorldView.swift
//  Dritft
//
//  Created by Arturo Ayala on 5/28/26.
//

import CoreLocation
import SwiftUI

/// Renders `buildings` as custom-drawn, individually animated polygons —
/// this is the replacement for MapKit's `Map` as the map screen's visual
/// surface. Every building's screen position is recomputed from its
/// real-world offset to `origin` on every single frame, never from a
/// discrete camera/region. That's the whole mechanism behind "the user
/// stands still and the world moves around them": there's no camera to
/// pan, because nothing here is drawn in a fixed frame to begin with.
///
/// Sway (per-building rotation) and proximity-scale both pivot around each
/// building's own centroid, not the scene as a whole, so a field of
/// buildings reads as independently alive — like grass in wind — rather
/// than one uniform effect applied to everything at once.
///
/// `heading` drives one more rotation on top of that, around the user
/// instead of each building's own centroid: the whole scene turns so the
/// direction the user is physically facing always renders as "up". That's
/// what makes turning your body — even standing still, a 180° spin — sweep
/// the entire city across the screen, the same way looking around a room
/// sweeps the room across your vision.
struct WorldView: View {
    let origin: CLLocationCoordinate2D?
    /// True compass heading, 0–360°. `nil` (no reading yet, or heading
    /// unavailable) renders the scene un-rotated, north-up — the same
    /// behavior as before heading tracking existed.
    let heading: CLLocationDirection?
    let movementState: MovementState
    let roads: [RoadSegment]
    let buildings: [BuildingShape]

    /// Screen points per meter. Tuned for "buildings up close" — a ~15m
    /// footprint renders roughly 45pt wide, matching the street-level feel
    /// MapView's old MapKit zoom was aiming for.
    private let pixelsPerMeter: CGFloat = 3.0
    /// Real-world distance (meters) at which a building renders at its
    /// plain, un-boosted 1x size. Below this, `scale` grows as
    /// `proximityReferenceDistance / distance` — true inverse-distance
    /// perspective, not a capped percentage boost — so a building actually
    /// looms toward life-size as the user walks up to it instead of just
    /// getting modestly bigger.
    private let proximityReferenceDistance: Double = 45
    /// Floor on the distance used in that division, so a building the user
    /// is standing right on top of (distance -> 0) doesn't scale toward
    /// infinity — this is the closest distance still on the true 1/distance
    /// curve before it flattens out at `maxProximityScale`.
    private let minProximityDistance: Double = 6
    /// Hard cap on how large `scale` can get, independent of how close the
    /// user actually gets — keeps an adjacent building from blowing out the
    /// canvas or drawing pathologically huge paths.
    private let maxProximityScale: Double = 6
    private let roadLineWidth: CGFloat = 9
    /// How many screen points a building's roof floats above its own
    /// footprint per meter of real height — the vertical half of
    /// `pixelsPerMeter`'s "meters to screen" conversion.
    private let heightPixelsPerMeter: CGFloat = 1.6
    /// Primary "sag" weight, applied to a point's forward/behind (screen
    /// vertical) distance from the user — this is the axis that rolls with
    /// whichever way the user is walking, since `headingRotation` keeps
    /// that direction pointing up. The dominant term in the "spinning ball
    /// underfoot" effect.
    private let horizonCurvature: CGFloat = 0.0016
    /// Secondary, weaker sag weight applied to horizontal (left/right)
    /// distance — rounds out the sides so the world reads as a sphere the
    /// user stands on top of, not a half-pipe that only curves fore/aft.
    private let horizonCurvatureSide: CGFloat = 0.0006
    /// Real-world meters between interpolated points along a road segment
    /// before curving each one individually. Roads span the entire render
    /// radius (~220m) as a single logical line — far too long to curve
    /// correctly by bending only its two endpoints and drawing a straight
    /// line between them, the way a building's footprint (~10-20m across)
    /// safely can. This keeps the curve looking smooth along the line's
    /// whole length instead of just yanking its far ends around.
    private let roadCurveSampleMeters: Double = 12
    /// Real-world floor height — drives window row count so a wall's grid
    /// reads as "one row per story" rather than stretching a fixed row
    /// count over every building regardless of how tall it is.
    private let floorHeightMeters: Double = 3.5
    /// Target on-screen spacing between window columns, before rounding to
    /// a whole column count — this (not a fixed count) is what makes wide
    /// walls get proportionally more windows than narrow ones.
    private let windowColumnSpacing: CGFloat = 11
    private let maxWindowRows = 14
    private let maxWindowColumns = 7
    private let windowWidthFraction: Double = 0.55
    private let windowHeightFraction: Double = 0.6
    /// Fraction of windows that render "lit" — deterministic per window
    /// (seeded from building id + wall/row/col), not animated, since a
    /// static occupied-looking pattern is enough to sell the effect for
    /// the cost of one extra fill per window.
    private let litWindowProbability: Double = 0.32

    var body: some View {
        TimelineView(.animation) { timeline in
            Canvas { context, size in
                guard let origin else { return }
                let center = CGPoint(x: size.width / 2, y: size.height / 2)
                let time = timeline.date.timeIntervalSinceReferenceDate

                // Roads first, buildings on top — streets sit at ground
                // level, buildings stand on top of them.
                for road in roads {
                    draw(road, origin: origin, center: center, in: &context)
                }
                for building in buildings {
                    draw(building, origin: origin, center: center, time: time, in: &context)
                }
            }
        }
    }

    private func draw(
        _ road: RoadSegment,
        origin: CLLocationCoordinate2D,
        center: CGPoint,
        in context: inout GraphicsContext
    ) {
        // Sampled as a polyline, not a single straight line between the two
        // far-apart endpoints — a road spans the entire render radius
        // (~220m), and the horizon curve is nonlinear, so curving only the
        // endpoints and drawing a straight line between them swings wildly
        // off the road's true (curved) path. Interpolating in real
        // lat/lng space every `roadCurveSampleMeters` and curving each
        // sample individually keeps the drawn line hugging the curve.
        let lengthMeters = hypot(
            WorldProjection.offset(from: road.start, to: road.end).dx,
            WorldProjection.offset(from: road.start, to: road.end).dy
        )
        let steps = max(1, Int((lengthMeters / roadCurveSampleMeters).rounded(.up)))

        var path = Path()
        for step in 0...steps {
            let t = Double(step) / Double(steps)
            let coordinate = CLLocationCoordinate2D(
                latitude: road.start.latitude + (road.end.latitude - road.start.latitude) * t,
                longitude: road.start.longitude + (road.end.longitude - road.start.longitude) * t
            )
            let screenPoint = point(for: coordinate, origin: origin, center: center)
            if step == 0 {
                path.move(to: screenPoint)
            } else {
                path.addLine(to: screenPoint)
            }
        }

        // Bumped well past claude.md's original 0.16/0.13 — with buildings
        // now rendered as filled, windowed 3D boxes instead of thin
        // outlines, that original "whisper" opacity reads as barely there
        // underneath them. Horizontal and vertical streets keep their
        // original relative difference, just scaled up together.
        let opacity = road.orientation == .horizontal ? 0.42 : 0.34
        context.stroke(
            path,
            with: .color(Color(hex: "B4B4BE").opacity(opacity)),
            style: StrokeStyle(lineWidth: roadLineWidth, lineCap: .round)
        )
    }

    private func point(for coordinate: CLLocationCoordinate2D, origin: CLLocationCoordinate2D, center: CGPoint) -> CGPoint {
        let offset = WorldProjection.offset(from: origin, to: coordinate)
        let rotated = rotate(offset, by: headingRotation)
        // Screen y grows downward, so "north" (positive dy in meters) has
        // to flip sign here to point up — same convention `draw(_:building)`
        // uses below.
        let flat = CGPoint(
            x: center.x + CGFloat(rotated.dx) * pixelsPerMeter,
            y: center.y - CGFloat(rotated.dy) * pixelsPerMeter
        )
        return applyHorizonCurve(flat, center: center)
    }

    /// Radians to rotate every raw (east, north) offset by so that facing
    /// `heading` always renders as "up" on screen. Derived from: a unit
    /// vector at compass bearing θ is (sin θ, cos θ) in (east, north); using
    /// `rotate(_:by:)`'s CCW convention, rotating that vector by angle = θ
    /// lands it at (0, 1) — straight up, once the usual dy-flip into screen
    /// space happens below. `nil` heading (no reading yet) rotates by 0,
    /// i.e. renders north-up exactly as before heading tracking existed.
    private var headingRotation: Double {
        (heading ?? 0) * .pi / 180
    }

    /// Bends a flat-projected point downward, weighted mostly by its
    /// *vertical* (forward/behind, screen dy) distance from center rather
    /// than horizontal — since `headingRotation` above already makes
    /// "the direction the user is walking" always point up on screen, this
    /// is what makes the curve roll specifically along the walking
    /// direction: a building dead ahead crests and comes down toward the
    /// user as they approach, one dead behind drops away over the curve,
    /// the same way walking forward on top of a ball rolls it under your
    /// feet along your direction of travel. A smaller secondary weight on
    /// horizontal distance keeps the sides gently rounding too, so it reads
    /// as a sphere the user stands on top of rather than a half-pipe that
    /// only curves along one axis.
    private func applyHorizonCurve(_ point: CGPoint, center: CGPoint) -> CGPoint {
        let dx = point.x - center.x
        let dy = point.y - center.y
        let sag = (dy * dy) * horizonCurvature + (dx * dx) * horizonCurvatureSide
        return CGPoint(x: point.x, y: point.y + sag)
    }

    private func draw(
        _ building: BuildingShape,
        origin: CLLocationCoordinate2D,
        center: CGPoint,
        time: TimeInterval,
        in context: inout GraphicsContext
    ) {
        // Rotated by heading immediately, before anything else touches
        // these — that's what makes the building's position *and* its own
        // footprint orientation turn together as the user turns, rather
        // than just sliding around a fixed-orientation city.
        let offsets = building.footprint.map { rotate(WorldProjection.offset(from: origin, to: $0), by: headingRotation) }
        guard let centroid = centroid(of: offsets) else { return }

        // True inverse-distance perspective (in real meters, not screen
        // distance): a building at `proximityReferenceDistance` away renders
        // at 1x, and it grows the closer the user actually gets, capped at
        // `maxProximityScale` — the "buildings get life-size as you approach
        // them" effect, not just a modest fixed boost.
        let distance = hypot(centroid.dx, centroid.dy)
        let scale = min(proximityReferenceDistance / max(distance, minProximityDistance), maxProximityScale)

        // Each building's own phase/speed offsets its sway from every other
        // building's, so the field doesn't move in lockstep. Amplitude
        // itself comes from `movementState` (claude.md: still = no sway,
        // walking = 1.5°, biking = 3°) rather than a fixed constant, so nearby
        // buildings only swoosh past while the user is actually moving.
        let swaySpeed = 0.6 + building.swayPhase * 0.4
        let swayAmplitudeRadians = movementState.swayAngle * .pi / 180
        let swayAngle = sin(time * swaySpeed + building.swayPhase * 2 * .pi) * swayAmplitudeRadians

        // The base footprint's screen points (before any vertical
        // extrusion) — flat on the "ground", already swayed/scaled/curved.
        let basePoints: [CGPoint] = offsets.map { offset in
            let relative = Vector2(dx: offset.dx - centroid.dx, dy: offset.dy - centroid.dy)
            let rotated = rotate(relative, by: swayAngle)
            let scaled = Vector2(dx: rotated.dx * scale, dy: rotated.dy * scale)
            let final = Vector2(dx: scaled.dx + centroid.dx, dy: scaled.dy + centroid.dy)

            // Screen y grows downward, so "north" (positive dy in meters)
            // has to flip sign here to point up.
            let flat = CGPoint(
                x: center.x + CGFloat(final.dx) * pixelsPerMeter,
                y: center.y - CGFloat(final.dy) * pixelsPerMeter
            )
            return applyHorizonCurve(flat, center: center)
        }

        // The roof is just the same footprint translated straight up —
        // taller buildings (and, thanks to `scale`, closer ones) float
        // their roof higher, which is the entire "extrusion".
        let extrusion = CGPoint(x: 0, y: -CGFloat(building.height) * heightPixelsPerMeter * CGFloat(scale))
        let roofPoints = basePoints.map { CGPoint(x: $0.x + extrusion.x, y: $0.y + extrusion.y) }

        // Real, un-swayed edge lengths (meters), one per wall — used only
        // to size the window grid. Sway rotation preserves edge length
        // exactly, so in theory reading it off `basePoints` post-sway would
        // give the same number; in practice `basePoints` is also passed
        // through `applyHorizonCurve`, which bends each vertex by a
        // slightly different amount as sway continuously moves them
        // through screen space. That sub-pixel wobble was enough to flip
        // the rounded column count frame to frame — most visible on small,
        // distant buildings — reading as windows "flashing" or buildings
        // seeming to redraw multiple times. Sizing the grid from the
        // static real-world footprint instead makes column count immune
        // to both sway and the horizon curve.
        let edgeLengthsMeters: [Double] = (0..<offsets.count).map { index in
            let next = (index + 1) % offsets.count
            return hypot(offsets[next].dx - offsets[index].dx, offsets[next].dy - offsets[index].dy)
        }

        drawSideWalls(
            basePoints: basePoints,
            roofPoints: roofPoints,
            extrusion: extrusion,
            edgeLengthsMeters: edgeLengthsMeters,
            scale: scale,
            buildingID: building.id,
            in: &context
        )

        var roofPath = Path()
        roofPath.move(to: roofPoints[0])
        for point in roofPoints.dropFirst() { roofPath.addLine(to: point) }
        roofPath.closeSubpath()
        context.fill(roofPath, with: .color(.white.opacity(0.30)))
        context.stroke(roofPath, with: .color(.white.opacity(0.45)), lineWidth: 1)
    }

    /// Draws only the footprint edges that would actually be visible from
    /// a straight-on view once extruded straight up — a cheap backface
    /// cull, not a real 3D renderer, but it's what turns a flat rectangle
    /// into a believable box: the "near" edges get walls, the "far" edge
    /// (already hidden behind the roof) and the edges running parallel to
    /// the extrusion (edge-on, zero width from this angle) get none.
    private func drawSideWalls(
        basePoints: [CGPoint],
        roofPoints: [CGPoint],
        extrusion: CGPoint,
        edgeLengthsMeters: [Double],
        scale: Double,
        buildingID: String,
        in context: inout GraphicsContext
    ) {
        let count = basePoints.count
        for index in 0..<count {
            let next = (index + 1) % count
            let edge = CGPoint(x: basePoints[next].x - basePoints[index].x, y: basePoints[next].y - basePoints[index].y)

            // 2D cross product of the edge with the extrusion vector.
            // Negative means this edge's outward normal points toward the
            // viewer (down-screen) — a visible wall. Zero or positive means
            // it's edge-on or facing away, so it's skipped entirely.
            let cross = edge.x * extrusion.y - edge.y * extrusion.x
            guard cross < 0 else { continue }

            var wall = Path()
            wall.move(to: basePoints[index])
            wall.addLine(to: basePoints[next])
            wall.addLine(to: roofPoints[next])
            wall.addLine(to: roofPoints[index])
            wall.closeSubpath()

            // Walls read as "in shadow" relative to the roof — a flat,
            // cheap stand-in for real per-face lighting that's still
            // enough to sell the box as three-dimensional.
            context.fill(wall, with: .color(.white.opacity(0.14)))
            context.stroke(wall, with: .color(.white.opacity(0.22)), lineWidth: 1)

            drawWindows(
                origin: basePoints[index],
                right: edge,
                up: extrusion,
                edgeMeters: edgeLengthsMeters[index],
                scale: scale,
                buildingID: buildingID,
                wallIndex: index,
                in: &context
            )
        }
    }

    /// Fills a grid of small window rects across one wall face. The wall is
    /// a parallelogram (roof is just the base translated by `extrusion`),
    /// so every window corner is a plain affine combination of `origin`,
    /// `right` (the base edge) and `up` (the extrusion) — no per-wall
    /// projection math needed beyond what `drawSideWalls` already has.
    private func drawWindows(
        origin: CGPoint,
        right: CGPoint,
        up: CGPoint,
        edgeMeters: Double,
        scale: Double,
        buildingID: String,
        wallIndex: Int,
        in context: inout GraphicsContext
    ) {
        guard edgeMeters > 0 else { return }

        // Column/row counts are both sized from stable, real-world inputs
        // (the footprint's own edge length and the building's own height)
        // rather than measured off `right`/`up` directly — those two
        // vectors move every frame with sway and the horizon curve, and
        // rounding a continuously wobbling length to a whole window count
        // flickers the grid. `edgeMeters` and `heightPixelsPerMeter`'s
        // meter basis don't wobble; only `scale` (real distance, changes
        // gradually) moves them, which is fine.
        let wallWidthPoints = edgeMeters * Double(pixelsPerMeter) * scale
        let wallHeightMeters = Double(hypot(up.x, up.y)) / (Double(heightPixelsPerMeter) * scale)
        guard wallWidthPoints > 1, wallHeightMeters > 0 else { return }

        let columns = min(maxWindowColumns, max(1, Int((wallWidthPoints / Double(windowColumnSpacing)).rounded())))
        let rows = min(maxWindowRows, max(1, Int((wallHeightMeters / floorHeightMeters).rounded())))
        guard columns > 0, rows > 0 else { return }

        var rng = SeededGenerator(seed: windowSeed(buildingID: buildingID, wallIndex: wallIndex))

        for row in 0..<rows {
            for column in 0..<columns {
                let isLit = Double.random(in: 0..<1, using: &rng) < litWindowProbability

                let u = (Double(column) + 0.5) / Double(columns)
                let v = (Double(row) + 0.5) / Double(rows)
                let halfWidth = windowWidthFraction / Double(columns) / 2
                let halfHeight = windowHeightFraction / Double(rows) / 2

                func point(_ u: Double, _ v: Double) -> CGPoint {
                    CGPoint(
                        x: origin.x + CGFloat(u) * right.x + CGFloat(v) * up.x,
                        y: origin.y + CGFloat(u) * right.y + CGFloat(v) * up.y
                    )
                }

                var window = Path()
                window.move(to: point(u - halfWidth, v - halfHeight))
                window.addLine(to: point(u + halfWidth, v - halfHeight))
                window.addLine(to: point(u + halfWidth, v + halfHeight))
                window.addLine(to: point(u - halfWidth, v + halfHeight))
                window.closeSubpath()

                if isLit {
                    context.fill(window, with: .color(Color(hex: "FDE68A").opacity(0.55)))
                } else {
                    context.fill(window, with: .color(.white.opacity(0.10)))
                }
            }
        }
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

#Preview {
    let origin = CLLocationCoordinate2D(latitude: 37.7749, longitude: -122.4194)
    WorldView(
        origin: origin,
        heading: nil,
        movementState: .walking,
        roads: PlaceholderRoadGenerator.roads(near: origin, radiusMeters: 220),
        buildings: PlaceholderCityGenerator.buildings(near: origin, radiusMeters: 220)
    )
    .background(Color.black)
}
