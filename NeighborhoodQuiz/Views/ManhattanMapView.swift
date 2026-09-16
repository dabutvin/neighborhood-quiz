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
    /// Whether a finger is on the map right now. Drawing is at its most expensive
    /// exactly when it has the least time, so a couple of things the eye cannot follow
    /// mid-drag are left until the map is still again.
    var interacting: Bool = false

    var body: some View {
        Canvas { context, size in
            draw(map: drawn, in: &context, size: size)
            draw(labels: drawn.labels, in: &context, size: size)
        }
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

        board.fill(map.park, with: .color(palette.park))
        board.stroke(
            map.parkEdge,
            with: .color(palette.parkInk),
            style: StrokeStyle(lineWidth: 1.4 / zoom, lineCap: .round, lineJoin: .round)
        )

        // Only the roads on the glass. A stroke that lands entirely off the edge costs
        // the same as one you can see, and at four times in almost all of them do.
        let onScreen = camera.visibleRect(in: size, margin: 8)

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

    private func draw(labels: [DrawnLabel], in context: inout GraphicsContext, size: CGSize) {
        // A margin either side of the screen, so a name whose middle has just gone off
        // the edge does not blink out while part of it is still showing.
        let visible = CGRect(origin: .zero, size: size).insetBy(dx: -90, dy: -90)

        // The paper each name has already taken. Labels arrive most important first, so
        // the first to claim a patch keeps it and whatever would have been written across
        // it is left off — which is what stops "Central Park West" being written straight
        // through "96th Street" at the widest zoom.
        var taken: [CGRect] = []

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
