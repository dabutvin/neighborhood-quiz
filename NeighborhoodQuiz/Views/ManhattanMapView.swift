import SwiftUI

/// The island, drawn.
///
/// Everything below the labels happens inside one `Canvas`: the paths are built once
/// for the view's size and then re-stroked under whatever transform the camera is
/// holding, with every pen weight divided by the zoom so a line stays a line rather
/// than swelling into a band as you come in on it. The names are drawn afterwards, in
/// screen coordinates, so they keep their size too — pulling the map in shows *more*
/// street names rather than bigger ones.
struct ManhattanMapView: View {
    let drawn: DrawnMap
    let camera: MapCamera
    let palette: MapPalette
    /// Which neighbourhood is picked out, if any, by `DrawnNeighborhood.id`.
    var selected: Int?
    /// Whether a finger is on the map right now. Drawing is at its most expensive
    /// exactly when it has the least time, so a couple of things the eye cannot follow
    /// mid-drag are left until the map is still again.
    var interacting: Bool = false

    var body: some View {
        Canvas { context, size in
            draw(map: drawn, in: &context, size: size)
            // The picked-out name claims its paper before any street name is offered
            // one, so a street is never written across the answer.
            let claimed = drawName(in: &context, size: size)
            draw(labels: drawn.labels, in: &context, size: size, claimed: claimed)
        }
        // Text drawn inside a `Canvas` is resolved against the canvas's own
        // environment, and this is the only way to reach it: `Text` has no alignment
        // modifier that hands back a `Text`. It matters for one label — a long
        // neighbourhood name wrapping onto a second line — and does nothing at all to
        // the street names, which are a line each.
        .multilineTextAlignment(.center)
    }

    /// The picked-out neighbourhood. Held by identity rather than by position, so a map
    /// rebuilt for a new size — a rotation, a split view — keeps hold of the same place
    /// whatever order the new list came out in.
    private var chosen: DrawnNeighborhood? {
        guard let selected else { return nil }
        return drawn.neighborhoods.first { $0.id == selected }
    }

    // MARK: - The drawing

    private func draw(map: DrawnMap, in context: inout GraphicsContext, size: CGSize) {
        var board = context
        let centre = CGPoint(x: size.width / 2, y: size.height / 2)
        let zoom = CGFloat(camera.zoom)
        board.translateBy(x: centre.x + camera.pan.width, y: centre.y + camera.pan.height)
        board.scaleBy(x: zoom, y: zoom)
        board.translateBy(x: -centre.x, y: -centre.y)

        board.fill(map.land, with: .color(palette.land))
        board.stroke(
            map.landEdge,
            with: .color(palette.waterInk.opacity(0.85)),
            style: StrokeStyle(lineWidth: 2.2 / zoom, lineCap: .round, lineJoin: .round)
        )

        board.fill(map.parks, with: .color(palette.park))
        board.stroke(
            map.parkEdge,
            with: .color(palette.parkInk),
            style: StrokeStyle(lineWidth: 1.2 / zoom, lineCap: .round, lineJoin: .round)
        )

        // Only the roads on the glass. A stroke that lands entirely off the edge costs
        // the same as one you can see, and at four times in almost all of them do.
        let onScreen = camera.visibleRect(in: size, margin: 8)

        // The wash goes under the streets rather than over them, so a picked-out
        // neighbourhood is tinted paper with its own grid still showing through it
        // rather than a sticker laid on top of the map.
        if let chosen {
            board.fill(chosen.shape, with: .color(palette.highlight.opacity(0.3)))
        }

        // Every border, faint and broken. Dashes are what keep these from reading as
        // more roads: no street on this map is drawn with gaps in it.
        for area in map.neighborhoods where area.bounds.intersects(onScreen) {
            guard area.id != selected else { continue }
            board.stroke(
                area.edge,
                with: .color(palette.border.opacity(0.4)),
                style: StrokeStyle(
                    lineWidth: 1 / zoom,
                    lineCap: .round,
                    lineJoin: .round,
                    dash: [5 / zoom, 4.5 / zoom]
                )
            )
        }

        for road in map.roads {
            guard road.bounds.intersects(onScreen) else { continue }
            let ink = presence(of: road)
            guard ink > 0.01 else { continue }
            board.stroke(
                road.path,
                with: .color(palette.colour(for: road.kind).opacity(ink)),
                style: StrokeStyle(
                    lineWidth: CGFloat(palette.weight(for: road.kind)) / zoom,
                    lineCap: .round,
                    lineJoin: .round
                )
            )
        }

        // And the chosen one's own line, unbroken and over the top of everything, which
        // is what makes it read as one shape rather than as a stain on the drawing.
        if let chosen {
            board.stroke(
                chosen.edge,
                with: .color(palette.highlightInk),
                style: StrokeStyle(lineWidth: 2 / zoom, lineCap: .round, lineJoin: .round)
            )
        }
    }

    /// How much of a road is on the page. The side streets come in over a range rather
    /// than at a threshold, so pinching fills the grid in instead of snapping it on.
    private func presence(of road: DrawnRoad) -> Double {
        guard road.minZoom > 1 else { return 1 }
        let span = DrawnMap.sideStreetFullZoom - road.minZoom
        guard span > 0 else { return camera.zoom >= road.minZoom ? 1 : 0 }
        return min(max((camera.zoom - road.minZoom) / span, 0), 1)
    }

    // MARK: - The names

