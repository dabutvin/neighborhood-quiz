import XCTest
@testable import NeighborhoodQuiz

/// The grid is arithmetic standing in for survey data, so the test that matters is
/// whether it lands on corners anybody can check. The tolerances are in metres and
/// they are loose on purpose: a hand-drawn map is allowed to be a block out, and the
/// job here is to catch a transform that has been broken, not to certify a survey.
final class ManhattanGridTests: XCTestCase {
    /// How far apart two coordinates are, in metres, on a plane laid over Manhattan.
    private func metres(_ a: Coordinate, _ b: Coordinate) -> Double {
        let north = (a.latitude - b.latitude) * MapProjection.metresPerDegreeLatitude
        let east = (a.longitude - b.longitude)
            * MapProjection.metresPerDegreeLatitude
            * cos(ManhattanGrid.anchor.latitude * .pi / 180)
        return (north * north + east * east).squareRoot()
    }

    func testTheAnchorIsItself() {
        let corner = ManhattanGrid.coordinate(street: 42, westOfFifth: 0)
        XCTAssertEqual(metres(corner, ManhattanGrid.anchor), 0, accuracy: 0.001)
    }

    func testTimesSquare() {
        // Seventh Avenue and Forty-Second Street.
        let corner = ManhattanGrid.coordinate(street: 42, westOfFifth: 1720)
        XCTAssertLessThan(metres(corner, Coordinate(-73.9870, 40.7560)), 100)
    }

    func testColumbusCircle() {
        // Eighth Avenue and Fifty-Ninth, the park's south-west corner.
        let corner = ManhattanGrid.coordinate(street: 59, westOfFifth: 2520)
        XCTAssertLessThan(metres(corner, Coordinate(-73.9819, 40.7681)), 150)
    }

    func testCentralParksNorthEastCorner() {
        // Fifth Avenue and a Hundred and Tenth — nearly four miles from the anchor,
        // which is where a wrong bearing would show up first.
        let corner = ManhattanGrid.coordinate(street: 110, westOfFifth: 0)
        XCTAssertLessThan(metres(corner, Coordinate(-73.9496, 40.7968)), 150)
    }

    func testHarlemAtParkAvenue() {
        // Park Avenue and a Hundred and Twenty-Fifth, under the viaduct.
        let corner = ManhattanGrid.coordinate(street: 125, westOfFifth: -840)
        XCTAssertLessThan(metres(corner, Coordinate(-73.9393, 40.8050)), 200)
    }

    func testTwentyBlocksIsAMile() {
        let south = ManhattanGrid.coordinate(street: 42, westOfFifth: 0)
        let north = ManhattanGrid.coordinate(street: 62, westOfFifth: 0)
        // 1609.34 metres, give or take what a spherical earth does to it.
        XCTAssertEqual(metres(south, north), 1609.34, accuracy: 5)
    }

    func testStreetsRunPerpendicularToAvenues() {
        let origin = ManhattanGrid.coordinate(street: 50, westOfFifth: 0)
        let upAnAvenue = ManhattanGrid.coordinate(street: 51, westOfFifth: 0)
        let alongAStreet = ManhattanGrid.coordinate(street: 50, westOfFifth: 800)

        let scale = cos(ManhattanGrid.anchor.latitude * .pi / 180)
        let avenue = (
            (upAnAvenue.longitude - origin.longitude) * scale,
            upAnAvenue.latitude - origin.latitude
        )
        let street = (
            (alongAStreet.longitude - origin.longitude) * scale,
            alongAStreet.latitude - origin.latitude
        )

        let dot = avenue.0 * street.0 + avenue.1 * street.1
        let magnitudes = (avenue.0 * avenue.0 + avenue.1 * avenue.1).squareRoot()
            * (street.0 * street.0 + street.1 * street.1).squareRoot()
        XCTAssertEqual(dot / magnitudes, 0, accuracy: 1e-9)
    }

    func testAvenuesLeanEastOfNorth() {
        let south = ManhattanGrid.coordinate(street: 42, westOfFifth: 0)
        let north = ManhattanGrid.coordinate(street: 62, westOfFifth: 0)
        XCTAssertGreaterThan(north.latitude, south.latitude, "Uptown is north")
        XCTAssertGreaterThan(north.longitude, south.longitude, "And a good way east of it")
    }
}
