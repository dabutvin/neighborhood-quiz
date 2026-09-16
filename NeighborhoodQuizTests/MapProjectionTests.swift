import CoreGraphics
import XCTest
@testable import NeighborhoodQuiz

final class MapProjectionTests: XCTestCase {
    private let size = CGSize(width: 400, height: 800)
    private var island: [Coordinate] { ManhattanMapData.land.flatMap { $0 } }

    private func fitted(padding: Double = 10) -> MapProjection {
        MapProjection(
            fitting: island,
            in: size,
            padding: padding,
            rotation: -ManhattanGeometry.gridBearingDegrees
        )
    }

    /// With the plane turned back by the grid's own bearing, an avenue must come out
    /// close to vertical. This is the whole reason the projection can be turned at all,
    /// and now it is checked against a real avenue rather than a generated one.
    func testTurningThePlaneStandsTheAvenuesUp() {
        let projection = fitted()
        let fifth = ManhattanMapData.roads.first { $0.name == "Fifth Avenue" && $0.carriesName }
        let points = projection.points(fifth?.coordinates ?? [])
        XCTAssertGreaterThanOrEqual(points.count, 2, "Fifth Avenue is missing from the map")

        let run = Polyline.heading(of: points, near: Polyline.midpoint(of: points))
        XCTAssertEqual(run, -.pi / 2, accuracy: 0.08, "Fifth Avenue should run up the page")
    }

    func testTurningThePlaneLaysTheCrossStreetsFlat() {
        let projection = fitted()
        let street = ManhattanMapData.roads.first { $0.name == "East 42nd Street" && $0.carriesName }
        let points = projection.points(street?.coordinates ?? [])
        XCTAssertGreaterThanOrEqual(points.count, 2, "42nd Street is missing from the map")

        let run = Polyline.heading(of: points, near: Polyline.midpoint(of: points))
        XCTAssertEqual(run, 0, accuracy: 0.12, "A cross street should lie flat")
    }

    func testTheFitStaysInsideThePaddingAndTouchesOneEdge() {
        let padding = 12.0
        let points = fitted(padding: padding).points(island)

        let minX = points.map { Double($0.x) }.min() ?? 0
        let maxX = points.map { Double($0.x) }.max() ?? 0
        let minY = points.map { Double($0.y) }.min() ?? 0
        let maxY = points.map { Double($0.y) }.max() ?? 0

        XCTAssertGreaterThanOrEqual(minX, padding - 0.001)
        XCTAssertGreaterThanOrEqual(minY, padding - 0.001)
        XCTAssertLessThanOrEqual(maxX, Double(size.width) - padding + 0.001)
        XCTAssertLessThanOrEqual(maxY, Double(size.height) - padding + 0.001)

        // Manhattan is far taller than it is wide once stood up, so the fit is the
        // height's, and the island should reach both ends of it.
        XCTAssertEqual(minY, padding, accuracy: 0.001)
        XCTAssertEqual(maxY, Double(size.height) - padding, accuracy: 0.001)
    }

    func testTheFitIsCentredAcrossTheSlackDimension() {
        let xs = fitted(padding: 12).points(island).map { Double($0.x) }
        let centre = ((xs.min() ?? 0) + (xs.max() ?? 0)) / 2
        XCTAssertEqual(centre, Double(size.width) / 2, accuracy: 0.001)
    }

    func testAnUnturnedProjectionPutsNorthUpAndEastRight() {
        let box = [Coordinate(-74, 40.7), Coordinate(-73.9, 40.8)]
        let projection = MapProjection(
            fitting: box,
            in: CGSize(width: 100, height: 100),
            padding: 0,
            rotation: 0
        )
        let southWest = projection.point(box[0])
        let northEast = projection.point(box[1])

        XCTAssertLessThan(southWest.x, northEast.x)
        XCTAssertGreaterThan(southWest.y, northEast.y)
    }

    func testAnEmptyFitDoesNotDivideByZero() {
        let projection = MapProjection(
            fitting: [],
            in: CGSize(width: 100, height: 100),
            padding: 0,
            rotation: 0
        )
        let point = projection.point(Coordinate(-74, 40.7))
        XCTAssertTrue(point.x.isFinite && point.y.isFinite)
    }
}
