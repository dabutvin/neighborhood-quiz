import CoreGraphics
import XCTest
@testable import NeighborhoodQuiz

final class MapCameraTests: XCTestCase {
    private let size = CGSize(width: 400, height: 800)

    func testAFreshCameraShowsTheDrawingAsItWasDrawn() {
        let camera = MapCamera()
        let point = CGPoint(x: 123, y: 456)
        XCTAssertEqual(camera.screenPoint(point, in: size), point)
    }

    func testZoomHoldsTheMiddleOfTheScreenStill() {
        var camera = MapCamera()
        let centre = CGPoint(x: size.width / 2, y: size.height / 2)
        camera.setZoom(4)
        XCTAssertEqual(camera.screenPoint(centre, in: size), centre)
    }

    func testZoomAfterPanningKeepsLookingAtTheSameThing() {
        var camera = MapCamera()
        camera.pan = CGSize(width: -120, height: 260)

        // Whatever was in the middle of the screen before must still be there after.
        let centre = CGPoint(x: size.width / 2, y: size.height / 2)
        let looking = modelPoint(at: centre, camera: camera)
        camera.setZoom(3.5)
        let stillLooking = modelPoint(at: centre, camera: camera)

        XCTAssertEqual(Double(looking.x), Double(stillLooking.x), accuracy: 1e-9)
        XCTAssertEqual(Double(looking.y), Double(stillLooking.y), accuracy: 1e-9)
    }

    func testZoomIsClampedAtBothEnds() {
        var camera = MapCamera()
        camera.setZoom(0.1)
        XCTAssertEqual(camera.zoom, MapCamera.range.lowerBound)

        camera.setZoom(1_000)
        XCTAssertEqual(camera.zoom, MapCamera.range.upperBound)
    }

    func testCentringPutsThePointInTheMiddle() {
        let target = CGPoint(x: 90, y: 640)
        let camera = MapCamera.centred(on: target, zoom: 4.2, in: size)
        let landed = camera.screenPoint(target, in: size)

        XCTAssertEqual(Double(landed.x), Double(size.width) / 2, accuracy: 1e-9)
        XCTAssertEqual(Double(landed.y), Double(size.height) / 2, accuracy: 1e-9)
    }

    func testAFreshCameraSeesTheWholeDrawing() {
        let visible = MapCamera().visibleRect(in: size)
        XCTAssertEqual(Double(visible.minX), 0, accuracy: 1e-9)
        XCTAssertEqual(Double(visible.minY), 0, accuracy: 1e-9)
        XCTAssertEqual(Double(visible.width), Double(size.width), accuracy: 1e-9)
        XCTAssertEqual(Double(visible.height), Double(size.height), accuracy: 1e-9)
    }

    func testComingInShowsLessOfTheDrawing() {
        var camera = MapCamera()
        camera.setZoom(4)
        let visible = camera.visibleRect(in: size)

        // Four times in is a quarter of the width and a quarter of the height, around
        // the middle — a twentieth of the drawing, which is the whole reason to cull.
        XCTAssertEqual(Double(visible.width), Double(size.width) / 4, accuracy: 1e-9)
        XCTAssertEqual(Double(visible.height), Double(size.height) / 4, accuracy: 1e-9)
        XCTAssertEqual(Double(visible.midX), Double(size.width) / 2, accuracy: 1e-9)
        XCTAssertEqual(Double(visible.midY), Double(size.height) / 2, accuracy: 1e-9)
    }

    func testTheVisibleRectFollowsThePan() {
        var camera = MapCamera(zoom: 2, pan: .zero)
        let before = camera.visibleRect(in: size)
        camera.pan = CGSize(width: -100, height: 0)
        let after = camera.visibleRect(in: size)

        // Dragging the map left shows what was off its right edge.
        XCTAssertEqual(Double(after.minX - before.minX), 50, accuracy: 1e-9)
        XCTAssertEqual(Double(after.width), Double(before.width), accuracy: 1e-9)
    }

    func testWhatIsVisibleIsExactlyWhatLandsOnTheGlass() {
        // The rect and `screenPoint` are inverses, so anything inside it draws inside
        // the screen and anything outside it does not. That equivalence is what makes
        // culling on the rect safe.
        let camera = MapCamera(zoom: 3.5, pan: CGSize(width: -40, height: 90))
        let visible = camera.visibleRect(in: size)
        let screen = CGRect(origin: .zero, size: size)

        for corner in [
            CGPoint(x: visible.minX, y: visible.minY),
            CGPoint(x: visible.maxX, y: visible.maxY),
            CGPoint(x: visible.midX, y: visible.midY),
        ] {
            let landed = camera.screenPoint(corner, in: size)
            XCTAssertTrue(
                screen.insetBy(dx: -0.001, dy: -0.001).contains(landed),
                "\(corner) should land on the glass, landed at \(landed)"
            )
        }

        let outside = CGPoint(x: visible.minX - 20, y: visible.midY)
        XCTAssertFalse(screen.contains(camera.screenPoint(outside, in: size)))
    }

    func testTheIslandCannotBeShovedOffTheGlass() {
        var camera = MapCamera()
        camera.pan = CGSize(width: 99_999, height: -99_999)
        camera.clampPan(in: size)

        XCTAssertLessThanOrEqual(camera.pan.width, size.width)
        XCTAssertGreaterThanOrEqual(camera.pan.height, -size.height)
    }

    func testThereIsMoreRoomToRoamTheFurtherInYouAre() {
        var close = MapCamera(zoom: 8, pan: CGSize(width: 99_999, height: 0))
        var wide = MapCamera(zoom: 1, pan: CGSize(width: 99_999, height: 0))
        close.clampPan(in: size)
        wide.clampPan(in: size)
        XCTAssertGreaterThan(close.pan.width, wide.pan.width)
    }

    /// The inverse of `screenPoint`: which part of the drawing is under a given spot
    /// on the glass. Only the tests need it, so it lives here.
    private func modelPoint(at screen: CGPoint, camera: MapCamera) -> CGPoint {
        let centre = CGPoint(x: size.width / 2, y: size.height / 2)
        return CGPoint(
            x: (screen.x - centre.x - camera.pan.width) / camera.zoom + centre.x,
            y: (screen.y - centre.y - camera.pan.height) / camera.zoom + centre.y
        )
    }
}
