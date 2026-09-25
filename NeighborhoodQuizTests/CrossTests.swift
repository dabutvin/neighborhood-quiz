import SwiftUI
import XCTest
@testable import NeighborhoodQuiz

/// The mark that says a guess was wrong.
///
/// The wash on its own was too quiet to be an answer — you said a place, you were
/// wrong, and the map went very slightly grey there. Two strokes through the middle
/// say *no* in a way a change of shade does not.
///
/// The tolerances here come from the pen rather than from taste: a stroke's ends stray
/// by at most `roughness × reach`, which is 0.9 × 1.5, and the bow perpendicular to a
/// line this short is smaller again. Three points covers both with room to spare, and
/// still catches the mistake worth catching, which is a clamp that stopped clamping.
@MainActor
final class CrossTests: XCTestCase {
    private let slop = 3.0

    private func extent(_ path: Path) -> (centre: CGPoint, half: Double) {
        let box = path.boundingRect
        return (CGPoint(x: box.midX, y: box.midY), Double(max(box.width, box.height)) / 2)
    }

    func testACrossIsDrawnWhereItIsPut() {
        let centre = CGPoint(x: 140, y: 260)
        let cross = DrawnMap.cross(
            at: centre,
            across: CGRect(x: 100, y: 220, width: 80, height: 80),
            seed: 7
        )
        XCTAssertFalse(cross.isEmpty)

        let (middle, _) = extent(cross)
        XCTAssertEqual(Double(middle.x), Double(centre.x), accuracy: slop)
        XCTAssertEqual(Double(middle.y), Double(centre.y), accuracy: slop)
    }

    /// The smallest neighbourhoods are a few points across. Sized purely in proportion
    /// they would get a mark nobody could see, which is the same as no mark at all.
    func testASmallPlaceStillGetsAMarkYouCanSee() {
        let cross = DrawnMap.cross(
            at: .zero,
            across: CGRect(x: -6, y: -6, width: 12, height: 12),
            seed: 3
        )
        XCTAssertGreaterThan(extent(cross).half, 7 - slop)
    }

    /// And the largest do not get one you can see from the next borough.
    func testABigPlaceDoesNotGetAHugeCross() {
        let cross = DrawnMap.cross(
            at: .zero,
            across: CGRect(x: -300, y: -250, width: 600, height: 500),
            seed: 3
        )
        XCTAssertLessThan(extent(cross).half, 26 + slop)
    }

    /// Between the two limits it follows the place, so the mark belongs to the shape it
    /// is on rather than being stamped over it.
    func testBetweenTheLimitsItFollowsThePlace() {
        let small = extent(DrawnMap.cross(
            at: .zero, across: CGRect(x: -20, y: -20, width: 40, height: 40), seed: 5
        )).half
        let large = extent(DrawnMap.cross(
            at: .zero, across: CGRect(x: -50, y: -50, width: 100, height: 100), seed: 5
        )).half
        XCTAssertGreaterThan(large, small)
        XCTAssertEqual(small, 8.8, accuracy: slop)
        XCTAssertEqual(large, 22, accuracy: slop)
    }

    /// The narrow dimension decides it, so a long thin neighbourhood gets a cross that
    /// fits across it rather than one that hangs over both sides.
    func testTheNarrowWayRoundIsWhatDecides() {
        let wide = extent(DrawnMap.cross(
            at: .zero, across: CGRect(x: -150, y: -20, width: 300, height: 40), seed: 5
        )).half
        XCTAssertEqual(wide, 8.8, accuracy: slop)
    }

    /// Same seed, same wobble. This is the whole reason the cross is worked out when the
    /// map is built instead of when it is drawn: a wobble computed afresh every frame
    /// would crawl about under the finger.
    func testTheSameSeedDrawsTheSameCross() {
        let box = CGRect(x: 0, y: 0, width: 90, height: 90)
        let once = DrawnMap.cross(at: CGPoint(x: 45, y: 45), across: box, seed: 99)
        let again = DrawnMap.cross(at: CGPoint(x: 45, y: 45), across: box, seed: 99)
        XCTAssertEqual(once, again)
    }

    /// Different seeds, different wobble — forty identical crosses would read as a
    /// stamp rather than as somebody crossing places off.
    func testDifferentSeedsWobbleDifferently() {
        let box = CGRect(x: 0, y: 0, width: 90, height: 90)
        let one = DrawnMap.cross(at: CGPoint(x: 45, y: 45), across: box, seed: 1)
        let two = DrawnMap.cross(at: CGPoint(x: 45, y: 45), across: box, seed: 2)
        XCTAssertNotEqual(one, two)
    }

    /// And on the real map: every neighbourhood has one, centred where its name goes,
    /// which is a point already known to be inside the shape.
    func testEveryNeighbourhoodOnTheMapHasOne() {
        let map = DrawnMap.build(borough: .manhattan, size: CGSize(width: 393, height: 852))
        XCTAssertFalse(map.neighborhoods.isEmpty)

        for area in map.neighborhoods {
            XCTAssertFalse(area.cross.isEmpty, "\(area.name) has no cross")
            let (middle, half) = extent(area.cross)
            XCTAssertEqual(Double(middle.x), Double(area.labelPoint.x), accuracy: slop, area.name)
            XCTAssertEqual(Double(middle.y), Double(area.labelPoint.y), accuracy: slop, area.name)
            XCTAssertGreaterThan(half, 7 - slop, area.name)
            XCTAssertLessThan(half, 26 + slop, area.name)
        }
    }
}
