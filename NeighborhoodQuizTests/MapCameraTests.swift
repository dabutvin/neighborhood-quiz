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
        let looking = camera.modelPoint(centre, in: size)
        camera.setZoom(3.5)
        let stillLooking = camera.modelPoint(centre, in: size)

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

    // MARK: - Turning a tap into a place

    func testAPointOnTheGlassAndAPointOnTheDrawingAgree() {
        let camera = MapCamera(zoom: 5.5, pan: CGSize(width: -210, height: 340))
        for point in [CGPoint(x: 0, y: 0), CGPoint(x: 400, y: 800), CGPoint(x: 137, y: 611)] {
            let there = camera.modelPoint(point, in: size)
            let back = camera.screenPoint(there, in: size)
            XCTAssertEqual(Double(back.x), Double(point.x), accuracy: 1e-9)
            XCTAssertEqual(Double(back.y), Double(point.y), accuracy: 1e-9)
        }
    }

    func testTheWholeScreenIsTheWholeDrawingBeforeAnybodyTouchesIt() {
        let visible = MapCamera().visibleRect(in: size)
        XCTAssertEqual(visible, CGRect(origin: .zero, size: size))
    }

    // MARK: - Framing something

    func testFramingPutsAShapeInTheMiddleOfTheGlass() {
        let shape = CGRect(x: 60, y: 300, width: 80, height: 120)
        let camera = MapCamera.framing(shape, in: size)
        let middle = camera.screenPoint(CGPoint(x: shape.midX, y: shape.midY), in: size)

        XCTAssertEqual(Double(middle.x), Double(size.width) / 2, accuracy: 1e-9)
        XCTAssertEqual(Double(middle.y), Double(size.height) / 2, accuracy: 1e-9)
    }

    func testFramingLeavesSomethingShowingRoundTheEdges() {
        let shape = CGRect(x: 60, y: 300, width: 80, height: 120)
        let camera = MapCamera.framing(shape, in: size)
        let onGlass = CGRect(origin: .zero, size: size)

        let corners = [
            CGPoint(x: shape.minX, y: shape.minY), CGPoint(x: shape.maxX, y: shape.minY),
            CGPoint(x: shape.minX, y: shape.maxY), CGPoint(x: shape.maxX, y: shape.maxY),
        ].map { camera.screenPoint($0, in: size) }

        for corner in corners {
            XCTAssertTrue(onGlass.contains(corner), "\(corner) is framed off the screen")
        }
        // And it is not lost in the middle of it either.
        let framed = corners.reduce(CGRect.null) { $0.union(CGRect(origin: $1, size: .zero)) }
        XCTAssertGreaterThan(framed.height, Double(size.height) * 0.4)
    }

    func testFramingWillNotPullInFurtherThanTheMapGoes() {
        // A block-sized shape would want a hundred times, and the camera only has
        // fourteen.
        let camera = MapCamera.framing(CGRect(x: 200, y: 400, width: 1, height: 1), in: size)
        XCTAssertEqual(camera.zoom, MapCamera.range.upperBound)
    }

    func testFramingNothingIsNotACrash() {
        XCTAssertEqual(MapCamera.framing(.zero, in: size), MapCamera())
        XCTAssertEqual(MapCamera.framing(CGRect(x: 0, y: 0, width: 10, height: 10), in: .zero), MapCamera())
    }
}
