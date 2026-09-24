import SwiftUI
import XCTest
@testable import NeighborhoodQuiz

/// The drawing, built from Manhattan's data unless a test says otherwise. The other
/// four boroughs get a loop of their own at the bottom; everything the five share is
/// checked on the one.
@MainActor
final class DrawnMapTests: XCTestCase {
    private let size = CGSize(width: 393, height: 852)  // an iPhone, near enough
    private let data = BoroughMap.of(.manhattan)
    private lazy var map = DrawnMap.build(borough: .manhattan, size: size)

    func testTheIslandTheGreensAndTheStreetsAreAllDrawn() {
        XCTAssertFalse(map.land.isEmpty)
        XCTAssertFalse(map.landEdge.isEmpty)
        XCTAssertFalse(map.parks.isEmpty)
        XCTAssertFalse(map.parkEdge.isEmpty)
        XCTAssertEqual(map.size, size)
        XCTAssertEqual(map.borough, .manhattan)
        XCTAssertEqual(map.roads.count, data.roads.count)
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
        XCTAssertEqual(map.labels.count, data.roads.filter(\.carriesName).count)
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
        let again = DrawnMap.build(borough: .manhattan, size: size)
        XCTAssertEqual(map.land, again.land)
        XCTAssertEqual(map.roads.count, again.roads.count)
        XCTAssertEqual(map.roads.first?.path, again.roads.first?.path)
        XCTAssertEqual(map.labels.map(\.text), again.labels.map(\.text))
        XCTAssertEqual(map.labels.map(\.position), again.labels.map(\.position))
    }

    func testADifferentSizeRedrawsRatherThanRescales() {
        let wide = DrawnMap.build(borough: .manhattan, size: CGSize(width: 820, height: 1_180))
        XCTAssertEqual(wide.size, CGSize(width: 820, height: 1_180))
        XCTAssertNotEqual(wide.land, map.land)
        XCTAssertGreaterThan(wide.land.boundingRect.height, map.land.boundingRect.height)
    }

    /// What a launch opens on. The one that matters is the first: a person launching the
    /// app passes no arguments and must get the game, not the map. Everything else here
    /// is the screenshot runs.
    func testALaunchWithNoArgumentsStartsARound() {
        XCTAssertEqual(Screen(arguments: ["NeighborhoodQuiz"]), .quiz(stage: nil))
        XCTAssertEqual(Screen(arguments: []), .quiz(stage: nil))
        XCTAssertEqual(
            Screen(arguments: ["NeighborhoodQuiz", "-NSTreatUnknownArgumentsAsOpen", "NO"]),
            .quiz(stage: nil),
            "Xcode and the simulator pass arguments of their own"
        )
    }

    /// Every state the gallery shoots has an argument that reaches it, and no two share
    /// one. A staged screen nobody can launch is a screenshot that silently becomes the
    /// fresh-round shot again.
    func testEveryStagedScreenHasItsOwnArgument() {
        for stage in QuizView.Stage.allCases {
            XCTAssertEqual(
                Screen(arguments: ["x", "-quiz-\(stage.rawValue)"]),
                .quiz(stage: stage),
                "-quiz-\(stage.rawValue) should reach \(stage)"
            )
        }
        let arguments = QuizView.Stage.allCases.map(\.rawValue)
        XCTAssertEqual(Set(arguments).count, arguments.count)
    }

    /// The staged rounds ask for these by name, so a rename in the data would quietly
    /// shorten the round the gallery plays and the screenshots would stop matching the
    /// states they are named after.
    func testTheGalleryRoundAsksForPlacesThatExist() {
        for name in QuizView.showcase {
            XCTAssertNotNil(map.neighborhood(named: name), "\(name) is not on the map")
        }
        XCTAssertEqual(QuizView.showcase.count, QuizRound.questionCount)
        // Two more the staging picks out by hand.
        XCTAssertNotNil(map.neighborhood(named: "SoHo"))
        XCTAssertNotNil(map.neighborhood(named: "West Village"))
    }

    func testTheScreenshotArgumentsAskForTheMap() {
        XCTAssertEqual(
            Screen(arguments: ["x", "-map"]),
            .map(borough: .manhattan, opening: .island, showing: nil)
        )
        XCTAssertEqual(
            Screen(arguments: ["x", "-map-zoomed"]),
            .map(borough: .manhattan, opening: .midtown, showing: nil)
        )
        XCTAssertEqual(
            Screen(arguments: ["x", "-map-neighborhood"]),
            .map(borough: .manhattan, opening: .neighborhood("Greenwich Village"), showing: "Greenwich Village")
        )
        // An argument apiece rather than a flag on `-map`, so the gallery's capture
        // lines stay one word per shot.
        let shots: [(String, Borough)] = [
            ("-map-brooklyn", .brooklyn),
            ("-map-queens", .queens),
            ("-map-bronx", .bronx),
            ("-map-staten-island", .statenIsland),
        ]
        for (argument, borough) in shots {
            XCTAssertEqual(
                Screen(arguments: ["x", argument]),
                .map(borough: borough, opening: .island, showing: nil),
                "\(argument) should open on \(borough.name)"
            )
        }
    }

