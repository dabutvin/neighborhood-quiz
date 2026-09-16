import CoreGraphics
import XCTest
@testable import NeighborhoodQuiz

final class ManhattanMapDataTests: XCTestCase {
    func testTheShorelineIsAPlausibleIsland() {
        let shore = ManhattanMapData.shoreline
        XCTAssertGreaterThan(shore.count, 20, "Too few corners to be Manhattan")

        for point in shore {
            XCTAssertTrue((-74.03...(-73.90)).contains(point.longitude), "\(point) is not in the harbour")
            XCTAssertTrue((40.69...40.89).contains(point.latitude), "\(point) is not in the harbour")
        }

        // Traced clockwise up the Hudson: the first point is the southern tip and the
        // northernmost is somewhere in the middle of the list, at Inwood.
        let southernmost = shore.min { $0.latitude < $1.latitude }
        XCTAssertEqual(southernmost?.latitude, shore.first?.latitude)
    }

    func testTheShorelineDoesNotCrossItself() {
        // A ring that crosses itself makes nonsense of every clip taken against it,
        // and it is the sort of thing a single fat-fingered digit introduces.
        let shore = ManhattanMapData.shoreline
        let points = shore.map { CGPoint(x: $0.longitude * 10_000, y: $0.latitude * 10_000) }

        for i in 0..<points.count {
            let a = points[i]
            let b = points[(i + 1) % points.count]
            for j in (i + 1)..<points.count {
                // Neighbouring edges share a corner, which is not a crossing.
                if j == i || j == (i + 1) % points.count || (j + 1) % points.count == i { continue }
                let c = points[j]
                let d = points[(j + 1) % points.count]
                XCTAssertNil(
                    Shoreline.crossing(a, b, c, d),
                    "Shoreline edge \(i) crosses edge \(j)"
                )
            }
        }
    }

    func testCentralParkSitsBetweenItsFourCorners() {
        let park = ManhattanMapData.centralPark
        XCTAssertEqual(park.count, 4)
        XCTAssertTrue(
            Shoreline.contains(
                ManhattanMapData.shoreline.map { CGPoint(x: $0.longitude, y: $0.latitude) },
                CGPoint(x: park[0].longitude, y: park[0].latitude)
            ),
            "The park is on the island"
        )
    }

    func testEveryRoadHasSomethingToDraw() {
        for road in ManhattanMapData.roads {
            XCTAssertGreaterThanOrEqual(road.coordinates.count, 2, "\(road.name) has no line")
            XCTAssertFalse(road.name.isEmpty)
            XCTAssertGreaterThanOrEqual(road.labelMinZoom, 1)
        }
    }

    func testTheParkSplitsTheStreetsThatRunIntoIt() {
        XCTAssertEqual(ManhattanMapData.spans(forStreet: 80).count, 2, "Eightieth is cut by the park")
        XCTAssertEqual(ManhattanMapData.spans(forStreet: 59).count, 1, "Fifty-Ninth runs along its foot")
        XCTAssertEqual(ManhattanMapData.spans(forStreet: 110).count, 1, "A Hundred and Tenth along its head")
        XCTAssertEqual(ManhattanMapData.spans(forStreet: 42).count, 1)
    }

    func testTheStreetsBelowFourteenthKeepToTheEastSide() {
        let downtown = ManhattanMapData.spans(forStreet: 5)
        XCTAssertEqual(downtown.count, 1)
        XCTAssertLessThan(downtown[0].to, 0, "Nothing west of Fifth Avenue exists down there")
    }

    func testTheSpansOvershootTheIslandOnPurpose() {
        // They are meant to be cut by the shoreline, so they must start out too long:
        // Manhattan is nowhere near ten thousand feet wide either side of Fifth.
        for number in [20, 42, 80, 130] {
            for span in ManhattanMapData.spans(forStreet: number) {
                XCTAssertGreaterThan(span.to - span.from, 2_500)
            }
        }
    }

