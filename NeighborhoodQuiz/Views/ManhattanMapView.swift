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

        for road in map.roads {
            board.stroke(
                road.path,
                with: .color(palette.colour(for: road.kind)),
                style: StrokeStyle(
                    lineWidth: CGFloat(palette.weight(for: road.kind)) / zoom,
                    lineCap: .round,
                    lineJoin: .round
                )
            )
        }
    }

    // MARK: - The names

    private func draw(labels: [DrawnLabel], in context: inout GraphicsContext, size: CGSize) {
        // A margin either side of the screen, so a name whose middle has just gone off
        // the edge does not blink out while part of it is still showing.
        let visible = CGRect(origin: .zero, size: size).insetBy(dx: -90, dy: -90)

        for label in labels where camera.zoom >= label.minZoom {
            let point = camera.screenPoint(label.position, in: size)
            guard visible.contains(point) else { continue }

            let text = Text(label.text)
                .font(MapFont.label(size: palette.labelSize(for: label.kind)))
            let ink = context.resolve(text.foregroundStyle(palette.label))
            let halo = context.resolve(text.foregroundStyle(palette.labelHalo))

            context.drawLayer { layer in
                layer.translateBy(x: point.x, y: point.y)
                layer.rotate(by: .radians(label.angle))

                // The paper showing through the name is what keeps it readable where it
                // crosses its own street: the same word laid down four times just off
                // the mark in the colour of the page, and then once more in ink.
                for offset in ManhattanMapView.haloOffsets {
                    layer.draw(halo, at: offset, anchor: .center)
                }
                layer.draw(ink, at: .zero, anchor: .center)
            }
        }
    }

    private static let haloOffsets: [CGPoint] = [
        CGPoint(x: -1.4, y: 0), CGPoint(x: 1.4, y: 0),
        CGPoint(x: 0, y: -1.4), CGPoint(x: 0, y: 1.4),
    ]
}
