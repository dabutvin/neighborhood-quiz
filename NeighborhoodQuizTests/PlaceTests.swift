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

    /// Checked on every drawn borough, not just Manhattan: Brooklyn is the one whose
    /// file has a few more shapes in it, and the one a future re-fetch is likelier to
    /// reorder.
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
    /// the whole city is the two lists end to end with nothing shared between them.
    func testTheSameNumberInTwoBoroughsIsTwoPlaces() {
        XCTAssertNotEqual(Place(.manhattan, 0), Place(.brooklyn, 0))

        let city = Borough.drawn.flatMap(Place.all(in:))
        XCTAssertEqual(city.count, Place.all(in: .manhattan).count + Place.all(in: .brooklyn).count)
        XCTAssertEqual(Set(city).count, city.count)
    }
}
