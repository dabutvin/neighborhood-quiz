import SwiftUI
import XCTest
@testable import NeighborhoodQuiz

/// The facts the fast path for the streets rests on.
///
/// Pulled back, nothing is off the glass, so skipping what cannot be seen skips
/// nothing and every road pays for a stroke of its own — four hundred of them at the
/// view the app opens on. The drawing now puts a whole rank down in one stroke when
/// most of it is showing, which is only allowed because of two things: every road of a
/// rank always carries the same ink, and the one path really does hold every road of
/// that rank. Both are checked here, because if either quietly stopped being true the
/// map would go wrong in a way no test was watching.
@MainActor
final class RoadSheetTests: XCTestCase {
    private let size = CGSize(width: 393, height: 852)
    private lazy var map = DrawnMap.build(borough: .manhattan, size: size)

    /// The load-bearing one. A rank fades in as a rank; no road inside it is ever a
    /// different shade from its neighbours, which is what lets them share a stroke.
    func testEveryRoadOfARankComesInAtTheSameZoom() {
        for kind in RoadKind.allCases {
            let zooms = Set(map.roads.filter { $0.kind == kind }.map(\.minZoom))
            XCTAssertEqual(zooms.count, 1, "\(kind) does not fade in as one rank: \(zooms)")
            XCTAssertEqual(zooms.first, DrawnMap.minZoom(for: kind))
        }
    }

    func testOnlyTheSideStreetsWaitToBeShown() {
        XCTAssertEqual(DrawnMap.minZoom(for: .avenue), 1)
        XCTAssertEqual(DrawnMap.minZoom(for: .major), 1)
        XCTAssertEqual(DrawnMap.minZoom(for: .side), DrawnMap.sideStreetZoom)
        XCTAssertGreaterThan(DrawnMap.sideStreetZoom, 1)
    }

    /// The split list is the same roads, in the same order, just filed by rank.
    ///
    /// The drawing trusts it for two separate things: which roads to stroke when a
    /// rank is mostly off the glass, and — through its count — whether the rank is
    /// mostly on the glass in the first place. A split that dropped a road would
    /// quietly make the sheet look like the better choice sooner than it is.
    func testTheSplitHoldsEveryRoadAndOnlyItsOwn() {
        XCTAssertEqual(map.roadsByKind.count, RoadKind.allCases.count)

        var total = 0
        for kind in RoadKind.allCases {
            let rank = map.roadsByKind[kind.rawValue]
            let expected = map.roads.filter { $0.kind == kind }

            XCTAssertFalse(rank.isEmpty, "\(kind) has no roads at all")
            XCTAssertEqual(rank.count, expected.count, "\(kind) lost or gained roads")
            XCTAssertEqual(rank.map(\.id), expected.map(\.id), "\(kind) is out of order")
            XCTAssertTrue(rank.allSatisfy { $0.kind == kind }, "\(kind) holds another rank")
            total += rank.count
        }
        XCTAssertEqual(total, map.roads.count, "The split is not the whole map")
    }

    func testThereIsOneSheetPerRank() {
        XCTAssertEqual(map.roadSheets.count, RoadKind.allCases.count)
        for kind in RoadKind.allCases {
            XCTAssertFalse(
                map.roadSheets[kind.rawValue].isEmpty,
                "\(kind) has roads but an empty sheet"
            )
        }
    }

    /// That the sheet is the whole rank and not most of it.
    ///
    /// Comparing the box each covers: a road left out of its sheet at the edge of the
    /// island would shrink the box and be caught, and one left out of the middle would
    /// not — so this is a floor rather than a proof. It is the check that catches the
    /// mistake anybody would actually make, which is building the sheets from the wrong
    /// list or before the roads are complete.
    func testASheetCoversTheWholeRank() {
        for kind in RoadKind.allCases {
            let roads = map.roads.filter { $0.kind == kind }
            XCTAssertFalse(roads.isEmpty, "\(kind) has no roads at all")

            let expected = roads.dropFirst().reduce(roads[0].bounds) { $0.union($1.bounds) }
            let actual = map.roadSheets[kind.rawValue].boundingRect

            XCTAssertEqual(actual.minX, expected.minX, accuracy: 0.5, "\(kind) left edge")
            XCTAssertEqual(actual.minY, expected.minY, accuracy: 0.5, "\(kind) top edge")
            XCTAssertEqual(actual.maxX, expected.maxX, accuracy: 0.5, "\(kind) right edge")
            XCTAssertEqual(actual.maxY, expected.maxY, accuracy: 0.5, "\(kind) bottom edge")
        }
    }

