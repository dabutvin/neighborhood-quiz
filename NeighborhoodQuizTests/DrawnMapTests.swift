import SwiftUI
import XCTest
@testable import NeighborhoodQuiz

@MainActor
final class DrawnMapTests: XCTestCase {
    private let size = CGSize(width: 393, height: 852)  // an iPhone, near enough
    private lazy var map = DrawnMap.build(size: size)

    func testTheIslandAndTheParkAreDrawn() {
        XCTAssertFalse(map.land.isEmpty)
        XCTAssertFalse(map.landEdge.isEmpty)
        XCTAssertFalse(map.park.isEmpty)
        XCTAssertFalse(map.parkEdge.isEmpty)
        XCTAssertEqual(map.size, size)
    }

    func testTheParkIsInsideTheIsland() {
        let island = map.land.boundingRect
        let park = map.park.boundingRect
        XCTAssertTrue(island.insetBy(dx: -4, dy: -4).contains(park))
        XCTAssertLessThan(park.width * park.height, island.width * island.height / 4)
    }

    func testEveryStreetSurvivesTheShoreline() {
        // Not one road may be clipped out of existence: a road that draws nothing is a
        // road whose coordinates are wrong, and on a map made of two hundred lines that
        // is exactly the sort of thing nobody notices by eye.
        let roads = ManhattanMapData.roads
        let drawn = Set(map.roads.compactMap { Int($0.id.split(separator: "-")[0]) })
        let missing = roads.indices.filter { !drawn.contains($0) }.map { roads[$0].name }
        XCTAssertEqual(missing, [], "These roads were clipped away entirely")
    }

    func testTheHeavyLinesAreDrawnOverTheFineOnes() {
        let order = map.roads.map { road -> Int in
            switch road.kind {
            case .crossStreet: return 0
            case .majorCrossStreet: return 1
            case .namedStreet: return 2
            case .avenue: return 3
            }
        }
        XCTAssertEqual(order, order.sorted())
    }

    func testEveryNameIsWrittenOnTheIsland() {
        let paper = CGRect(origin: .zero, size: size)
        for label in map.labels {
            XCTAssertTrue(
                paper.contains(label.position),
                "\(label.text) is written off the page at \(label.position)"
            )
        }
    }

    func testNoNameIsUpsideDown() {
        // A quarter turn, plus the slack that lets a near-vertical avenue read upwards
        // rather than downwards. Anything past that is a name written back to front.
        let limit = Double.pi / 2 + Shoreline.uprightTolerance + 1e-9
        for label in map.labels {
            XCTAssertLessThanOrEqual(abs(label.angle), limit, "\(label.text) reads backwards")
        }
    }

    func testTheAvenuesAreWrittenUpThePageAndTheStreetsAcrossIt() {
        func angle(_ name: String) -> Double? { map.labels.first { $0.text == name }?.angle }

        // The plane is turned so the avenues stand up, so their names do too: a quarter
        // turn anticlockwise, reading from the bottom.
        XCTAssertEqual(angle("Fifth Avenue") ?? 0, -.pi / 2, accuracy: 0.05)
        XCTAssertEqual(angle("42nd Street") ?? 1, 0, accuracy: 0.05)
    }

    func testTheNamesEverybodyKnowsAreAllThere() {
        let names = Set(map.labels.map(\.text))
        for expected in [
            "Fifth Avenue", "Broadway", "Park Avenue", "Central Park West",
            "Lexington Avenue", "Amsterdam Avenue", "42nd Street", "125th Street",
            "Houston Street", "Canal Street", "Wall Street",
        ] {
            XCTAssertTrue(names.contains(expected), "\(expected) is not on the map")
        }
    }

    func testTheWholeIslandOpensWithoutAWallOfText() {
        // At the widest zoom only the names somebody could place blind are written.
        let atRest = map.labels.filter { $0.minZoom <= 1 }
        XCTAssertGreaterThan(atRest.count, 8, "The opening map should not be bare")
        XCTAssertLessThan(atRest.count, 30, "Nor a wall of text")
    }

