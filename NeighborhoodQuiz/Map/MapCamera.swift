import CoreGraphics
import Foundation

/// Where the map is being looked at from: how far in, and how far it has been pushed
/// about. The drawing itself never changes — this does.
///
/// Zoom is anchored on the middle of the screen, which is what makes a pair of buttons
/// feel right: whatever you have centred stays centred as you come in on it.
struct MapCamera: Equatable {
    /// 1 is the whole island on screen. The far end is about a block across the glass.
    static let range: ClosedRange<Double> = 1...14

    var zoom: Double = 1
    var pan: CGSize = .zero
    /// How far in this camera may go. Fourteen for one borough; further for the whole
    /// city, which starts three or four times further out and has to reach the same
    /// streets. Set by the board from the drawing it is looking at.
    var ceiling: Double = MapCamera.range.upperBound

    /// Where a point of the drawing lands on the glass.
    func screenPoint(_ point: CGPoint, in size: CGSize) -> CGPoint {
        let centre = MapCamera.centre(of: size)
        return CGPoint(
            x: (Double(point.x) - centre.x) * zoom + centre.x + Double(pan.width),
            y: (Double(point.y) - centre.y) * zoom + centre.y + Double(pan.height)
        )
    }

    /// Come in or pull back, keeping whatever is in the middle of the screen in the
    /// middle of the screen. Panning is measured in screen points, so it has to grow
    /// and shrink with the zoom it was measured against.
    mutating func setZoom(_ newZoom: Double) {
        guard zoom > 0 else { return }
        let clamped = min(max(newZoom, MapCamera.range.lowerBound), max(ceiling, MapCamera.range.lowerBound))
        let ratio = clamped / zoom
        pan = CGSize(width: Double(pan.width) * ratio, height: Double(pan.height) * ratio)
        zoom = clamped
    }

    /// How far the map may be pushed in each direction before it is off its leash.
    /// There is more room to roam the further in you are, since there is more drawing
    /// to roam over.
    func slack(in size: CGSize) -> CGSize {
        CGSize(
            width: Double(size.width) * max(zoom - 1, 0) / 2 + Double(size.width) / 3,
            height: Double(size.height) * max(zoom - 1, 0) / 2 + Double(size.height) / 3
        )
    }

    /// Stop the island being pushed off the edge of the glass altogether.
    mutating func clampPan(in size: CGSize) {
        let slack = slack(in: size)
        pan = CGSize(
            width: min(max(Double(pan.width), -Double(slack.width)), Double(slack.width)),
            height: min(max(Double(pan.height), -Double(slack.height)), Double(slack.height))
        )
    }

    /// How far past the leash a pull may stretch before it is all resistance and no
    /// movement. A quarter of the glass: enough to feel like give, not so much that the
    /// island can be dragged out of sight.
    static func give(in size: CGSize) -> CGSize {
        CGSize(width: Double(size.width) / 4, height: Double(size.height) / 4)
    }

    /// The same pan with springy edges instead of solid ones.
    ///
    /// Clamping mid-drag is what made a pan feel like it hit something: at the limit the
    /// map simply stopped answering the thumb, while the thumb kept going. This keeps
    /// the two together — less and less of the pull gets through, but never none of it.
    mutating func resistPan(in size: CGSize) {
        let slack = slack(in: size)
        let give = MapCamera.give(in: size)
        pan = CGSize(
            width: MapCamera.resisted(Double(pan.width), limit: Double(slack.width), give: Double(give.width)),
            height: MapCamera.resisted(Double(pan.height), limit: Double(slack.height), give: Double(give.height))
        )
    }

    static func resisted(_ value: Double, limit: Double, give: Double) -> Double {
        if value > limit { return limit + stretch(value - limit, give: give) }
        if value < -limit { return -limit - stretch(-value - limit, give: give) }
        return value
    }

    /// UIKit's own curve for pulling past an edge. The first little way answers the
    /// finger at a bit over half speed and it stiffens from there, approaching `give`
    /// however hard you pull — so there is always somewhere further to go and never
    /// anywhere much further.
    private static func stretch(_ past: Double, give: Double) -> Double {
        guard past > 0, give > 0 else { return max(past, 0) }
        return (1 - 1 / (past * 0.55 / give + 1)) * give
    }

    /// Which part of the drawing is under a given spot on the glass — `screenPoint`
    /// run backwards. This is what turns a tap into a place on the map.
    func modelPoint(_ point: CGPoint, in size: CGSize) -> CGPoint {
        let centre = MapCamera.centre(of: size)
        guard zoom > 0 else { return point }
        return CGPoint(
            x: (Double(point.x) - centre.x - Double(pan.width)) / zoom + centre.x,
            y: (Double(point.y) - centre.y - Double(pan.height)) / zoom + centre.y
        )
    }

    /// The piece of the drawing that is on the glass, in the drawing's own coordinates.
    ///
    /// This is `screenPoint` run backwards, and it is what lets the drawing skip the
    /// nine tenths of itself that is off the edge: at four times in, a phone is showing
    /// about a twentieth of the island, and stroking the other nineteen twentieths every
    /// frame is most of what made a drag feel heavy.
    func visibleRect(in size: CGSize, margin: Double = 0) -> CGRect {
        let topLeft = modelPoint(.zero, in: size)
        let bottomRight = modelPoint(CGPoint(x: size.width, y: size.height), in: size)
        return CGRect(
            x: Double(topLeft.x) - margin,
            y: Double(topLeft.y) - margin,
            width: Double(bottomRight.x - topLeft.x) + margin * 2,
            height: Double(bottomRight.y - topLeft.y) + margin * 2
        )
    }

    /// A camera looking straight at one point of the drawing.
    static func centred(on point: CGPoint, zoom: Double, in size: CGSize) -> MapCamera {
        let centre = MapCamera.centre(of: size)
        return MapCamera(
            zoom: zoom,
            pan: CGSize(
                width: -(Double(point.x) - centre.x) * zoom,
                height: -(Double(point.y) - centre.y) * zoom
            )
        )
    }

    /// A camera holding a piece of the drawing comfortably on the glass, with a little
    /// of what is round it left showing so the piece reads as part of something.
    static func framing(
        _ rect: CGRect,
        in size: CGSize,
        fill: Double = 0.62,
        ceiling: Double = MapCamera.range.upperBound
    ) -> MapCamera {
        guard rect.width > 0, rect.height > 0, size.width > 0, size.height > 0 else {
            return MapCamera()
        }
        let wanted = min(
            Double(size.width) / Double(rect.width),
            Double(size.height) / Double(rect.height)
        ) * fill
        let zoom = min(max(wanted, range.lowerBound), ceiling)
        var camera = centred(on: CGPoint(x: rect.midX, y: rect.midY), zoom: zoom, in: size)
        camera.ceiling = ceiling
        return camera
    }

    private static func centre(of size: CGSize) -> (x: Double, y: Double) {
        (x: Double(size.width) / 2, y: Double(size.height) / 2)
    }
}
