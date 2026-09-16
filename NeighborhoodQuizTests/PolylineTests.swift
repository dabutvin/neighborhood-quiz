import CoreGraphics
import XCTest
@testable import NeighborhoodQuiz

final class PolylineTests: XCTestCase {
    func testLengthAndMidpointFollowTheLineRatherThanTheIndex() {
        let bent = [CGPoint(x: 0, y: 0), CGPoint(x: 90, y: 0), CGPoint(x: 100, y: 0)]
        XCTAssertEqual(Polyline.length(of: bent), 100, accuracy: 1e-9)

        let middle = Polyline.midpoint(of: bent)
        XCTAssertEqual(Double(middle.x), 50, accuracy: 1e-6)
        XCTAssertEqual(Double(middle.y), 0, accuracy: 1e-6)
    }

    func testAShortRunStillHasAMiddle() {
        XCTAssertEqual(Polyline.length(of: []), 0)
        XCTAssertEqual(Polyline.midpoint(of: []), .zero)
        XCTAssertEqual(Polyline.midpoint(of: [CGPoint(x: 3, y: 4)]), CGPoint(x: 3, y: 4))
    }

    func testHeadingNeverReadsUpsideDown() {
        let rightwards = Polyline.heading(
            of: [CGPoint(x: 0, y: 0), CGPoint(x: 100, y: 0)],
            near: CGPoint(x: 50, y: 0)
        )
        XCTAssertEqual(rightwards, 0, accuracy: 1e-9)

        // A street drawn east-to-west is still written left-to-right.
        let leftwards = Polyline.heading(
            of: [CGPoint(x: 100, y: 0), CGPoint(x: 0, y: 0)],
            near: CGPoint(x: 50, y: 0)
        )
        XCTAssertEqual(leftwards, 0, accuracy: 1e-9)

        // An avenue reads bottom-to-top whichever way it was drawn.
        let up = Polyline.heading(
            of: [CGPoint(x: 0, y: 100), CGPoint(x: 0, y: 0)],
            near: CGPoint(x: 0, y: 50)
        )
        let down = Polyline.heading(
            of: [CGPoint(x: 0, y: 0), CGPoint(x: 0, y: 100)],
            near: CGPoint(x: 0, y: 50)
        )
        XCTAssertEqual(up, -.pi / 2, accuracy: 1e-9)
        XCTAssertEqual(down, -.pi / 2, accuracy: 1e-9)
    }

    func testALineAHairOffVerticalIsStillWrittenUpwards() {
        // The avenues come out of the projection a hundredth of a degree off vertical,
        // which is enough to land on the wrong side of a fold that sits exactly on the
        // quarter turn — and Fifth Avenue then read downwards while Park Avenue beside
        // it read up.
        let leaningRight = Polyline.heading(
            of: [CGPoint(x: 0, y: 0), CGPoint(x: 0.06, y: 500)],
            near: CGPoint(x: 0.03, y: 250)
        )
        let leaningLeft = Polyline.heading(
            of: [CGPoint(x: 0, y: 0), CGPoint(x: -0.06, y: 500)],
            near: CGPoint(x: -0.03, y: 250)
        )
        XCTAssertEqual(leaningRight, -.pi / 2, accuracy: 0.01)
        XCTAssertEqual(leaningLeft, -.pi / 2, accuracy: 0.01)
    }

    func testAGenuineDiagonalKeepsItsLean() {
        // The slack must not swallow a real tilt: eighty-six degrees is Broadway-ish,
        // not vertical, and it stays where it is.
        let steep = Polyline.heading(
            of: [CGPoint(x: 0, y: 0), CGPoint(x: 7, y: 100)],
            near: CGPoint(x: 3.5, y: 50)
        )
        XCTAssertEqual(steep, 1.50091, accuracy: 0.001)
    }

    func testHeadingPicksTheNearestPartOfABentLine() {
        // Flat on the left, steep on the right.
        let bent = [
            CGPoint(x: 0, y: 0),
            CGPoint(x: 100, y: 0),
            CGPoint(x: 100, y: -100),
        ]
        XCTAssertEqual(Polyline.heading(of: bent, near: CGPoint(x: 10, y: 0)), 0, accuracy: 1e-9)
        XCTAssertEqual(
            Polyline.heading(of: bent, near: CGPoint(x: 100, y: -90)),
            -.pi / 2,
            accuracy: 1e-9
        )
    }

    func testCrossingFindsWhereTwoSegmentsMeetAndOnlyWhenTheyDo() {
        let hit = Polyline.crossing(
            CGPoint(x: 0, y: 0), CGPoint(x: 10, y: 0),
            CGPoint(x: 4, y: -5), CGPoint(x: 4, y: 5)
        )
        XCTAssertEqual(hit ?? -1, 0.4, accuracy: 1e-9)

        XCTAssertNil(Polyline.crossing(
            CGPoint(x: 0, y: 0), CGPoint(x: 10, y: 0),
            CGPoint(x: 4, y: 5), CGPoint(x: 4, y: 15)
        ), "The second segment stops short")

        XCTAssertNil(Polyline.crossing(
            CGPoint(x: 0, y: 0), CGPoint(x: 10, y: 0),
            CGPoint(x: 0, y: 3), CGPoint(x: 10, y: 3)
        ), "Parallel lines never meet")
    }
}
