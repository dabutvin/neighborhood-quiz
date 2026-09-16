import CoreGraphics
import SwiftUI

/// A street name, already placed: where it sits on the drawing, which way it is
/// written, and how far the map has to be pulled in before it appears at all.
struct DrawnLabel: Identifiable {
    let id: String
    let text: String
    let position: CGPoint
    /// Radians. Avenue names run up their avenues; cross street names lie flat.
    let angle: Double
    let kind: RoadKind
    let minZoom: Double
}

/// One inked line, and what kind of road it was.
struct DrawnRoad: Identifiable {
    let id: String
    let path: Path
    let kind: RoadKind
    /// How far in the map has to be before this line is drawn at all.
    ///
    /// Two hundred side streets on a four-inch screen showing thirteen miles of city is
    /// not texture, it is a smudge — the island came out a solid block of hatching. So
    /// the side streets arrive the way their names do, once there is room for them, and
    /// the wide view is the island, the park, the avenues and the streets people name.
    let minZoom: Double
}

/// The whole map, drawn once for a given size and then only ever re-transformed.
///
/// Building this is the expensive part — two hundred and some roads, each cut against
/// the shoreline and then redrawn twice with a wobbling pen. It happens when the view
/// first gets its size and never again while the map is being pushed about, which is
/// why panning and zooming stay smooth and why the wobble never shifts under your
/// finger: what moves is the transform, not the drawing.
struct DrawnMap {
    let size: CGSize
    let projection: MapProjection
    let land: Path
    let landEdge: Path
    let park: Path
    let parkEdge: Path
    /// Fine cross streets first, then the major ones, then the avenues on top, so the
    /// heavy lines are never broken by the light ones crossing them.
    let roads: [DrawnRoad]
    let labels: [DrawnLabel]

    static func build(size: CGSize) -> DrawnMap {
        let shore = ManhattanMapData.shoreline
        // Turning the plane back by the grid's own bearing stands the avenues upright.
        let projection = MapProjection(
            fitting: shore,
            in: size,
            padding: 14,
            rotation: -ManhattanGrid.bearingDegrees
        )

        let shorePoints = projection.points(shore)
        let land = Pen.fill(shorePoints, style: PenStyle(roughness: 1.6, bowing: 1.4, reach: 2.4, seed: 7))
        let landEdge = Pen.outline(shorePoints, style: PenStyle(roughness: 1.7, bowing: 1.5, reach: 2.2, seed: 11))

        let parkPoints = projection.points(ManhattanMapData.centralPark)
        let park = Pen.fill(parkPoints, style: PenStyle(roughness: 1.4, bowing: 1.1, reach: 2, seed: 23))
        let parkEdge = Pen.outline(parkPoints, style: PenStyle(roughness: 1.4, bowing: 1.1, reach: 1.8, seed: 29))

        var roads: [DrawnRoad] = []
        var labels: [DrawnLabel] = []

        for (index, road) in ManhattanMapData.roads.enumerated() {
            let runs = Shoreline.clip(projection.points(road.coordinates), to: shorePoints)
            guard !runs.isEmpty else { continue }

            let style = penStyle(for: road.kind, seed: UInt32(index &+ 101))
            for (runIndex, run) in runs.enumerated() {
                roads.append(DrawnRoad(
                    id: "\(index)-\(runIndex)",
                    path: Pen.stroke(run, style: style),
                    kind: road.kind,
                    minZoom: road.kind == .crossStreet ? DrawnMap.sideStreetZoom : 1
                ))
            }

            // The name goes on the longest piece of the road that survived the water —
            // a street cut in two by the park should be named on its longer half, not
            // on whichever half happened to be clipped first.
            guard let longest = runs.max(by: { Shoreline.length(of: $0) < Shoreline.length(of: $1) }) else {
                continue
            }
            let anchor = road.labelAnchor.map(projection.point) ?? Shoreline.midpoint(of: longest)
            // An anchor placed by hand can land off the end of what survived; fall back
            // to the middle of the line rather than writing the name out in the river.
            let position = Shoreline.contains(shorePoints, anchor) ? anchor : Shoreline.midpoint(of: longest)

            labels.append(DrawnLabel(
                id: "\(index)",
                text: road.name,
                position: position,
                angle: Shoreline.heading(of: longest, near: position),
                kind: road.kind,
                minZoom: road.labelMinZoom
            ))
        }

        roads.sort { drawingOrder($0.kind) < drawingOrder($1.kind) }
        // Names are drawn in this order and the first to claim a piece of the page keeps
        // it, so the order is the priority: an avenue's name beats a side street's.
        labels.sort { labelOrder($0.kind) < labelOrder($1.kind) }

        return DrawnMap(
            size: size,
            projection: projection,
            land: land,
            landEdge: landEdge,
            park: park,
            parkEdge: parkEdge,
            roads: roads,
            labels: labels
        )
    }

    /// Where the side streets start to appear, and the zoom by which they are all the
    /// way in. Fading them across a range rather than switching them on at a threshold
    /// keeps the grid from snapping into existence under a pinch.
    static let sideStreetZoom = 1.35
    static let sideStreetFullZoom = 1.9

    /// A heavier road is drawn with a steadier hand: the avenues were ruled off a long
    /// straight edge and the side streets were filled in afterwards, which is roughly
    /// how a person drawing this would have gone about it.
    private static func penStyle(for kind: RoadKind, seed: UInt32) -> PenStyle {
        switch kind {
        case .avenue:
            return PenStyle(roughness: 1.4, bowing: 1.1, reach: 2, seed: seed)
        case .namedStreet:
            return PenStyle(roughness: 1.5, bowing: 1.2, reach: 2, seed: seed)
        case .majorCrossStreet:
            return PenStyle(roughness: 1.3, bowing: 1, reach: 1.7, seed: seed)
        case .crossStreet:
            return PenStyle(roughness: 1.1, bowing: 0.8, reach: 1.3, seed: seed)
        }
    }

    private static func drawingOrder(_ kind: RoadKind) -> Int {
        switch kind {
        case .crossStreet: return 0
        case .majorCrossStreet: return 1
        case .namedStreet: return 2
        case .avenue: return 3
        }
    }

    /// The reverse of the drawing order: what gets its name written first when two names
    /// want the same piece of paper.
    private static func labelOrder(_ kind: RoadKind) -> Int {
        switch kind {
        case .avenue: return 0
        case .namedStreet: return 1
        case .majorCrossStreet: return 2
        case .crossStreet: return 3
        }
    }
}
