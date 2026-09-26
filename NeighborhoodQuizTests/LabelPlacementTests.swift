import CoreGraphics
import XCTest
@testable import NeighborhoodQuiz

/// Keeping a street name on the glass: slid along its own street, never off it.
@MainActor
final class LabelPlacementTests: XCTestCase {
    private let screen = CGSize(width: 400, height: 800)

    /// The box a name of this size fills at this point, lying at this angle — the same
    /// sums the map uses, without the point of air.
    private func box(_ size: CGSize, at point: CGPoint, angle: Double) -> CGRect {
        let across = abs(cos(angle))
        let down = abs(sin(angle))
        let width = size.width * across + size.height * down
        let height = size.width * down + size.height * across
        return CGRect(x: point.x - width / 2, y: point.y - height / 2, width: width, height: height)
    }

    private func slid(_ point: CGPoint, _ size: CGSize, angle: Double) -> CGPoint {
        BoroughMapView.slid(
            point,
            box: box(size, at: point, angle: angle),
            angle: angle,
            reach: size.width,
            onto: screen
        )
    }

    /// "47th Street" with its middle forty points in from the left edge, a hundred and
    /// twenty long: forty-odd points of it were off the glass. It comes in by exactly
    /// that, and stays on its street's line.
    func testACrossStreetHangingOffTheSideComesInAlongItsStreet() {
        let name = CGSize(width: 120, height: 20)
        let moved = slid(CGPoint(x: 40, y: 300), name, angle: 0)

        XCTAssertEqual(moved.y, 300, "along the street, not off it")
        XCTAssertEqual(box(name, at: moved, angle: 0).minX, 4, accuracy: 0.001)
    }

    func testTheSameOnTheOtherSide() {
        let name = CGSize(width: 120, height: 20)
        let moved = slid(CGPoint(x: 380, y: 300), name, angle: 0)

        XCTAssertEqual(box(name, at: moved, angle: 0).maxX, 396, accuracy: 0.001)
    }

    /// An avenue's name runs up the screen, so it is its overhang at the bottom that
    /// moves it.
    func testAnAvenueHangingOffTheBottomComesUpAlongItsAvenue() {
        let name = CGSize(width: 120, height: 20)
        let upright = -Double.pi / 2
        let moved = slid(CGPoint(x: 200, y: 780), name, angle: upright)

        XCTAssertEqual(moved.x, 200, accuracy: 0.001)
        XCTAssertEqual(box(name, at: moved, angle: upright).maxY, 796, accuracy: 0.001)
    }

    /// A slanting street moves along its slant: in from the side, and down or up the
    /// screen by as much as the slant says.
    func testASlantingStreetMovesAlongItsSlant() {
        let name = CGSize(width: 100, height: 16)
        let angle = 0.5
        let start = CGPoint(x: 20, y: 400)
        let moved = slid(start, name, angle: angle)

        XCTAssertGreaterThan(moved.x, start.x)
        XCTAssertEqual((moved.y - start.y) / (moved.x - start.x), CGFloat(tan(angle)), accuracy: 0.001)
    }

    func testANameAlreadyOnTheGlassIsLeftAlone() {
        let point = CGPoint(x: 200, y: 400)
        XCTAssertEqual(slid(point, CGSize(width: 120, height: 20), angle: 0), point)
    }

    /// A cross street clipped at the top cannot be helped by moving it sideways.
    func testANameClippedAlongItsOwnLengthStays() {
        let point = CGPoint(x: 200, y: 2)
        XCTAssertEqual(slid(point, CGSize(width: 120, height: 20), angle: 0), point)
    }

    /// Further than its own length and it would be on some other part of the street,
    /// or off a curving one altogether.
    func testANameIsNeverMovedFurtherThanItsOwnLength() {
        let point = CGPoint(x: -150, y: 300)
        XCTAssertEqual(slid(point, CGSize(width: 120, height: 20), angle: 0), point)
    }
}