    /// The shot that shows a highlight names a real place, and a rename in the data
    /// would otherwise turn it into a screenshot of nothing picked out at all.
    func testTheHighlightShotNamesAPlaceThatExists() {
        guard case .map(_, _, let showing) = Screen(arguments: ["x", "-map-neighborhood"]),
              let showing else {
            return XCTFail("That argument should ask for a neighborhood")
        }
        XCTAssertNotNil(map.neighborhood(named: showing), "\(showing) is not on the map")
    }

    // MARK: - The other boroughs

    /// Every borough goes through the same builder and comes out whole: every road and
    /// every neighbourhood in its file is on the page, every name is written on the
    /// paper rather than off it, and the drawing knows whose map it is. Built at the
    /// phone size, which is the one a player sees first. Five builds is a second or
    /// two, and this is the test that would catch a file that loads but does not draw.
    func testEveryBoroughDrawsWhole() {
        let paper = CGRect(origin: .zero, size: size)
        for borough in Borough.allCases {
            let data = BoroughMap.of(borough)
            let drawn = DrawnMap.build(borough: borough, size: size)

            XCTAssertEqual(drawn.borough, borough)
            XCTAssertEqual(drawn.size, size)
            XCTAssertFalse(drawn.land.isEmpty, "\(borough.name) has no land")
            XCTAssertFalse(drawn.landEdge.isEmpty, "\(borough.name) has no shoreline")
            XCTAssertFalse(drawn.parks.isEmpty, "\(borough.name) has no greens")
            XCTAssertEqual(drawn.roads.count, data.roads.count, "\(borough.name) did not draw every road")
            XCTAssertEqual(drawn.neighborhoods.count, data.neighborhoods.count, "\(borough.name) did not draw every neighbourhood")
            XCTAssertEqual(drawn.labels.count, data.roads.filter(\.carriesName).count, "\(borough.name) offers every name once")

            for label in drawn.labels {
                XCTAssertTrue(paper.contains(label.position), "\(borough.name): \(label.text) is written off the page")
            }
        }
    }

    /// Brooklyn is drawn north-up — the projection was built with no turn — which is
    /// checked against a street rather than a number: Atlantic Avenue runs west to
    /// east across the borough, and unturned it should lie close to flat. The other
    /// three are north-up too, but Brooklyn is the one with a street that runs
    /// straight enough across the whole borough to say so.
    func testBrooklynIsDrawnAsItSits() throws {
        let brooklyn = DrawnMap.build(borough: .brooklyn, size: size)

        XCTAssertEqual(Borough.brooklyn.gridBearingDegrees, 0, "Brooklyn is drawn as it sits")
        let atlantic = try XCTUnwrap(
            brooklyn.labels.first { $0.text == "Atlantic Avenue" },
            "Atlantic Avenue should be on the map and carry its name"
        )
        XCTAssertEqual(atlantic.angle, 0, accuracy: 0.35, "Atlantic Avenue runs west to east, so north-up it lies flat")
    }

    /// No two boroughs are the same drawing with the same places on it. The obvious
    /// thing, but it is what the cache in `BoroughMap.of` and the borough check in
    /// `MapBoard` both rest on, so it is worth one loop saying so — and a copy-paste
    /// in the tool that wrote one borough's neighbourhoods into another's file would
    /// pass every data test and fail here.
    func testNoTwoBoroughsAreTheSameMap() {
        let names = Dictionary(uniqueKeysWithValues: Borough.allCases.map { borough in
            (borough, Set(DrawnMap.build(borough: borough, size: size).neighborhoods.map(\.name)))
        })
        for here in Borough.allCases {
            for there in Borough.allCases where here != there {
                XCTAssertNotEqual(names[here], names[there], "\(here.name) and \(there.name) are the same map")
            }
        }
        XCTAssertTrue(names[.manhattan]?.contains("SoHo") ?? false)
        XCTAssertTrue(names[.brooklyn]?.contains("Park Slope") ?? false)
        XCTAssertFalse(names[.brooklyn]?.contains("SoHo") ?? true)
    }
}
