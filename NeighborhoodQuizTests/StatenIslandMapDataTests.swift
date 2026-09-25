import CoreGraphics
import XCTest
@testable import NeighborhoodQuiz

/// The same checks `BrooklynMapDataTests` makes, on the last file.
///
/// `staten-island.json` comes out of the same tool as the others, so what could go
/// wrong with it is what could go wrong with any of them — a filter that swallowed the
/// borough, a ring that folded over, a stump the speller left. What is Staten Island's
/// own: it is an island again, like Manhattan, with a shoreline that is all shoreline;
/// it has no grid and its long roads follow the shore and the ridge instead; and the
/// Staten Island Expressway cuts it in half and is not an avenue.
final class StatenIslandMapDataTests: XCTestCase {
    private let map = BoroughMap.of(.statenIsland)

    /// Staten Island's box, with a little water round it. Tottenville is the south-west
    /// corner and St. George the north-east; the Arthur Kill is the west and the
    /// Narrows the east.
    private let longitudes = -74.26...(-74.04)
    private let latitudes = 40.49...40.66

    func testTheFileIsThereAndHasLand() {
        let land = map.land
        XCTAssertFalse(land.isEmpty, "staten-island.json did not load")
        XCTAssertEqual(map.borough, .statenIsland)

        let island = land.max { $0.count < $1.count } ?? []
        XCTAssertGreaterThan(island.count, 150, "Too coarse to read as Staten Island")
    }

    func testTheLandIsWhereStatenIslandIs() {
        for ring in map.land {
            for point in ring {
                XCTAssertTrue(longitudes.contains(point.longitude), "\(point) is not on Staten Island")
                XCTAssertTrue(latitudes.contains(point.latitude), "\(point) is not on Staten Island")
            }
        }
    }

    func testTheShorelineDoesNotCrossItself() {
        // The same fold that once turned Wards Island into a bow tie. Every pair of
        // edges on the thinned ring is still a fraction of a second.
        let island = map.land.max { $0.count < $1.count } ?? []
        let points = island.map { CGPoint(x: $0.longitude * 10_000, y: $0.latitude * 10_000) }

        for i in 0..<points.count {
            let a = points[i]
            let b = points[(i + 1) % points.count]
            for j in (i + 1)..<points.count {
                if j == i || j == (i + 1) % points.count || (j + 1) % points.count == i { continue }
                XCTAssertNil(
                    Polyline.crossing(a, b, points[j], points[(j + 1) % points.count]),
                    "Shoreline edge \(i) crosses edge \(j)"
                )
            }
        }
    }

    func testEveryRoadHasSomethingToDrawAndAName() {
        let roads = map.roads
        XCTAssertGreaterThan(roads.count, 1_000, "The whole borough should be in here")
        for road in roads {
            XCTAssertGreaterThanOrEqual(road.coordinates.count, 2, "\(road.name) has no line")
            XCTAssertFalse(road.name.isEmpty)
        }
    }

    func testEveryStreetIsNamedExactlyOnce() {
        var carriers: [String: Int] = [:]
        for road in map.roads where road.carriesName {
            carriers[road.name, default: 0] += 1
        }
        let doubled = carriers.filter { $0.value > 1 }
        XCTAssertTrue(doubled.isEmpty, "written more than once: \(doubled.keys.sorted())")

        let named = Set(map.roads.map(\.name))
        XCTAssertEqual(carriers.count, named.count, "every street gets its name somewhere")
    }

    /// The streets anybody would look for first: Hylan along the east shore, Richmond
    /// Terrace along the north, Arthur Kill Road along the west, and the few that cross
    /// the island between them.
    func testTheStreetsPeopleKnowAreThere() {
        let named = Set(map.roads.map(\.name))
        for street in [
            "Hylan Boulevard", "Victory Boulevard", "Richmond Terrace", "Arthur Kill Road",
            "Amboy Road", "Forest Avenue", "Richmond Avenue", "Bay Street", "Clove Road",
            "Richmond Road",
        ] {
            XCTAssertTrue(named.contains(street), "\(street) is missing from the map")
        }
    }

    /// The Staten Island Expressway is the way across the island and nobody gives
    /// directions by it. It is a highway, and the roadway type is what keeps it out of
    /// the top rank — the same sorting that keeps the Belt Parkway off Brooklyn's and
    /// the FDR off Manhattan's.
    func testTheExpresswayIsNotAnAvenue() {
        let avenues = Set(map.roads.filter { $0.kind == .avenue }.map(\.name))
        XCTAssertFalse(avenues.contains("Staten Island Expressway"), "Staten Island Expressway should not rank as an avenue")
        XCTAssertFalse(avenues.isEmpty, "But something should")
    }

    func testTheNamesAreSpeltTheWayPeopleWriteThem() {
        for name in Set(map.roads.map(\.name)) {
            XCTAssertFalse(name.contains("  "), "\(name) has the city's double space in it")
            XCTAssertEqual(name, name.trimmingCharacters(in: .whitespaces))
            for stump in [" St", " Ave", " Pl", " Blvd", " Dr", " Pkwy", " Hl", " Dy"] {
                XCTAssertFalse(name.hasSuffix(stump), "\(name) was not spelled out")
            }
        }
    }

