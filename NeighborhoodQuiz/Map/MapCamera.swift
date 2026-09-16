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
        let clamped = min(max(newZoom, MapCamera.range.lowerBound), MapCamera.range.upperBound)
        let ratio = clamped / zoom
        pan = CGSize(width: Double(pan.width) * ratio, height: Double(pan.height) * ratio)
        zoom = clamped
    }

    /// Stop the island being pushed off the edge of the glass altogether. There is more
    /// room to roam the further in you are, since there is more drawing to roam over.
    mutating func clampPan(in size: CGSize) {
        let slackX = Double(size.width) * max(zoom - 1, 0) / 2 + Double(size.width) / 3
        let slackY = Double(size.height) * max(zoom - 1, 0) / 2 + Double(size.height) / 3
        pan = CGSize(
            width: min(max(Double(pan.width), -slackX), slackX),
            height: min(max(Double(pan.height), -slackY), slackY)
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

    private static func centre(of size: CGSize) -> (x: Double, y: Double) {
        (x: Double(size.width) / 2, y: Double(size.height) / 2)
    }
}
