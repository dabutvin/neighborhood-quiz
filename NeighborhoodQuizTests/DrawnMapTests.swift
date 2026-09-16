import SwiftUI
import XCTest
@testable import NeighborhoodQuiz

@MainActor
final class DrawnMapTests: XCTestCase {
    private let size = CGSize(width: 393, height: 852)  // an iPhone, near enough
    private lazy var map = DrawnMap.build(size: size)

    func testTheIslandTheGreensAndTheStreetsAreAllDrawn() {
        XCTAssertFalse(map.land.isEmpty)
        XCTAssertFalse(map.landEdge.isEmpty)
        XCTAssertFalse(map.parks.isEmpty)
        XCTAssertFalse(map.parkEdge.isEmpty)
        XCTAssertEqual(map.size, size)
        XCTAssertEqual(map.roads.count, ManhattanMapData.roads.count)
    }

    func testTheGreensAreInsideTheIsland() {
        let island = map.land.boundingRect
        XCTAssertTrue(island.insetBy(dx: -6, dy: -6).contains(map.parks.boundingRect))
    }

    func testTheHeavyLinesAreDrawnOverTheFineOnes() {
        let order = map.roads.map { -$0.kind.rawValue }
        XCTAssertEqual(order, order.sorted(), "Side streets first, avenues last")
    }

    func testEveryNameIsWrittenOnThePage() {
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
        let limit = Double.pi / 2 + Polyline.uprightTolerance + 1e-9
        for label in map.labels {
            XCTAssertLessThanOrEqual(abs(label.angle), limit, "\(label.text) reads backwards")
        }
    }

    func testEveryStreetIsOfferedItsNameExactlyOnce() {
        XCTAssertEqual(map.labels.count, ManhattanMapData.roads.filter(\.carriesName).count)
        let texts = map.labels.map(\.text)
        XCTAssertEqual(Set(texts).count, texts.count, "A street is offered its name once")
    }

    func testTheImportantNamesAreOfferedFirst() {
        // Whichever name reaches a patch of paper first keeps it, so the order labels
        // come in is the order they win ties in — and within a rank it is longest first,
        // because the data arrives that way.
        let order = map.labels.map(\.kind.rawValue)
        XCTAssertEqual(order, order.sorted())
    }

    func testEveryRoadKnowsWhereItSits() {
        for road in map.roads {
            XCTAssertFalse(road.bounds.isNull, "\(road.id) has no box to cull against")
            XCTAssertEqual(road.bounds, road.path.boundingRect, "\(road.id)'s box is stale")
        }
    }

    func testTheSideStreetsWaitUntilThereIsRoomForThem() {
        for road in map.roads {
            switch road.kind {
            case .side:
                XCTAssertEqual(road.minZoom, DrawnMap.sideStreetZoom)
            case .avenue, .major:
                XCTAssertEqual(road.minZoom, 1, "\(road.kind) is part of the wide view")
            }
        }
        // The wide view is not bare, and it is not the whole city either.
        let atRest = map.roads.filter { $0.minZoom <= 1 }
        XCTAssertGreaterThan(atRest.count, 50)
        XCTAssertLessThan(atRest.count, map.roads.count / 2)
    }

    func testTheCullLeavesTheWideViewAloneAndGutsTheCloseOne() {
        // At rest the whole island is on the glass, so almost nothing may be culled.
        let wide = MapCamera().visibleRect(in: size, margin: 8)
        let offscreenWide = map.roads.filter { !$0.bounds.intersects(wide) }.count
        XCTAssertLessThan(offscreenWide, map.roads.count / 20, "The wide view shows the island")

        // Four times in on Midtown, most of it is not — which is the saving.
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
