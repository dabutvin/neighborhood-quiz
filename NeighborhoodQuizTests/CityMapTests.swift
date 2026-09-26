import CoreGraphics
import XCTest
@testable import NeighborhoodQuiz

/// The whole city on one sheet: what a round across the city draws, so that getting
/// from SoHo to Astoria is a push across the river rather than a jump between maps.
@MainActor
final class CityMapTests: XCTestCase {
    private let size = CGSize(width: 393, height: 700)

    // MARK: - Numbering

    /// On one borough's sheet a place is drawn under its own index, exactly as before.
    func testABoroughsSheetNumbersPlacesAsItAlwaysDid() {
        let sheet = MapSheet.borough(.brooklyn)

        XCTAssertEqual(sheet.id(of: Place(.brooklyn, 12)), 12)
        XCTAssertEqual(sheet.place(for: 12), Place(.brooklyn, 12))
        XCTAssertNil(sheet.id(of: Place(.queens, 12)), "Queens is not on Brooklyn's sheet")
    }

    /// On the city the borough is folded in, and comes back out.
    func testTheCitysNumbersCarryTheBoroughAndComeBack() {
        let sheet = MapSheet.city([.manhattan, .brooklyn, .queens])

        for place in [Place(.manhattan, 0), Place(.brooklyn, 12), Place(.queens, 67)] {
            let id = sheet.id(of: place)
            XCTAssertNotNil(id)
            XCTAssertEqual(id.flatMap(sheet.place(for:)), place)
        }
        XCTAssertNotEqual(
            sheet.id(of: Place(.manhattan, 12)), sheet.id(of: Place(.brooklyn, 12)),
            "Manhattan's twelfth and Brooklyn's twelfth are both on the page"
        )
    }

    func testABoroughNotOnTheCitySheetHasNoNumberThere() {
        let sheet = MapSheet.city([.manhattan, .brooklyn])

        XCTAssertNil(sheet.id(of: Place(.bronx, 3)))
        let bronxSlot = Borough.allCases.firstIndex(of: .bronx)!
        XCTAssertNil(sheet.place(for: bronxSlot * MapSheet.stride + 3))
    }

    func testTheCityIsNorthUpAndInTheCitysOrder() {
        let sheet = MapSheet.city([.queens, .manhattan])

        XCTAssertEqual(sheet.boroughs, [.manhattan, .queens])
        XCTAssertEqual(sheet.rotation, 0)
        XCTAssertEqual(MapSheet.borough(.manhattan).rotation, -Borough.manhattan.gridBearingDegrees)
        XCTAssertEqual(sheet.name, "New York City")
    }

    // MARK: - The drawing

    /// Every neighbourhood of every borough on the sheet, each under a number that
    /// leads back to the right place — by name, which is the test that matters.
    func testTheCityHoldsEveryNeighborhoodUnderTheRightPlace() {
        let sheet = MapSheet.city([.manhattan, .brooklyn])
        let city = DrawnMap.build(sheet: sheet, size: size)

        let expected = BoroughMap.of(.manhattan).neighborhoods.count
            + BoroughMap.of(.brooklyn).neighborhoods.count
        XCTAssertEqual(city.neighborhoods.count, expected)
        XCTAssertEqual(Set(city.neighborhoods.map(\.id)).count, expected, "no two share a number")

        for drawn in city.neighborhoods {
            let place = sheet.place(for: drawn.id)
            XCTAssertNotNil(place, "\(drawn.name) has a number that leads nowhere")
            XCTAssertEqual(place?.name, drawn.name)
        }
    }

    /// Street names are measured once each and kept by number, so no two may share
    /// one; and they are offered avenues first across the whole city.
    func testStreetNamesAreDistinctAndOfferedInRankOrder() {
        let city = DrawnMap.build(sheet: .city([.manhattan, .brooklyn]), size: size)

        XCTAssertEqual(Set(city.labels.map(\.id)).count, city.labels.count)
        let ranks = city.labels.map(\.kind.rawValue)
        XCTAssertEqual(ranks, ranks.sorted(), "every avenue before any side street")
        XCTAssertEqual(
            city.roads.count,
            DrawnMap.build(borough: .manhattan, size: size).roads.count
                + DrawnMap.build(borough: .brooklyn, size: size).roads.count
        )
    }

    /// The city is fitted to the same screen as one borough, so it is drawn smaller,
    /// and can be zoomed further in to reach the same streets.
    func testTheCityAsksForDetailInItsOwnTerms() {
        let borough = DrawnMap.build(borough: .manhattan, size: size)
        let city = DrawnMap.build(sheet: .city(Borough.drawn), size: size)

        XCTAssertEqual(borough.detail, 1)
        XCTAssertEqual(borough.zoomCeiling, MapCamera.range.upperBound)
        XCTAssertLessThan(city.detail, 1)
        XCTAssertGreaterThan(city.detail, 0.05)
        XCTAssertGreaterThan(city.zoomCeiling, MapCamera.range.upperBound)
        XCTAssertEqual(city.zoomCeiling * city.detail, MapCamera.range.upperBound, accuracy: 0.0001)
    }

    /// One borough's drawing is what it always was: a borough sheet asks nothing new.
    func testABoroughDrawingIsUnchanged() {
        let drawn = DrawnMap.build(borough: .manhattan, size: size)

        XCTAssertEqual(drawn.borough, .manhattan)
        XCTAssertEqual(drawn.sheet, .borough(.manhattan))
        XCTAssertEqual(drawn.neighborhoods.map(\.id), Array(drawn.neighborhoods.indices))
    }

    // MARK: - The camera

    func testTheCameraStopsAtItsDrawingsCeiling() {
        var camera = MapCamera()
        camera.ceiling = 40

        camera.setZoom(100)
        XCTAssertEqual(camera.zoom, 40)

        var borough = MapCamera()
        borough.setZoom(100)
        XCTAssertEqual(borough.zoom, MapCamera.range.upperBound, "a borough stops where it always did")
    }
}
