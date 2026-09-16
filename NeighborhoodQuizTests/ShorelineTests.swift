import CoreGraphics
import XCTest
@testable import NeighborhoodQuiz

final class ShorelineTests: XCTestCase {
    private let square = [
        CGPoint(x: 0, y: 0),
        CGPoint(x: 100, y: 0),
        CGPoint(x: 100, y: 100),
        CGPoint(x: 0, y: 100),
    ]

    /// A block with a notch cut out of the top, so a line drawn across it comes back
    /// in two pieces — which is what a cross street does either side of Central Park.
    private let notched = [
        CGPoint(x: 0, y: 0),
        CGPoint(x: 100, y: 0),
        CGPoint(x: 100, y: 100),
        CGPoint(x: 70, y: 100),
        CGPoint(x: 70, y: 40),
        CGPoint(x: 30, y: 40),
        CGPoint(x: 30, y: 100),
        CGPoint(x: 0, y: 100),
    ]

    func testContains() {
        XCTAssertTrue(Shoreline.contains(square, CGPoint(x: 50, y: 50)))
        XCTAssertFalse(Shoreline.contains(square, CGPoint(x: -1, y: 50)))
        XCTAssertFalse(Shoreline.contains(square, CGPoint(x: 50, y: 101)))
        XCTAssertTrue(Shoreline.contains(notched, CGPoint(x: 10, y: 70)))
        XCTAssertFalse(Shoreline.contains(notched, CGPoint(x: 50, y: 70)), "The notch is outside")
    }

    func testALineRightAcrossComesBackCutToTheEdges() {
        let runs = Shoreline.clip(
            [CGPoint(x: -50, y: 50), CGPoint(x: 150, y: 50)],
            to: square
        )
        XCTAssertEqual(runs.count, 1)
        XCTAssertEqual(Double(runs[0].first?.x ?? -1), 0, accuracy: 1e-6)
        XCTAssertEqual(Double(runs[0].last?.x ?? -1), 100, accuracy: 1e-6)
    }

    func testALineStoppingInsideKeepsItsOwnEnd() {
        let runs = Shoreline.clip(
            [CGPoint(x: -50, y: 50), CGPoint(x: 40, y: 50)],
            to: square
        )
        XCTAssertEqual(runs.count, 1)
        XCTAssertEqual(Double(runs[0].first?.x ?? -1), 0, accuracy: 1e-6)
        XCTAssertEqual(Double(runs[0].last?.x ?? -1), 40, accuracy: 1e-6)
    }

    func testALineWhollyOutsideComesBackWithNothing() {
        XCTAssertTrue(Shoreline.clip(
            [CGPoint(x: -50, y: 200), CGPoint(x: 150, y: 200)],
            to: square
        ).isEmpty)
    }

    func testALineAcrossTheNotchComesBackInTwoPieces() {
        let runs = Shoreline.clip(
            [CGPoint(x: -10, y: 70), CGPoint(x: 110, y: 70)],
            to: notched
        )
        XCTAssertEqual(runs.count, 2)
        XCTAssertEqual(Double(runs[0].first?.x ?? -1), 0, accuracy: 1e-6)
        XCTAssertEqual(Double(runs[0].last?.x ?? -1), 30, accuracy: 1e-6)
        XCTAssertEqual(Double(runs[1].first?.x ?? -1), 70, accuracy: 1e-6)
        XCTAssertEqual(Double(runs[1].last?.x ?? -1), 100, accuracy: 1e-6)
    }

    func testABentLineInsideStaysOnePiece() {
        let runs = Shoreline.clip(
            [CGPoint(x: 10, y: 10), CGPoint(x: 50, y: 20), CGPoint(x: 90, y: 10)],
            to: square
        )
        XCTAssertEqual(runs.count, 1)
        XCTAssertEqual(runs[0].count, 3)
    }

