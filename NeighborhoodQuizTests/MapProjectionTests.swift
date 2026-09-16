import CoreGraphics
import XCTest
@testable import NeighborhoodQuiz

final class MapProjectionTests: XCTestCase {
    private let size = CGSize(width: 400, height: 800)

    /// With the plane turned back by the grid's own bearing, an avenue must come out
    /// vertical. This is the whole reason the projection can be turned at all.
    func testTurningThePlaneStandsTheAvenuesUp() {
        let projection = MapProjection(
            fitting: ManhattanMapData.shoreline,
            in: size,
            padding: 10,
            rotation: -ManhattanGrid.bearingDegrees
        )

        let downtown = projection.point(ManhattanGrid.coordinate(street: 20, westOfFifth: 0))
        let uptown = projection.point(ManhattanGrid.coordinate(street: 100, westOfFifth: 0))

        XCTAssertEqual(Double(downtown.x), Double(uptown.x), accuracy: 1.0)
        XCTAssertLessThan(uptown.y, downtown.y, "Uptown is up the page")
    }

    func testTurningThePlaneLaysTheCrossStreetsFlat() {
        let projection = MapProjection(
            fitting: ManhattanMapData.shoreline,
            in: size,
            padding: 10,
            rotation: -ManhattanGrid.bearingDegrees
        )

        let east = projection.point(ManhattanGrid.coordinate(street: 50, westOfFifth: -2000))
        let west = projection.point(ManhattanGrid.coordinate(street: 50, westOfFifth: 4000))

        XCTAssertEqual(Double(east.y), Double(west.y), accuracy: 1.0)
        XCTAssertLessThan(west.x, east.x, "West of Fifth is to the left")
    }

    func testTheFitStaysInsideThePaddingAndTouchesOneEdge() {
        let padding = 12.0
        let projection = MapProjection(
            fitting: ManhattanMapData.shoreline,
            in: size,
            padding: padding,
            rotation: -ManhattanGrid.bearingDegrees
        )
        let points = projection.points(ManhattanMapData.shoreline)

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
        let projection = MapProjection(
            fitting: ManhattanMapData.shoreline,
            in: size,
            padding: 12,
            rotation: -ManhattanGrid.bearingDegrees
        )
        let xs = projection.points(ManhattanMapData.shoreline).map { Double($0.x) }
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
