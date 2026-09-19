import CoreGraphics
import SwiftUI

/// The size each street name takes on the page, worked out once and kept.
///
/// Measuring text is laying it out, and it is the expensive half of writing a name.
/// The answer does not depend on where the camera is — the same name at the same size
/// fills the same box on every frame — so doing it afresh for every name on every
/// frame of a drag was a few thousand text layouts a second, all of them arriving at
/// the answer they arrived at last time.
///
/// A class so that every copy of the map shares the one cache. Read and written only
/// from the drawing pass, which SwiftUI runs on a single thread here because the
/// canvas does not render asynchronously.
final class LabelMetrics {
    private var known: [Int: CGSize] = [:]

    func size(of label: DrawnLabel, palette: MapPalette, in context: GraphicsContext) -> CGSize {
        if let measured = known[label.id] { return measured }
        let text = Text(label.text).font(MapFont.label(size: palette.labelSize(for: label.kind)))
        let measured = context.resolve(text).measure(in: CGSize(width: 600, height: 200))
        known[label.id] = measured
        return measured
    }

    /// How many names have been measured so far. For the tests, and for anybody
    /// wondering whether the cache is doing anything.
    var count: Int { known.count }
}

/// A street name, already placed: where it sits on the drawing, which way it is
/// written, and how far the map has to be pulled in before it appears at all.
struct DrawnLabel: Identifiable {
    let id: Int
    let text: String
    let position: CGPoint
    /// Radians. Avenue names run up their avenues; cross street names lie flat.
    let angle: Double
    let kind: RoadKind
    let minZoom: Double
}

/// One inked line, and what kind of road it was.
struct DrawnRoad: Identifiable {
    let id: Int
    let path: Path
    let kind: RoadKind
    /// How far in the map has to be before this line is drawn at all.
    let minZoom: Double
    /// Where this line sits on the drawing, worked out once so that deciding whether it
    /// is on the glass costs one rectangle test rather than walking the path.
    let bounds: CGRect
}

/// The whole map of one borough, drawn once for a given size and then only ever
/// re-transformed.
///
/// Building this is the expensive part — fifteen hundred runs of road, the shoreline
/// and ninety-six greens, each redrawn twice with a wobbling pen. It happens when the
/// view first gets its size and never again while the map is being pushed about, which
/// is why panning and zooming stay smooth and why the wobble never shifts under your
/// finger: what moves is the transform, not the drawing. Changing borough is the one
/// other thing that builds it again, because that is a different drawing altogether.
struct DrawnMap {
    /// Where the side streets start to appear, and the zoom by which they are all the
    /// way in. Fading them across a range rather than switching them on at a threshold
    /// keeps the grid from snapping into existence under a pinch.
    static let sideStreetZoom = 1.5
    static let sideStreetFullZoom = 2.3

    /// Which borough this is a drawing of. The board checks it against the one it has
    /// been asked for, the same way it checks the size.
    let borough: Borough
    let size: CGSize
    let projection: MapProjection
    let land: Path
    let landEdge: Path
    let parks: Path
    let parkEdge: Path
    /// The tappable shapes — forty in Manhattan, fifty-odd in Brooklyn — in the order
    /// the data holds them.
    let neighborhoods: [DrawnNeighborhood]
    /// Side streets first, then the major ones, then the avenues on top, so the heavy
    /// lines are never broken by the light ones crossing them.
    let roads: [DrawnRoad]
    let labels: [DrawnLabel]

    /// Every road of a kind gathered into one path, indexed by `RoadKind.rawValue`.
    ///
    /// Each road of a kind is drawn in the same colour at the same weight — they share
    /// a `minZoom`, so they fade in together and there is never a frame where two side
    /// streets want different ink. That means a view showing most of them can put them
    /// down in one stroke instead of a thousand, which is what the whole borough at
    /// once used to cost: nothing is off the glass at that zoom, so nothing was culled
    /// and every road paid its own call.
    let roadSheets: [Path]