    func testPullingInBringsMoreNamesOut() {
        let atRest = map.labels.filter { $0.minZoom <= 1 }.count
        let closer = map.labels.filter { $0.minZoom <= 4 }.count
        XCTAssertGreaterThan(closer, atRest * 2)
    }

    func testTheSideStreetsWaitUntilThereIsRoomForThem() {
        for road in map.roads {
            switch road.kind {
            case .crossStreet:
                XCTAssertGreaterThan(road.minZoom, 1, "Side streets are a smudge at the widest zoom")
                XCTAssertLessThan(road.minZoom, DrawnMap.sideStreetFullZoom)
            case .avenue, .majorCrossStreet, .namedStreet:
                XCTAssertEqual(road.minZoom, 1, "\(road.kind) is part of the wide view")
            }
        }

        // The wide view is not bare: the avenues and the streets people name are all on it.
        let atRest = map.roads.filter { $0.minZoom <= 1 }
        XCTAssertGreaterThan(atRest.count, 30)
    }

    func testTheImportantNamesAreOfferedFirst() {
        // Whichever name reaches a patch of paper first keeps it, so the order labels
        // come in is the order they win ties in.
        let order = map.labels.map { label -> Int in
            switch label.kind {
            case .avenue: return 0
            case .namedStreet: return 1
            case .majorCrossStreet: return 2
            case .crossStreet: return 3
            }
        }
        XCTAssertEqual(order, order.sorted())
    }

    func testEveryRoadKnowsWhereItSits() {
        for road in map.roads {
            XCTAssertFalse(road.bounds.isNull, "\(road.id) has no box to cull against")
            XCTAssertEqual(road.bounds, road.path.boundingRect, "\(road.id)'s box is stale")
        }
    }

    func testTheCullLeavesTheWideViewAloneAndGutsTheCloseOne() {
        // At rest the whole island is on the glass, so nothing may be culled.
        let wide = MapCamera().visibleRect(in: size, margin: 8)
        XCTAssertEqual(map.roads.filter { !$0.bounds.intersects(wide) }.count, 0)

        // Four times in on Midtown, almost none of it is — which is the saving.
        let midtown = map.projection.point(Coordinate(-73.9855, 40.7580))
        let close = MapCamera.centred(on: midtown, zoom: 4, in: size).visibleRect(in: size, margin: 8)
        let drawn = map.roads.filter { $0.bounds.intersects(close) }
        XCTAssertLessThan(
            Double(drawn.count) / Double(map.roads.count),
            0.5,
            "Coming in should leave most of the drawing off the glass"
        )
        XCTAssertGreaterThan(drawn.count, 10, "But not all of it — there is a city there")
    }

    func testTheMapIsDrawnTheSameWayTwice() {
        let again = DrawnMap.build(size: size)
        XCTAssertEqual(map.land, again.land)
        XCTAssertEqual(map.roads.count, again.roads.count)
        XCTAssertEqual(map.roads.first?.path, again.roads.first?.path)
        XCTAssertEqual(map.labels.map(\.text), again.labels.map(\.text))
        XCTAssertEqual(map.labels.map(\.position), again.labels.map(\.position))
    }

    func testADifferentSizeRedrawsRatherThanRescales() {
        let wide = DrawnMap.build(size: CGSize(width: 820, height: 1_180))
        XCTAssertEqual(wide.size, CGSize(width: 820, height: 1_180))
        XCTAssertNotEqual(wide.land, map.land)
        XCTAssertGreaterThan(wide.land.boundingRect.height, map.land.boundingRect.height)
    }

    func testTheScreenshotOpeningAimsAtMidtown() {
        XCTAssertEqual(HomeView.Opening(arguments: ["NeighborhoodQuiz"]), .island)
        XCTAssertEqual(HomeView.Opening(arguments: ["NeighborhoodQuiz", "-map"]), .island)
        XCTAssertEqual(HomeView.Opening(arguments: ["NeighborhoodQuiz", "-map-zoomed"]), .midtown)
    }
}
