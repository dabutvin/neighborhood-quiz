import CoreGraphics
import Foundation

/// Cutting lines off at the water's edge.
///
/// The grid is arithmetic, so a numbered street drawn from it runs out into the Hudson
/// on one side and the East River on the other. Rather than teach every street how wide
/// the island is at its latitude, each one is drawn far too long and then cut against
/// the shoreline — which means the map's edges come from the one traced outline, and a
/// correction to the shoreline corrects every street that meets it.
enum Shoreline {
    /// The parts of `points` that fall inside `polygon`, each returned as its own run.
    /// A street crossing the island once comes back as one run; one that clips a
    /// headland twice comes back as two.
    static func clip(_ points: [CGPoint], to polygon: [CGPoint]) -> [[CGPoint]] {
        guard points.count >= 2, polygon.count >= 3 else { return [] }

        var runs: [[CGPoint]] = []
        var current: [CGPoint] = []

        func flush() {
            if current.count >= 2 { runs.append(current) }
            current = []
        }

        for index in 0..<(points.count - 1) {
            let start = points[index]
            let end = points[index + 1]

            // Every place this segment meets the shore, plus its own two ends.
            var cuts: [Double] = [0, 1]
            for edge in 0..<polygon.count {
                let a = polygon[edge]
                let b = polygon[(edge + 1) % polygon.count]
                if let t = crossing(start, end, a, b) { cuts.append(t) }
            }
            cuts.sort()

            for step in 0..<(cuts.count - 1) {
                let from = cuts[step]
                let to = cuts[step + 1]
                if to - from < 1e-9 { continue }

                // Between two consecutive crossings the piece is wholly in or wholly
                // out, so its midpoint settles it.
                guard contains(polygon, interpolate(start, end, (from + to) / 2)) else {
                    flush()
                    continue
                }

                let head = interpolate(start, end, from)
                let tail = interpolate(start, end, to)
                if current.isEmpty {
                    current = [head, tail]
                } else if isNear(current[current.count - 1], head) {
                    current.append(tail)
                } else {
                    flush()
                    current = [head, tail]
                }
            }
        }

        flush()
        return runs
    }

    /// Whether `point` is inside `polygon`, by counting the times a ray heading east
    /// out of it crosses an edge.
    static func contains(_ polygon: [CGPoint], _ point: CGPoint) -> Bool {
        guard polygon.count >= 3 else { return false }
        var inside = false
        var previous = polygon.count - 1
        for index in 0..<polygon.count {
            let a = polygon[index]
            let b = polygon[previous]
            if (a.y > point.y) != (b.y > point.y) {
                let x = (b.x - a.x) * (point.y - a.y) / (b.y - a.y) + a.x
                if point.x < x { inside.toggle() }
            }
            previous = index
        }
        return inside
    }

    /// How far along `a`→`b` it crosses `c`→`d`, or nil if the two segments miss.
    static func crossing(_ a: CGPoint, _ b: CGPoint, _ c: CGPoint, _ d: CGPoint) -> Double? {
        let abx = Double(b.x - a.x)
        let aby = Double(b.y - a.y)
        let cdx = Double(d.x - c.x)
        let cdy = Double(d.y - c.y)

        let denominator = abx * cdy - aby * cdx
        if abs(denominator) < 1e-12 { return nil }  // parallel, or both a point

        let acx = Double(c.x - a.x)
        let acy = Double(c.y - a.y)
        let alongAB = (acx * cdy - acy * cdx) / denominator
        let alongCD = (acx * aby - acy * abx) / denominator

        guard (0...1).contains(alongAB), (0...1).contains(alongCD) else { return nil }
        return alongAB
    }

    static func interpolate(_ a: CGPoint, _ b: CGPoint, _ t: Double) -> CGPoint {
        CGPoint(
            x: Double(a.x) + (Double(b.x) - Double(a.x)) * t,
            y: Double(a.y) + (Double(b.y) - Double(a.y)) * t
        )
    }

    /// How long a run of points is, end to end along itself.
    static func length(of points: [CGPoint]) -> Double {
        guard points.count >= 2 else { return 0 }
        var total = 0.0
        for index in 0..<(points.count - 1) {
            let dx = Double(points[index + 1].x - points[index].x)
            let dy = Double(points[index + 1].y - points[index].y)
            total += sqrt(dx * dx + dy * dy)
        }
        return total
    }

    /// The point halfway along a run, measured by distance rather than by index.
    static func midpoint(of points: [CGPoint]) -> CGPoint {
        guard points.count >= 2 else { return points.first ?? .zero }
        let half = length(of: points) / 2
        var travelled = 0.0
        for index in 0..<(points.count - 1) {
            let dx = Double(points[index + 1].x - points[index].x)
            let dy = Double(points[index + 1].y - points[index].y)
            let step = sqrt(dx * dx + dy * dy)
            if travelled + step >= half, step > 0 {
                return interpolate(points[index], points[index + 1], (half - travelled) / step)
            }
            travelled += step
        }
        return points[points.count - 1]
    }

    /// How far off vertical a line may lean and still be written as a vertical one.
    ///
    /// An avenue is not *quite* vertical once projected. Mercator stretches latitude
    /// unevenly, so a line that is dead straight on the grid bends about a hundredth of
    /// a degree over a hundred blocks — and with the fold below sitting exactly on the
    /// quarter turn, that hundredth was enough to drop Fifth Avenue on the side that
    /// reads *downwards* while its neighbours read up. Two degrees of slack is far more
    /// than the projection's bend and far less than any real diagonal.
    static let uprightTolerance = 2.0 * Double.pi / 180

    /// Which way the run is heading where it passes closest to `point`, as an angle in
    /// radians. Street names are written along their streets, so this is what tilts them.
    static func heading(of points: [CGPoint], near point: CGPoint) -> Double {
        guard points.count >= 2 else { return 0 }
        var bestIndex = 0
        var bestDistance = Double.greatestFiniteMagnitude
        for index in 0..<(points.count - 1) {
            let mid = interpolate(points[index], points[index + 1], 0.5)
            let dx = Double(mid.x - point.x)
            let dy = Double(mid.y - point.y)
            let distance = dx * dx + dy * dy
            if distance < bestDistance {
                bestDistance = distance
                bestIndex = index
            }
        }

        let dx = Double(points[bestIndex + 1].x - points[bestIndex].x)
        let dy = Double(points[bestIndex + 1].y - points[bestIndex].y)

        // A name is written left to right, and a name on a vertical street is written
        // from the bottom up — so a heading and the same heading turned round are the
        // same thing to write along. Folding the angle into a half turn gives one answer
        // for both, and never one that reads upside down or back to front.
        //
        // The window is that half turn shifted by `uprightTolerance`, which is what puts
        // anything within a couple of degrees of vertical on the upward side of the fold
        // rather than leaving it to which side of the quarter turn it happened to land.
        let top = Double.pi / 2 - uprightTolerance
        var angle = atan2(dy, dx)
        while angle >= top { angle -= .pi }
        while angle < top - .pi { angle += .pi }
        return angle
    }

    private static func isNear(_ a: CGPoint, _ b: CGPoint) -> Bool {
        abs(a.x - b.x) < 1e-6 && abs(a.y - b.y) < 1e-6
    }
}
