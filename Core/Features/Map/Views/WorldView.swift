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
struct WorldView: View {
    let origin: CLLocationCoordinate2D?
    let roads: [RoadSegment]
    let buildings: [BuildingShape]

    /// Screen points per meter. Tuned for "buildings up close" — a ~15m
    /// footprint renders roughly 45pt wide, matching the street-level feel
    /// MapView's old MapKit zoom was aiming for.
    private let pixelsPerMeter: CGFloat = 3.0
    private let swayAmplitude: Double = .pi / 36 // ~5°
    private let proximityBoost: Double = 0.6
    private let maxScaleDistance: Double = 150
    private let roadLineWidth: CGFloat = 7
    /// How many screen points a building's roof floats above its own
    /// footprint per meter of real height — the vertical half of
    /// `pixelsPerMeter`'s "meters to screen" conversion.
    private let heightPixelsPerMeter: CGFloat = 1.6
    /// Radial "sag" applied to every rendered point based on its straight-
    /// line distance from the user at screen center, in *any* direction —
    /// the farther something is, the more it sinks toward the bottom of
    /// the screen, like standing at the center of a small curved world and
    /// watching everything dip below your local horizon as it recedes.
    private let horizonCurvature: CGFloat = 0.0006

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
        let start = point(for: road.start, origin: origin, center: center)
        let end = point(for: road.end, origin: origin, center: center)

        var path = Path()
        path.move(to: start)
        path.addLine(to: end)

        // Matches claude.md's two road opacities — horizontal and vertical
        // streets share the same color, just a different low opacity.
        let opacity = road.orientation == .horizontal ? 0.16 : 0.13
        context.stroke(
            path,
            with: .color(Color(hex: "B4B4BE").opacity(opacity)),
            style: StrokeStyle(lineWidth: roadLineWidth, lineCap: .round)
        )
    }

    private func point(for coordinate: CLLocationCoordinate2D, origin: CLLocationCoordinate2D, center: CGPoint) -> CGPoint {
        let offset = WorldProjection.offset(from: origin, to: coordinate)
        // Screen y grows downward, so "north" (positive dy in meters) has
        // to flip sign here to point up — same convention `draw(_:building)`
        // uses below.
        let flat = CGPoint(
            x: center.x + CGFloat(offset.dx) * pixelsPerMeter,
            y: center.y - CGFloat(offset.dy) * pixelsPerMeter
        )
        return applyHorizonCurve(flat, center: center)
    }

    /// Bends a flat-projected point downward based on its radial distance
    /// from center, in every direction — not just left/right — so
    /// something directly "above" or "below" the user on screen sags just
    /// as much as something to the side. Cheap enough to apply to every
    /// point in the scene (roads and buildings alike) without any real
    /// spherical/dome math, and it reads as the ground curving away
    /// underfoot in every direction rather than a flat plane viewed
    /// edge-on.
    private func applyHorizonCurve(_ point: CGPoint, center: CGPoint) -> CGPoint {
        let dx = point.x - center.x
        let dy = point.y - center.y
        let distance = sqrt(dx * dx + dy * dy)
        let sag = (distance * distance) * horizonCurvature
        return CGPoint(x: point.x, y: point.y + sag)
    }

    private func draw(
        _ building: BuildingShape,
        origin: CLLocationCoordinate2D,
        center: CGPoint,
        time: TimeInterval,
        in context: inout GraphicsContext
    ) {
        let offsets = building.footprint.map { WorldProjection.offset(from: origin, to: $0) }
        guard let centroid = centroid(of: offsets) else { return }

        // Closer to the user (in real meters, not screen distance) reads as
        // bigger — an intentional exaggeration, not real perspective.
        let distance = hypot(centroid.dx, centroid.dy)
        let proximity = 1 - min(distance / maxScaleDistance, 1)
        let scale = 1 + proximity * proximityBoost

        // Each building's own phase/speed offsets its sway from every other
        // building's, so the field doesn't move in lockstep.
        let swaySpeed = 0.6 + building.swayPhase * 0.4
        let swayAngle = sin(time * swaySpeed + building.swayPhase * 2 * .pi) * swayAmplitude

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

        drawSideWalls(basePoints: basePoints, roofPoints: roofPoints, extrusion: extrusion, in: &context)

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
        }
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
        roads: PlaceholderRoadGenerator.roads(near: origin, radiusMeters: 220),
        buildings: PlaceholderCityGenerator.buildings(near: origin, radiusMeters: 220)
    )
    .background(Color.black)
}