    func testTheRampsAndServiceRoadsAreLeftOut() {
        for road in map.roads {
            let name = road.name.uppercased()
            for plumbing in [" EN ", " EX ", " NB ", " SB ", "OPAS", "RAMP"] {
                XCTAssertFalse(name.contains(plumbing), "\(road.name) is highway plumbing, not a street")
            }
        }
    }

    /// The middle of the island is one green after another — Clove Lakes, LaTourette,
    /// the Greenbelt that joins them — and the city files the pieces under several
    /// names, so any one of them is enough to say the greens came through.
    func testTheGreenbeltIsAmongTheGreens() {
        let parks = map.parks
        XCTAssertGreaterThan(parks.count, 10)
        XCTAssertTrue(parks.contains { park in
            ["Clove Lakes", "Latourette", "Greenbelt"].contains { park.name.localizedCaseInsensitiveContains($0) }
        }, "None of Clove Lakes, LaTourette or the Greenbelt is among the greens")
        for park in parks {
            XCTAssertGreaterThanOrEqual(park.ring.count, 3, "\(park.name) is not a shape")
        }
    }

    func testTheNeighbourhoodsAreNotOnTheMap() {
        // The point of the quiz is that the map does not tell you. A street may share a
        // name with a district — there is a Rosebank Place and a Travis Avenue — so
        // this checks for road names that are *only* a neighbourhood.
        let forbidden = ["Tottenville", "Stapleton", "Rosebank", "Travis", "Annadale"]
        for road in map.roads {
            for name in forbidden {
                XCTAssertNotEqual(road.name.lowercased(), name.lowercased())
            }
        }
    }

    func testTheSourceIsCredited() {
        XCTAssertTrue(map.source.contains("NYC Open Data"))
    }

    // MARK: - The neighbourhoods

    /// About thirty. Not an exact figure, because the pass over the tracts that decides
    /// what each place is called is a judgement and will be revised; a band catches a
    /// re-fetch that fell back to the city's own areas — there are far fewer — or one
    /// that kept every tract as its own place.
    func testStatenIslandIsDividedIntoNeighborhoods() {
        let areas = map.neighborhoods
        XCTAssertGreaterThanOrEqual(areas.count, 25, "Too few: has the tool fallen back to the NTAs?")
        XCTAssertLessThanOrEqual(areas.count, 45, "Too many to ask about, and too many to name")

        for area in areas {
            XCTAssertFalse(area.name.isEmpty)
            XCTAssertFalse(area.rings.isEmpty, "\(area.name) has no shape")
            for ring in area.rings {
                XCTAssertGreaterThanOrEqual(ring.count, 3, "\(area.name) has a ring that is a line")
            }
        }

        let names = areas.map(\.name)
        XCTAssertEqual(Set(names).count, names.count, "Two neighborhoods share a name")
    }

    func testTheNeighborhoodsAreWhereStatenIslandIs() {
        for area in map.neighborhoods {
            for point in area.rings.flatMap({ $0 }) {
                XCTAssertTrue(longitudes.contains(point.longitude), "\(area.name) is not on Staten Island")
                XCTAssertTrue(latitudes.contains(point.latitude), "\(area.name) is not on Staten Island")
            }
        }
    }

    func testNoNeighborhoodCrossesItself() {
        for area in map.neighborhoods {
            for (index, ring) in area.rings.enumerated() {
                let points = ring.map { CGPoint(x: $0.longitude * 10_000, y: $0.latitude * 10_000) }
                for i in 0..<points.count {
                    let a = points[i]
                    let b = points[(i + 1) % points.count]
                    for j in (i + 1)..<points.count {
                        if j == i || j == (i + 1) % points.count || (j + 1) % points.count == i { continue }
                        XCTAssertNil(
                            Polyline.crossing(a, b, points[j], points[(j + 1) % points.count]),
                            "\(area.name) ring \(index) folds over itself at \(i)/\(j)"
                        )
                    }
                }
            }
        }
    }

    /// The names a player would say, and none of the city's compounds. The city files
    /// Tottenville with Charleston and Rossville, and Todt Hill with Emerson Hill and
    /// Dongan Hills; a re-fetch that fell back to the NTA table would pass every other
    /// test in this file and fail this one many times over.
    func testTheNamesAreOnesAPlayerWouldSay() {
        for name in [
            "St. George", "New Brighton", "Tompkinsville", "Stapleton", "Rosebank",
            "West Brighton", "Port Richmond", "Mariners Harbor", "Westerleigh", "Todt Hill",
            "Dongan Hills", "South Beach", "Midland Beach", "New Dorp", "Oakwood",
            "Great Kills", "Eltingville", "Annadale", "Huguenot", "Tottenville", "Charleston",
            "Rossville", "Arden Heights", "New Springville", "Bulls Head", "Willowbrook",
            "Travis",
        ] {
            XCTAssertNotNil(named(name), "\(name) is missing from the map")
        }

        // A hyphen *and* a space is the shape of an NTA name, not of a place.
        for area in map.neighborhoods {
            XCTAssertFalse(
                area.name.contains("-") && area.name.contains(" "),
                "\(area.name) still reads like an NTA rather than like a place"
            )
            XCTAssertFalse(area.name.contains("("), "\(area.name) still has a qualifier on it")
        }
    }

    private func named(_ name: String) -> BoroughMap.Neighborhood? {
        map.neighborhoods.first { $0.name == name }
    }
}
