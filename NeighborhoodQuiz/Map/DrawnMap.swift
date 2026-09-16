import CoreGraphics
import SwiftUI

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

/// The whole map, drawn once for a given size and then only ever re-transformed.
///
/// Building this is the expensive part — fifteen hundred runs of road, the shoreline
/// and ninety-six greens, each redrawn twice with a wobbling pen. It happens when the
/// view first gets its size and never again while the map is being pushed about, which
/// is why panning and zooming stay smooth and why the wobble never shifts under your
/// finger: what moves is the transform, not the drawing.
struct DrawnMap {
    /// Where the side streets start to appear, and the zoom by which they are all the
    /// way in. Fading them across a range rather than switching them on at a threshold
    /// keeps the grid from snapping into existence under a pinch.
    static let sideStreetZoom = 1.5
    static let sideStreetFullZoom = 2.3

    let size: CGSize
    let projection: MapProjection
    let land: Path
    let landEdge: Path
    let parks: Path
    let parkEdge: Path
    /// Side streets first, then the major ones, then the avenues on top, so the heavy
    /// lines are never broken by the light ones crossing them.
    let roads: [DrawnRoad]
    let labels: [DrawnLabel]

    static func build(size: CGSize) -> DrawnMap {
        let islands = ManhattanMapData.land
        // Turning the plane back by the grid's own bearing stands the avenues upright.
        let projection = MapProjection(
            fitting: islands.flatMap { $0 },
            in: size,
            padding: 14,
            rotation: -ManhattanGeometry.gridBearingDegrees
        )

        var land = Path()
        var landEdge = Path()
        for (index, ring) in islands.enumerated() {
            let points = projection.points(ring)
            let seed = UInt32(7 &+ index &* 13)
            land.addPath(Pen.fill(points, style: PenStyle(roughness: 1.5, bowing: 1.2, reach: 2.2, seed: seed)))
            landEdge.addPath(Pen.outline(points, style: PenStyle(roughness: 1.5, bowing: 1.2, reach: 2, seed: seed &+ 1)))
        }

        var parks = Path()
        var parkEdge = Path()
        for (index, park) in ManhattanMapData.parks.enumerated() {
            let points = projection.points(park.ring)
            guard points.count >= 3 else { continue }
            let seed = UInt32(401 &+ index &* 7)
            parks.addPath(Pen.fill(points, style: PenStyle(roughness: 1.2, bowing: 1, reach: 1.6, seed: seed)))
            parkEdge.addPath(Pen.outline(points, style: PenStyle(roughness: 1.2, bowing: 1, reach: 1.4, seed: seed &+ 1)))
        }

        var roads: [DrawnRoad] = []
        var labels: [DrawnLabel] = []

        // The data arrives longest street first, which is the order names are offered
        // in: whichever reaches a patch of paper first keeps it.
        for (index, road) in ManhattanMapData.roads.enumerated() {
            let points = projection.points(road.coordinates)
            guard points.count >= 2 else { continue }

            let path = Pen.stroke(points, style: penStyle(for: road.kind, seed: UInt32(index &+ 101)))
            roads.append(DrawnRoad(
                id: index,
                path: path,
                kind: road.kind,
                minZoom: road.kind == .side ? sideStreetZoom : 1,
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

        return DrawnMap(
            size: size,
            projection: projection,
            land: land,
            landEdge: landEdge,
            parks: parks,
            parkEdge: parkEdge,
            roads: roads,
            labels: labels
        )
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
    private static func penStyle(for kind: RoadKind, seed: UInt32) -> PenStyle {
        switch kind {
        case .avenue: return PenStyle(roughness: 1.3, bowing: 1, reach: 1.8, seed: seed)
        case .major: return PenStyle(roughness: 1.2, bowing: 0.9, reach: 1.5, seed: seed)
        case .side: return PenStyle(roughness: 1, bowing: 0.7, reach: 1.1, seed: seed)
        }
    }
}

/// The one thing the 1811 grid is still needed for.
///
/// The streets themselves come from the city now, but Manhattan's grid still runs
/// about twenty-nine degrees east of north, and turning the projected plane back by
/// that much is what stands the avenues upright and lays the cross streets flat. It is
/// the difference between a drawing and a satellite photograph.
enum ManhattanGeometry {
    static let gridBearingDegrees = 29.0
}