    /// The measurement cache is shared, not copied. A struct holding a class means every
    /// copy of the map reads and writes the one cache — which is the entire point, since
    /// a cache that emptied whenever the map was passed to a view would never be warm.
    func testTheNameCacheIsSharedByEveryCopyOfTheMap() {
        let copy = map
        XCTAssertTrue(copy.metrics === map.metrics)
        XCTAssertEqual(map.metrics.count, 0, "nothing is measured until a name is drawn")
    }

    // MARK: - Fading in, and when a sheet is allowed

    /// The rule that keeps the sheet honest.
    ///
    /// Half-transparent strokes laid down one at a time build up where they cross; the
    /// same lines in a single path are composited once and do not. So a rank may only
    /// go down as a sheet at full ink. These two ranks are always at full ink, which is
    /// why the opening view — where nothing is off the glass and so nothing is skipped —
    /// is the case the sheet was built for.
    func testTheAvenuesAndMajorStreetsAreAlwaysFullyIn() {
        for zoom in stride(from: 1.0, through: 14.0, by: 0.25) {
            XCTAssertEqual(DrawnMap.presence(of: .avenue, at: zoom), 1, "avenue at \(zoom)")
            XCTAssertEqual(DrawnMap.presence(of: .major, at: zoom), 1, "major at \(zoom)")
        }
    }

    /// Below a borough's own scale — the whole city, pulled back — even the avenues go,
    /// so the overview is the shape of the city rather than a wash of brown.
    func testTheAvenuesGiveWayOnTheWholeCity() {
        XCTAssertEqual(DrawnMap.presence(of: .avenue, at: DrawnMap.overviewZoom), 0)
        XCTAssertEqual(DrawnMap.presence(of: .avenue, at: 0.3), 0)
        XCTAssertEqual(DrawnMap.presence(of: .major, at: 0.3), 0)
        XCTAssertEqual(DrawnMap.presence(of: .side, at: 0.3), 0)

        let middle = (DrawnMap.overviewZoom + 1) / 2
        XCTAssertEqual(DrawnMap.presence(of: .avenue, at: middle), 0.5, accuracy: 0.001)

        var last = -1.0
        for zoom in stride(from: 0.2, through: 1.0, by: 0.05) {
            let now = DrawnMap.presence(of: .avenue, at: zoom)
            XCTAssertGreaterThanOrEqual(now, last, "avenues fading back out at \(zoom)")
            last = now
        }
    }

    /// And the one rank that does fade is never caught part-way at full ink, so it can
    /// never be drawn as a sheet while it is still coming in.
    func testTheSideStreetsComeInSmoothlyAndOnlyCountAsFullAtTheEnd() {
        XCTAssertEqual(DrawnMap.presence(of: .side, at: 1), 0)
        XCTAssertEqual(DrawnMap.presence(of: .side, at: DrawnMap.sideStreetZoom), 0)
        XCTAssertEqual(DrawnMap.presence(of: .side, at: DrawnMap.sideStreetFullZoom), 1)
        XCTAssertEqual(DrawnMap.presence(of: .side, at: 14), 1)

        let middle = (DrawnMap.sideStreetZoom + DrawnMap.sideStreetFullZoom) / 2
        XCTAssertEqual(DrawnMap.presence(of: .side, at: middle), 0.5, accuracy: 0.001)

        // No step anywhere in the climb: that is what stops the grid snapping on.
        var last = 0.0
        for zoom in stride(from: 1.0, through: 3.0, by: 0.02) {
            let now = DrawnMap.presence(of: .side, at: zoom)
            XCTAssertGreaterThanOrEqual(now, last, "went backwards at \(zoom)")
            XCTAssertLessThanOrEqual(now - last, 0.05, "jumped at \(zoom)")
            last = now
        }
        XCTAssertEqual(last, 1)
    }

    /// Roads are held light-first so the heavy lines are never broken by the light ones
    /// crossing them, and the drawing walks the ranks in that same order.
    func testTheRoadsAreHeldLightestFirst() {
        let ranks = map.roads.map(\.kind.rawValue)
        XCTAssertEqual(ranks, ranks.sorted(by: >))
    }
}