    /// Writes the picked-out neighbourhood's name across it, and hands back the paper it
    /// took so no street name is offered the same patch.
    ///
    /// The name is kept on the glass rather than pinned to the shape: tap the Upper West
    /// Side and then drag half of it off the edge and the name slides along the border
    /// instead of leaving with it. Knowing what you have picked matters more than knowing
    /// exactly where its middle is, and the highlight is already saying where.
    private func drawName(in context: inout GraphicsContext, size: CGSize) -> [CGRect] {
        guard let chosen else { return [] }

        let text = Text(chosen.name)
            .font(MapFont.label(size: palette.neighborhoodLabelSize))
        let ink = context.resolve(text.foregroundStyle(palette.highlightInk))
        let halo = context.resolve(text.foregroundStyle(palette.labelHalo))

        // The city's names for these are compound — "Upper East Side-Lenox Hill-
        // Roosevelt Island" is one neighbourhood — and several of them are wider than a
        // phone. Measuring inside the width it will be drawn in is what lets those wrap
        // onto a second line instead of running off both edges.
        let room = CGSize(width: max(size.width - 32, 40), height: 240)
        let measured = ink.measure(in: room)

        let wanted = camera.screenPoint(chosen.labelPoint, in: size)
        // Somewhere it fits: over the shape if the shape is on screen, shouldered back
        // onto the glass if it is not. The generous margin top and bottom keeps it out
        // from under the title and the zoom buttons.
        let point = CGPoint(
            x: clamp(wanted.x, measured.width / 2 + 16, size.width - measured.width / 2 - 16),
            y: clamp(wanted.y, measured.height / 2 + 64, size.height - measured.height / 2 - 72)
        )
        let box = CGRect(
            x: point.x - measured.width / 2,
            y: point.y - measured.height / 2,
            width: measured.width,
            height: measured.height
        )

        for offset in ManhattanMapView.haloOffsets {
            context.draw(halo, in: box.offsetBy(dx: offset.x, dy: offset.y))
        }
        context.draw(ink, in: box)

        return [box.insetBy(dx: -4, dy: -4)]
    }

    private func clamp(_ value: CGFloat, _ low: CGFloat, _ high: CGFloat) -> CGFloat {
        // On a narrow screen a long name can want more room than there is, and the two
        // ends of the travel cross over. Middle of the screen, then.
        guard low <= high else { return (low + high) / 2 }
        return min(max(value, low), high)
    }

    private func draw(
        labels: [DrawnLabel],
        in context: inout GraphicsContext,
        size: CGSize,
        claimed: [CGRect]
    ) {
        // A margin either side of the screen, so a name whose middle has just gone off
        // the edge does not blink out while part of it is still showing.
        let visible = CGRect(origin: .zero, size: size).insetBy(dx: -90, dy: -90)

        // The paper each name has already taken. Labels arrive most important first, so
        // the first to claim a patch keeps it and whatever would have been written across
        // it is left off — which is what stops "Central Park West" being written straight
        // through "96th Street" at the widest zoom.
        var taken: [CGRect] = claimed

        for label in labels where camera.zoom >= label.minZoom {
            let point = camera.screenPoint(label.position, in: size)
            guard visible.contains(point) else { continue }

            let text = Text(label.text)
                .font(MapFont.label(size: palette.labelSize(for: label.kind)))
            let ink = context.resolve(text.foregroundStyle(palette.label))

            let box = footprint(of: ink, at: point, angle: label.angle)
            if taken.contains(where: { $0.intersects(box) }) { continue }
            taken.append(box)

            // The paper showing through a name is what keeps it readable where it
            // crosses its own street: the same word laid down four times just off the
            // mark in the colour of the page, and then once more in ink.
            //
            // It is also four fifths of what a name costs to draw, and while a finger is
            // down that is four fifths of the work for something nobody is reading. So
            // the halo is left off mid-gesture and comes back the moment the map is let
            // go of — the names stay put either way, which is far less distracting than
            // having them disappear.
            let halo = interacting
                ? nil
                : context.resolve(text.foregroundStyle(palette.labelHalo))

            context.drawLayer { layer in
                layer.translateBy(x: point.x, y: point.y)
                layer.rotate(by: .radians(label.angle))
                if let halo {
                    for offset in ManhattanMapView.haloOffsets {
                        layer.draw(halo, at: offset, anchor: .center)
                    }
                }
                layer.draw(ink, at: .zero, anchor: .center)
            }
        }
    }

    private static let haloOffsets: [CGPoint] = [
        CGPoint(x: -1.4, y: 0), CGPoint(x: 1.4, y: 0),
        CGPoint(x: 0, y: -1.4), CGPoint(x: 0, y: 1.4),
    ]

    /// The upright box a rotated name sits in. A name written up an avenue is measured
    /// lying down and then stood up, which is what the sine and cosine are doing.
    private func footprint(
        of text: GraphicsContext.ResolvedText,
        at point: CGPoint,
        angle: Double
    ) -> CGRect {
        let measured = text.measure(in: CGSize(width: 600, height: 200))
        let across = abs(cos(angle))
        let down = abs(sin(angle))
        // A point of air either side, so two names never quite touch.
        let width = measured.width * across + measured.height * down + 2
        let height = measured.width * down + measured.height * across + 2
        return CGRect(
            x: point.x - width / 2,
            y: point.y - height / 2,
            width: width,
            height: height
        )
    }

}
