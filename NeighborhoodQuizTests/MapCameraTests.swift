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
