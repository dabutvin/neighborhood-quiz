import CoreGraphics
import SwiftUI
import XCTest
@testable import NeighborhoodQuiz

/// The geometry a tap goes through. Every one of these is a pure function of a handful
/// of points, so they are the cheap half of the check; the expensive half — that the
/// city's own shapes go through them sensibly — is at the bottom.
@MainActor
final class DrawnNeighborhoodTests: XCTestCase {

    // A square, counter-clockwise on screen.
    private let square = [
        CGPoint(x: 0, y: 0), CGPoint(x: 100, y: 0),
        CGPoint(x: 100, y: 100), CGPoint(x: 0, y: 100),
    ]

    /// A horseshoe opening east — the shape the Financial District makes round Battery
    /// Park City, and the reason a centroid is not enough on its own.
    private let horseshoe = [
        CGPoint(x: 0, y: 0), CGPoint(x: 100, y: 0), CGPoint(x: 100, y: 20),
        CGPoint(x: 30, y: 20), CGPoint(x: 30, y: 80), CGPoint(x: 100, y: 80),
        CGPoint(x: 100, y: 100), CGPoint(x: 0, y: 100),
    ]

    // MARK: - Inside and out

    func testAPointInsideIsInside() {
        XCTAssertTrue(DrawnNeighborhood.ring(square, contains: CGPoint(x: 50, y: 50)))
        XCTAssertTrue(DrawnNeighborhood.ring(square, contains: CGPoint(x: 1, y: 99)))
    }

    func testAPointOutsideIsOutside() {
        for point in [
            CGPoint(x: -1, y: 50), CGPoint(x: 101, y: 50),
            CGPoint(x: 50, y: -1), CGPoint(x: 50, y: 101),
        ] {
            XCTAssertFalse(DrawnNeighborhood.ring(square, contains: point), "\(point)")
        }
    }

    func testTheNotchOfAHorseshoeIsOutsideIt() {
        // Dead centre of the bounding box, and firmly not in the shape.
        XCTAssertFalse(DrawnNeighborhood.ring(horseshoe, contains: CGPoint(x: 60, y: 50)))
        XCTAssertTrue(DrawnNeighborhood.ring(horseshoe, contains: CGPoint(x: 10, y: 50)))
    }

    func testALineIsNotAShape() {
        XCTAssertFalse(DrawnNeighborhood.ring([], contains: .zero))
        XCTAssertFalse(DrawnNeighborhood.ring([CGPoint(x: 0, y: 0), CGPoint(x: 1, y: 1)], contains: .zero))
    }

    // MARK: - Where the name goes

    func testTheMiddleOfASquareIsItsMiddle() {
        let centre = DrawnNeighborhood.centroid(of: square)
        XCTAssertEqual(Double(centre.x), 50, accuracy: 1e-9)
        XCTAssertEqual(Double(centre.y), 50, accuracy: 1e-9)
    }

    func testTheMiddleOfAHorseshoeIsPulledBackIntoIt() {
        let centre = DrawnNeighborhood.centroid(of: horseshoe)
        XCTAssertFalse(
            DrawnNeighborhood.ring(horseshoe, contains: centre),
            "This shape is only interesting if its centroid misses"
        )

        let rescued = DrawnNeighborhood.insidePoint(of: horseshoe, near: centre)
        XCTAssertTrue(DrawnNeighborhood.ring(horseshoe, contains: rescued))
        XCTAssertEqual(Double(rescued.y), Double(centre.y), accuracy: 1e-9, "It stays at the same height")
    }

    func testADegenerateRingDoesNotDivideByZero() {
        let flat = [CGPoint(x: 0, y: 5), CGPoint(x: 10, y: 5), CGPoint(x: 20, y: 5)]
        let centre = DrawnNeighborhood.centroid(of: flat)
        XCTAssertEqual(Double(centre.x), 10, accuracy: 1e-9)
        XCTAssertEqual(Double(centre.y), 5, accuracy: 1e-9)
        // Nothing to be inside of, so it hands the point back rather than inventing one.
        XCTAssertEqual(DrawnNeighborhood.insidePoint(of: flat, near: centre), centre)
    }

    // MARK: - The city's own shapes

    private let size = CGSize(width: 393, height: 852)
    private lazy var map = DrawnMap.build(size: size)