    func testEveryAvenueIsNamedOnItself() {
        for avenue in ManhattanMapData.avenues {
            XCTAssertLessThan(avenue.from, avenue.to, "\(avenue.name) runs backwards")
            XCTAssertTrue(
                (avenue.from...avenue.to).contains(avenue.labelStreet),
                "\(avenue.name) is named off the end of itself"
            )
        }
    }

    func testTheAvenuesAreInOrderFromTheEastRiverToTheHudson() {
        let midtown = ManhattanMapData.avenues.filter { $0.from <= 40 && $0.to >= 40 }
        let offsets = midtown.map(\.westOfFifth)
        XCTAssertEqual(offsets, offsets.sorted(), "The avenue table reads east to west")
        XCTAssertTrue(midtown.contains { $0.name == "Fifth Avenue" && $0.westOfFifth == 0 })
    }

    func testTheHeadlineStreetsAreAllMajorOnes() {
        XCTAssertTrue(ManhattanMapData.headlineCrossStreets.isSubset(of: ManhattanMapData.majorCrossStreets))
        for number in ManhattanMapData.majorCrossStreets {
            XCTAssertTrue(ManhattanMapData.crossStreetNumbers.contains(number), "\(number) is not drawn")
        }
    }

    func testNamesAppearInWavesAsTheMapIsPulledIn() {
        let roads = ManhattanMapData.roads
        func minZoom(_ name: String) -> Double? { roads.first { $0.name == name }?.labelMinZoom }

        XCTAssertEqual(minZoom("Fifth Avenue"), 1)
        XCTAssertEqual(minZoom("Broadway"), 1)
        XCTAssertEqual(minZoom("42nd Street"), 1)
        XCTAssertGreaterThan(minZoom("York Avenue") ?? 0, 1)
        XCTAssertGreaterThan(minZoom("41st") ?? 0, 2, "The fine streets come last")
    }

    func testOrdinals() {
        XCTAssertEqual(ManhattanMapData.ordinal(1), "1st")
        XCTAssertEqual(ManhattanMapData.ordinal(2), "2nd")
        XCTAssertEqual(ManhattanMapData.ordinal(3), "3rd")
        XCTAssertEqual(ManhattanMapData.ordinal(4), "4th")
        XCTAssertEqual(ManhattanMapData.ordinal(11), "11th")
        XCTAssertEqual(ManhattanMapData.ordinal(12), "12th")
        XCTAssertEqual(ManhattanMapData.ordinal(13), "13th")
        XCTAssertEqual(ManhattanMapData.ordinal(21), "21st")
        XCTAssertEqual(ManhattanMapData.ordinal(42), "42nd")
        XCTAssertEqual(ManhattanMapData.ordinal(103), "103rd")
        XCTAssertEqual(ManhattanMapData.ordinal(111), "111th")
        XCTAssertEqual(ManhattanMapData.ordinal(125), "125th")
    }

    func testBroadwayCutsAcrossTheGridRatherThanRunningWithIt() {
        let broadway = ManhattanMapData.broadway
        XCTAssertGreaterThan(broadway.count, 10)

        // At Bowling Green it is west of Fifth Avenue's line; by Times Square it has
        // crossed it and by Ninety-Sixth it is well west again. What matters here is
        // that it is not parallel to anything: its bearing must change along its length.
        func bearing(_ a: Coordinate, _ b: Coordinate) -> Double {
            atan2(b.longitude - a.longitude, b.latitude - a.latitude)
        }
        let first = bearing(broadway[0], broadway[1])
        let last = bearing(broadway[broadway.count - 2], broadway[broadway.count - 1])
        XCTAssertGreaterThan(abs(first - last), 0.05, "Broadway bends")
    }

    func testTheNeighbourhoodsAreNotOnTheMapYet() {
        // The point of the quiz is that the map does not tell you. If a neighbourhood
        // name ever lands in the road table by accident, this catches it.
        let forbidden = ["SoHo", "Harlem", "Tribeca", "Chelsea", "Midtown", "Village", "Inwood"]
        for road in ManhattanMapData.roads {
            for name in forbidden {
                XCTAssertFalse(
                    road.name.localizedCaseInsensitiveContains(name),
                    "\(road.name) names a neighbourhood"
                )
            }
        }
    }
}