    /// The measured size of every street name, filled in as each is first drawn.
    let metrics = LabelMetrics()

    static func build(borough: Borough, size: CGSize) -> DrawnMap {
        let data = BoroughMap.of(borough)
        let islands = data.land
        // Turning the plane back by the grid's own bearing stands the avenues upright.
        // Manhattan's is twenty-nine degrees; Brooklyn's is nought, and is drawn as it
        // sits — see `Borough.gridBearingDegrees` for why.
        let projection = MapProjection(
            fitting: islands.flatMap { $0 },
            in: size,
            padding: 14,
            rotation: -borough.gridBearingDegrees
        )

        var land = Path()
        var landEdge = Path()
        for (index, ring) in islands.enumerated() {
            let points = projection.points(ring)
            let seed = UInt32(7 &+ index &* 13)
            land.addPath(Pen.fill(points, style: PenStyle(roughness: 0.4, bowing: 0.32, reach: 1.1, seed: seed)))
            landEdge.addPath(Pen.outline(points, style: PenStyle(roughness: 0.4, bowing: 0.32, reach: 1, seed: seed &+ 1)))
        }

        var parks = Path()
        var parkEdge = Path()
        for (index, park) in data.parks.enumerated() {
            let points = projection.points(park.ring)
            guard points.count >= 3 else { continue }
            let seed = UInt32(401 &+ index &* 7)
            parks.addPath(Pen.fill(points, style: PenStyle(roughness: 0.32, bowing: 0.26, reach: 0.9, seed: seed)))
            parkEdge.addPath(Pen.outline(points, style: PenStyle(roughness: 0.32, bowing: 0.26, reach: 0.8, seed: seed &+ 1)))
        }

        var neighborhoods: [DrawnNeighborhood] = []
        for (index, area) in data.neighborhoods.enumerated() {
            let rings = area.rings.map(projection.points).filter { $0.count >= 3 }
            guard !rings.isEmpty else { continue }

            var shape = Path()
            var edge = Path()
            for (ringIndex, ring) in rings.enumerated() {
                let seed = UInt32(9_001 &+ index &* 17 &+ ringIndex)
                shape.addPath(Pen.fill(ring, style: PenStyle(roughness: 0.3, bowing: 0.24, reach: 0.9, seed: seed)))
                edge.addPath(Pen.outline(ring, style: PenStyle(roughness: 0.3, bowing: 0.24, reach: 0.8, seed: seed &+ 1)))
            }

            let widest = rings.max { $0.count < $1.count } ?? []
            var anchor = DrawnNeighborhood.centroid(of: widest)
            if !DrawnNeighborhood.ring(widest, contains: anchor) {
                anchor = DrawnNeighborhood.insidePoint(of: widest, near: anchor)
            }

            var box = CGRect.null
            for ring in rings {
                for point in ring { box = box.union(CGRect(origin: point, size: .zero)) }
            }

            neighborhoods.append(DrawnNeighborhood(
                id: index,
                name: area.name,
                shape: shape,
                edge: edge,
                rings: rings,
                bounds: box,
                labelPoint: anchor
            ))
        }

        var roads: [DrawnRoad] = []
        var labels: [DrawnLabel] = []

        // The data arrives longest street first, which is the order names are offered
        // in: whichever reaches a patch of paper first keeps it.
        for (index, road) in data.roads.enumerated() {
            let points = projection.points(road.coordinates)
            guard points.count >= 2 else { continue }

            let path = Pen.stroke(points, style: penStyle(for: road.kind, seed: UInt32(index &+ 101)))
            roads.append(DrawnRoad(
                id: index,
                path: path,
                kind: road.kind,
                minZoom: minZoom(for: road.kind),
                bounds: path.boundingRect
            ))

            guard road.carriesName, !road.name.isEmpty else { continue }
            let position = Polyline.midpoint(of: points)
            labels.append(DrawnLabel(
                id: index,
                text: road.name,
                position: position,
                angle: Polyline.heading(of: points, near: position),
                kind: road.kind,
                minZoom: labelZoom(for: road.kind)
            ))
        }

        // Light lines under heavy ones. A stable sort would be tidier but the key is
        // the only thing the drawing cares about.
        roads.sort { $0.kind.rawValue > $1.kind.rawValue }

        var sheets = [Path](repeating: Path(), count: RoadKind.allCases.count)
        for road in roads {
            sheets[road.kind.rawValue].addPath(road.path)
        }

        return DrawnMap(
            borough: borough,
            size: size,
            projection: projection,
            land: land,
            landEdge: landEdge,
            parks: parks,
            parkEdge: parkEdge,
            neighborhoods: neighborhoods,
            roads: roads,
            labels: labels,
            roadSheets: sheets
        )
    }

