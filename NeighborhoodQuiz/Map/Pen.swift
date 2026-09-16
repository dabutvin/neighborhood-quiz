import CoreGraphics
import SwiftUI

/// A repeatable random source, so the pen wobbles the same way every time the map is
/// drawn. Without this the island would shimmer on every rotation and every redraw,
/// which is the one thing a drawing must not do.
///
/// This is mulberry32: a whole-word counter run through a couple of multiply-and-xor
/// rounds. Small, fast, and good enough for a pen that is only pretending to be shaky.
struct SeededRandom {
    private var state: UInt32

    init(seed: UInt32) {
        // Anything but zero, which mulberry32 sits still on.
        state = seed &* 2_654_435_761 &+ 1
    }

    /// The next value, in `0..<1`.
    mutating func next() -> Double {
        state = state &+ 0x6D2B_79F5
        var z = state
        z = (z ^ (z >> 15)) &* (z | 1)
        z = z ^ (z &+ ((z ^ (z >> 7)) &* (z | 61)))
        z = z ^ (z >> 14)
        return Double(z) / Double(UInt32.max)
    }

    /// The next value, somewhere in `range`.
    mutating func next(in range: ClosedRange<Double>) -> Double {
        range.lowerBound + next() * (range.upperBound - range.lowerBound)
    }
}

/// How shaky the pen is for one thing it draws.
struct PenStyle {
    /// How far the pen strays. 0 is a ruler; the map uses about 1.5.
    var roughness: Double = 1.4
    /// How much a straight line bends on its way between its ends.
    var bowing: Double = 1.2
    /// The pen's reach, in points, before roughness scales it.
    var reach: Double = 2
    /// Which wobble this is. Two things drawn with the same seed wobble identically.
    var seed: UInt32 = 1
}

/// Turns straight geometry into the kind of line somebody draws with a pen that is not
/// quite steady and a hand that is not quite patient.
///
/// The arithmetic follows rough.js, which is what the Park Slope map is drawn with:
/// every straight run becomes a shallow bezier that leaves its start a little off the
/// mark, bends somewhere past a third of the way along, and arrives a little off the
/// other end — and then the whole thing is drawn a second time, slightly differently,
/// because a person going over a line twice never quite retraces it.
enum Pen {
    /// An open run of points, drawn twice.
    static func stroke(_ points: [CGPoint], style: PenStyle) -> Path {
        guard points.count >= 2 else { return Path() }
        var random = SeededRandom(seed: style.seed)
        var path = Path()
        for pass in 0..<2 {
            for index in 0..<(points.count - 1) {
                append(
                    &path,
                    from: points[index],
                    to: points[index + 1],
                    overlay: pass == 1,
                    style: style,
                    random: &random
                )
            }
        }
        return path
    }

    /// A closed ring, drawn twice. Use for an inked edge over a fill.
    static func outline(_ ring: [CGPoint], style: PenStyle) -> Path {
        guard ring.count >= 3 else { return stroke(ring, style: style) }
        return stroke(ring + [ring[0]], style: style)
    }

    /// A closed ring as one continuous shape, for filling. Every corner is nudged and
    /// every edge bowed, so the fill has the same unsteady edge the ink does — but it
    /// stays a single subpath, which a fill needs and a double-drawn outline is not.
    static func fill(_ ring: [CGPoint], style: PenStyle) -> Path {
        guard ring.count >= 3 else { return Path() }
        var random = SeededRandom(seed: style.seed)
        let reach = style.reach * style.roughness

        let nudged = ring.map { point in
            CGPoint(
                x: Double(point.x) + random.next(in: -reach...reach),
                y: Double(point.y) + random.next(in: -reach...reach)
            )
        }

        var path = Path()
        path.move(to: nudged[0])
        for index in 0..<nudged.count {
            let start = nudged[index]
            let end = nudged[(index + 1) % nudged.count]
            path.addQuadCurve(to: end, control: bowedMidpoint(
                from: start,
                to: end,
                style: style,
                random: &random
            ))
        }
        path.closeSubpath()
        return path
    }

    /// The midpoint of an edge, pushed off to one side so the edge bellies out.
    private static func bowedMidpoint(
        from start: CGPoint,
        to end: CGPoint,
        style: PenStyle,
        random: inout SeededRandom
    ) -> CGPoint {
        let dx = Double(end.x - start.x)
        let dy = Double(end.y - start.y)
        let length = max(sqrt(dx * dx + dy * dy), 0.0001)
        // A perpendicular of unit length, times a bow that grows with the edge but
        // never runs away with it.
        let bow = style.bowing * min(length / 24, style.reach * 2)
        let push = random.next(in: -bow...bow)
        return CGPoint(
            x: (Double(start.x) + Double(end.x)) / 2 - dy / length * push,
            y: (Double(start.y) + Double(end.y)) / 2 + dx / length * push
        )
    }

    private static func append(
        _ path: inout Path,
        from start: CGPoint,
        to end: CGPoint,
        overlay: Bool,
        style: PenStyle,
        random: inout SeededRandom
    ) {
        let dx = Double(end.x - start.x)
        let dy = Double(end.y - start.y)
        let lengthSquared = dx * dx + dy * dy
        let length = sqrt(lengthSquared)

        // A long line drawn freehand is *steadier* than a short one, proportionally —
        // the hand commits to it. Past five hundred points the wobble is damped right
        // down, below two hundred it is left alone.
        let gain: Double
        if length < 200 {
            gain = 1
        } else if length > 500 {
            gain = 0.4
        } else {
            gain = -0.0016668 * length + 1.233334
        }

        var reach = style.reach
        if reach * reach * 100 > lengthSquared {
            reach = length / 10
        }
        let spread = overlay ? reach / 2 : reach

        func strayed() -> Double {
            style.roughness * gain * random.next(in: -spread...spread)
        }

        // Where the line stops going straight. Somewhere in the first fifth to
        // two-fifths, never the middle, which would read as a deliberate curve.
        let diverge = 0.2 + random.next() * 0.2

        // The belly of the line, perpendicular to it and proportional to its length.
        // Only the size of the displacement matters, so the span is taken as a
        // magnitude — a negative one would be the same wobble described backwards.
        let bowSpanX = abs(style.bowing * style.reach * dy / 200)
        let bowSpanY = abs(style.bowing * style.reach * dx / 200)
        let bowX = style.roughness * gain * random.next(in: -bowSpanX...bowSpanX)
        let bowY = style.roughness * gain * random.next(in: -bowSpanY...bowSpanY)

        path.move(to: CGPoint(x: Double(start.x) + strayed(), y: Double(start.y) + strayed()))
        path.addCurve(
            to: CGPoint(x: Double(end.x) + strayed(), y: Double(end.y) + strayed()),
            control1: CGPoint(
                x: bowX + Double(start.x) + dx * diverge + strayed(),
                y: bowY + Double(start.y) + dy * diverge + strayed()
            ),
            control2: CGPoint(
                x: bowX + Double(start.x) + 2 * dx * diverge + strayed(),
                y: bowY + Double(start.y) + 2 * dy * diverge + strayed()
            )
        )
    }
}