    func testEveryNeighborhoodIsDrawnAndCanBeTouched() {
        XCTAssertEqual(map.neighborhoods.count, ManhattanMapData.neighborhoods.count)

        for area in map.neighborhoods {
            XCTAssertFalse(area.shape.isEmpty, "\(area.name) has nothing to fill")
            XCTAssertFalse(area.edge.isEmpty, "\(area.name) has no line round it")
            XCTAssertFalse(area.rings.isEmpty, "\(area.name) has nothing to hit test")
            XCTAssertFalse(area.bounds.isNull, "\(area.name) has no box to cull against")
        }
    }

    func testTheNamesGoSomewhereInsideTheirOwnNeighborhood() {
        for area in map.neighborhoods {
            XCTAssertTrue(
                area.contains(area.labelPoint),
                "\(area.name)'s name is written outside \(area.name)"
            )
        }
    }

    /// The whole point of the feature, end to end: press where a neighborhood's name is
    /// written and you get that neighborhood back and no other. The areas tile the
    /// island, so this would also catch two of them claiming the same ground after
    /// thinning.
    func testTouchingANeighborhoodPicksOutThatNeighborhood() {
        for area in map.neighborhoods {
            let hit = map.neighborhood(at: area.labelPoint)
            XCTAssertEqual(hit?.id, area.id, "Touching \(area.name) gave back \(hit?.name ?? "nothing")")
        }
    }

    func testTouchingTheWaterPicksOutNothing() {
        // The four corners of the page. The island is drawn rotated and padded, so all
        // four are river.
        for corner in [
            CGPoint(x: 1, y: 1), CGPoint(x: size.width - 1, y: 1),
            CGPoint(x: 1, y: size.height - 1), CGPoint(x: size.width - 1, y: size.height - 1),
        ] {
            XCTAssertNil(map.neighborhood(at: corner), "There is a neighborhood in the river at \(corner)")
        }
    }

    func testTheNeighborhoodsCoverTheIsland() {
        let island = map.land.boundingRect
        var covered = CGRect.null
        for area in map.neighborhoods {
            XCTAssertTrue(area.bounds.intersects(island), "\(area.name) is off the island")
            covered = covered.union(area.bounds)
        }

        // Top to bottom, near enough: what this would catch is a re-fetch that lost a
        // whole end of the island. Only near enough, for two reasons — the city draws
        // these out to the pierhead lines rather than to the water's edge, so they
        // spill a little into both rivers, and the very northern tip is Inwood Hill
        // Park, which is an NTA nobody lives in and so is not here at all.
        XCTAssertLessThanOrEqual(covered.minY, island.minY + island.height * 0.06)
        XCTAssertGreaterThanOrEqual(covered.maxY, island.maxY - island.height * 0.06)
    }

    func testTheOnesTheCityLeavesOutAreLeftOut() {
        // Central Park is its own kind of NTA and is not a neighborhood anybody lives
        // in, so it is a hole in the coverage rather than a shape. A tap in the middle
        // of the Ramble picks out nothing, which is the behaviour the quiz will want.
        let ramble = map.projection.point(Coordinate(-73.9654, 40.7829))
        XCTAssertNil(map.neighborhood(at: ramble))
    }

    func testANeighborhoodCanBeFoundByName() {
        XCTAssertEqual(map.neighborhood(named: "Greenwich Village")?.name, "Greenwich Village")
        XCTAssertNil(map.neighborhood(named: "Brooklyn Heights"))
    }

    // MARK: - Reading it

    func testANeighborhoodsNameIsWrittenLargerThanAnyStreetName() {
        // It is the answer to the question the map is asking, and at the size it
        // started at you had to go looking for it among the cross streets.
        for palette in [MapPalette.day, MapPalette.night] {
            for kind in RoadKind.allCases {
                XCTAssertGreaterThan(
                    palette.neighborhoodLabelSize,
                    palette.labelSize(for: kind) * 1.5,
                    "A \(kind) name is nearly as loud as a neighborhood's"
                )
            }
            // And it clears more paper round itself, because it lies across a grid of
            // streets rather than crossing one.
            XCTAssertGreaterThan(palette.neighborhoodHaloReach, palette.labelHaloReach)
        }
    }
}
