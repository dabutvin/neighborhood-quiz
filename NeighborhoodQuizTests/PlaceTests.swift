import CoreGraphics
import XCTest
@testable import NeighborhoodQuiz

/// The one fact `Place` rests on: a place's id is its index in the borough's data, and
/// that is the id the drawing gives the same shape. The round draws its questions from
/// the data and the map answers taps with the drawing, and if the two ever numbered a
/// neighbourhood differently the game would ask for Harlem and settle Inwood.
@MainActor
final class PlaceTests: XCTestCase {
    private let size = CGSize(width: 393, height: 852)

    /// Checked on every drawn borough, which is all five now, not just Manhattan: the
    /// other files have more shapes in them, and a future re-fetch of any one of them
    /// is likelier to reorder it than Manhattan's forty are.
    func testAPlaceIsItsIndexOnTheDrawing() {
        for borough in Borough.drawn {
            let drawn = DrawnMap.build(borough: borough, size: size)
            let data = BoroughMap.of(borough).neighborhoods
            XCTAssertEqual(drawn.neighborhoods.count, data.count, "\(borough.name) did not draw every shape")

            for (index, area) in drawn.neighborhoods.enumerated() {
                XCTAssertEqual(area.id, index, "\(borough.name): \(area.name) is out of order")
                XCTAssertEqual(
                    Place(borough, area.id).name, area.name,
                    "\(borough.name): id \(area.id) is two different places"
                )
            }
        }
    }

    func testAllInABoroughIsEveryPlaceOnceInOrder() {
        for borough in Borough.drawn {
            let places = Place.all(in: borough)
            let data = BoroughMap.of(borough).neighborhoods

            XCTAssertEqual(places.count, data.count)
            XCTAssertEqual(places.map(\.id), Array(data.indices), "in the file's order")
            XCTAssertEqual(Set(places).count, places.count, "no place twice")
            XCTAssertTrue(places.allSatisfy { $0.borough == borough })
        }
        XCTAssertEqual(Place.all(in: .manhattan).count, 40, "fetch_map_data.py names forty")
    }

    func testANameIsReadOffTheData() {
        XCTAssertTrue(Place.all(in: .manhattan).map(\.name).contains("SoHo"))
        XCTAssertTrue(Place.all(in: .brooklyn).map(\.name).contains("Park Slope"))
        XCTAssertFalse(Place.all(in: .brooklyn).map(\.name).contains("SoHo"))
    }

    /// The whole reason for the type: the same number on two maps is two places, and
    /// the whole city is the five lists end to end with nothing shared between them.
    func testTheSameNumberInTwoBoroughsIsTwoPlaces() {
        XCTAssertNotEqual(Place(.manhattan, 0), Place(.brooklyn, 0))
        XCTAssertNotEqual(Place(.queens, 0), Place(.bronx, 0))

        let city = Borough.drawn.flatMap(Place.all(in:))
        XCTAssertEqual(city.count, Borough.drawn.map { Place.all(in: $0).count }.reduce(0, +))
        XCTAssertEqual(Set(city).count, city.count)
    }
}
