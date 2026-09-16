import CoreGraphics
import SwiftUI

/// A neighborhood as the map holds it: the shape to fill, the line round it, and the
/// polygons a tap is tested against.
///
/// The shape that is drawn and the shape that is hit are the same points. They are
/// thinned once when the data is fetched and never again, so a tap can never land a
/// pixel outside the thing it looks like it landed in.
struct DrawnNeighborhood: Identifiable {
    let id: Int
    let name: String
    /// Filled when this one is picked out.
    let shape: Path
    /// The line round it, drawn faintly for every neighborhood and firmly for the
    /// chosen one.
    let edge: Path
    /// The projected rings, for hit testing. Not the wobbled ones — a tap is tested
    /// against the geometry, not against the pen's opinion of it.
    let rings: [[CGPoint]]
    /// Worked out once, so a tap tests one rectangle before it tests any polygon.
    let bounds: CGRect
    /// Where its name is written when it is picked out: the middle of its largest
    /// piece, pulled inside the shape if the middle happens to fall outside it.
    let labelPoint: CGPoint

    /// Whether a point on the drawing falls inside this neighborhood.
    func contains(_ point: CGPoint) -> Bool {
        guard bounds.contains(point) else { return false }
        return rings.contains { DrawnNeighborhood.ring($0, contains: point) }
    }

    /// Ray casting: does a ray heading east out of `point` cross the ring an odd
    /// number of times?
    static func ring(_ ring: [CGPoint], contains point: CGPoint) -> Bool {
        guard ring.count >= 3 else { return false }
        var inside = false
        var previous = ring.count - 1
        for index in ring.indices {
            let a = ring[index]
            let b = ring[previous]
            if (a.y > point.y) != (b.y > point.y) {
                let crossing = (b.x - a.x) * (point.y - a.y) / (b.y - a.y) + a.x
                if point.x < crossing { inside.toggle() }
            }
            previous = index
        }
        return inside
    }

    /// The centre of area of a ring. A neighborhood is rarely a blob — the Financial
    /// District wraps round Battery Park City, Chelsea is a long strip — so the middle
    /// of the *bounding box* often falls outside the shape, and a name written there
    /// would sit in the river. The centroid is a better guess, and it is checked
    /// against the shape anyway.
    static func centroid(of ring: [CGPoint]) -> CGPoint {
        guard ring.count >= 3 else { return ring.first ?? .zero }
        var twiceArea = 0.0
        var x = 0.0
        var y = 0.0
        for index in ring.indices {
            let a = ring[index]
            let b = ring[(index + 1) % ring.count]
            let cross = Double(a.x) * Double(b.y) - Double(b.x) * Double(a.y)
            twiceArea += cross
            x += (Double(a.x) + Double(b.x)) * cross
            y += (Double(a.y) + Double(b.y)) * cross
        }
        guard abs(twiceArea) > 1e-9 else {
            // Degenerate: fall back to the average of the corners.
            let count = Double(ring.count)
            return CGPoint(
                x: ring.reduce(0.0) { $0 + Double($1.x) } / count,
                y: ring.reduce(0.0) { $0 + Double($1.y) } / count
            )
        }
        return CGPoint(x: x / (3 * twiceArea), y: y / (3 * twiceArea))
    }

    /// A point that is definitely inside the ring, at the height of `point`. Used when
    /// a centroid lands in the notch of a horseshoe.
    static func insidePoint(of ring: [CGPoint], near point: CGPoint) -> CGPoint {
        guard ring.count >= 3 else { return point }
        // Every place the ring crosses this height, in order; the middle of the widest
        // gap between an entering and a leaving edge is well inside the shape.
        var crossings: [Double] = []
        var previous = ring.count - 1
        for index in ring.indices {
            let a = ring[index]
            let b = ring[previous]
            if (a.y > point.y) != (b.y > point.y) {
                crossings.append((b.x - a.x) * (point.y - a.y) / (b.y - a.y) + a.x)
            }
            previous = index
        }
        crossings.sort()
        var best = point
        var widest = 0.0
        var pair = 0
        while pair + 1 < crossings.count {
            let span = crossings[pair + 1] - crossings[pair]
            if span > widest {
                widest = span
                best = CGPoint(x: (crossings[pair] + crossings[pair + 1]) / 2, y: point.y)
            }
            pair += 2
        }
        return widest > 0 ? best : point
    }
}