    /// Which neighbourhood a point of the drawing falls in, if any.
    ///
    /// The areas tile the borough without overlapping, so the first one that claims the
    /// point is the only one that would — but the water, and the holes the parks leave
    /// in the coverage, belong to nobody, and a tap there is a tap on nothing.
    func neighborhood(at point: CGPoint) -> DrawnNeighborhood? {
        neighborhoods.first { $0.contains(point) }
    }

    func neighborhood(named name: String) -> DrawnNeighborhood? {
        neighborhoods.first { $0.name == name }
    }

    /// How far in the map must be before a road of this rank is drawn at all.
    ///
    /// Of the rank, not of the road: every road of a rank shares this, so they fade in
    /// together and always carry the same ink. That is the fact the drawing leans on
    /// when it puts a whole rank down in one stroke.
    static func minZoom(for kind: RoadKind) -> Double {
        kind == .side ? sideStreetZoom : 1
    }

    /// How much of a rank is on the page at a given zoom, from nothing to all of it.
    ///
    /// The side streets come in over a range rather than at a threshold, so pinching
    /// fills the grid in instead of snapping it on. The avenues and the major streets
    /// are simply always there.
    ///
    /// This lives here rather than in the drawing because two things depend on it and
    /// they must not disagree: what shade a rank is drawn in, and whether it is allowed
    /// to go down as one stroke. The second is only safe at full ink.
    static func presence(of kind: RoadKind, at zoom: Double) -> Double {
        let start = minZoom(for: kind)
        guard start > 1 else { return 1 }
        let span = sideStreetFullZoom - start
        guard span > 0 else { return zoom >= start ? 1 : 0 }
        return min(max((zoom - start) / span, 0), 1)
    }

    /// How far in the map must be before a name of this rank is written. The avenues
    /// are offered from the start and the collision check decides how many of them
    /// actually fit; the rest wait until there is room to be worth offering.
    static func labelZoom(for kind: RoadKind) -> Double {
        switch kind {
        case .avenue: return 1
        case .major: return 2.2
        case .side: return 4
        }
    }

    /// A heavier road is drawn with a steadier hand: the avenues were ruled off a long
    /// straight edge and the side streets were filled in afterwards, which is roughly
    /// how a person drawing this would have gone about it.
    ///
    /// The hand is much steadier than it was. These numbers were first set against a
    /// map of 269 generated streets, where a wandering line was most of what said the
    /// drawing was drawn; against fifteen hundred real ones it read as a shake rather
    /// than a style, and Broadway wavered where Broadway does not. A third of the old
    /// stray leaves the doubled stroke and the soft corners doing the work, which is
    /// where the hand shows anyway.
    private static func penStyle(for kind: RoadKind, seed: UInt32) -> PenStyle {
        switch kind {
        case .avenue: return PenStyle(roughness: 0.35, bowing: 0.28, reach: 1, seed: seed)
        case .major: return PenStyle(roughness: 0.32, bowing: 0.25, reach: 0.9, seed: seed)
        case .side: return PenStyle(roughness: 0.28, bowing: 0.2, reach: 0.7, seed: seed)
        }
    }
}