    func testCrossingFindsWhereTwoSegmentsMeetAndOnlyWhenTheyDo() {
        let hit = Shoreline.crossing(
            CGPoint(x: 0, y: 0), CGPoint(x: 10, y: 0),
            CGPoint(x: 4, y: -5), CGPoint(x: 4, y: 5)
        )
        XCTAssertEqual(hit ?? -1, 0.4, accuracy: 1e-9)

        XCTAssertNil(Shoreline.crossing(
            CGPoint(x: 0, y: 0), CGPoint(x: 10, y: 0),
            CGPoint(x: 4, y: 5), CGPoint(x: 4, y: 15)
        ), "The second segment stops short")

        XCTAssertNil(Shoreline.crossing(
            CGPoint(x: 0, y: 0), CGPoint(x: 10, y: 0),
            CGPoint(x: 0, y: 3), CGPoint(x: 10, y: 3)
        ), "Parallel lines never meet")
    }

    func testLengthAndMidpointFollowTheLineRatherThanTheIndex() {
        let bent = [CGPoint(x: 0, y: 0), CGPoint(x: 90, y: 0), CGPoint(x: 100, y: 0)]
        XCTAssertEqual(Shoreline.length(of: bent), 100, accuracy: 1e-9)

        let middle = Shoreline.midpoint(of: bent)
        XCTAssertEqual(Double(middle.x), 50, accuracy: 1e-6)
        XCTAssertEqual(Double(middle.y), 0, accuracy: 1e-6)
    }

    func testHeadingNeverReadsUpsideDown() {
        let rightwards = Shoreline.heading(
            of: [CGPoint(x: 0, y: 0), CGPoint(x: 100, y: 0)],
            near: CGPoint(x: 50, y: 0)
        )
        XCTAssertEqual(rightwards, 0, accuracy: 1e-9)

        // A street drawn east-to-west is still written left-to-right.
        let leftwards = Shoreline.heading(
            of: [CGPoint(x: 100, y: 0), CGPoint(x: 0, y: 0)],
            near: CGPoint(x: 50, y: 0)
        )
        XCTAssertEqual(leftwards, 0, accuracy: 1e-9)

        // An avenue reads bottom-to-top whichever way it was drawn.
        let up = Shoreline.heading(
            of: [CGPoint(x: 0, y: 100), CGPoint(x: 0, y: 0)],
            near: CGPoint(x: 0, y: 50)
        )
        let down = Shoreline.heading(
            of: [CGPoint(x: 0, y: 0), CGPoint(x: 0, y: 100)],
            near: CGPoint(x: 0, y: 50)
        )
        XCTAssertEqual(up, -.pi / 2, accuracy: 1e-9)
        XCTAssertEqual(down, -.pi / 2, accuracy: 1e-9)
    }

    func testALineAHairOffVerticalIsStillWrittenUpwards() {
        // The case that broke: the avenues come out of the projection a hundredth of a
        // degree off vertical, which is enough to land on the wrong side of a fold that
        // sits exactly on the quarter turn — and Fifth Avenue then read downwards while
        // Park Avenue beside it read up.
        let leaningRight = Shoreline.heading(
            of: [CGPoint(x: 0, y: 0), CGPoint(x: 0.06, y: 500)],
            near: CGPoint(x: 0.03, y: 250)
        )
        let leaningLeft = Shoreline.heading(
            of: [CGPoint(x: 0, y: 0), CGPoint(x: -0.06, y: 500)],
            near: CGPoint(x: -0.03, y: 250)
        )
        XCTAssertEqual(leaningRight, -.pi / 2, accuracy: 0.01)
        XCTAssertEqual(leaningLeft, -.pi / 2, accuracy: 0.01)
    }

    func testAGenuineDiagonalKeepsItsLean() {
        // The slack must not swallow a real tilt: eighty-six degrees is Broadway-ish,
        // not vertical, and it stays where it is.
        let steep = Shoreline.heading(
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
        XCTAssertEqual(Shoreline.heading(of: bent, near: CGPoint(x: 10, y: 0)), 0, accuracy: 1e-9)
        XCTAssertEqual(
            Shoreline.heading(of: bent, near: CGPoint(x: 100, y: -90)),
            -.pi / 2,
            accuracy: 1e-9
        )
    }
}
