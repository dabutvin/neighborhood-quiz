import CoreGraphics
import XCTest
@testable import NeighborhoodQuiz

/// The same checks `ManhattanMapDataTests` makes, on Brooklyn's file.
///
/// `brooklyn.json` comes out of the same tool with a different borough on the command
/// line, so most of what could go wrong with it is what could go wrong with Manhattan's
/// — a filter that swallowed the borough, a ring that folded over, a stump the speller
/// left. What is Brooklyn's own is the shape of the place: bigger, more neighbourhoods,
/// numbered avenues in figures rather than words, and a Belt Parkway that is the longest
/// road in the borough and not an avenue at all.
final class BrooklynMapDataTests: XCTestCase {
    private let map = BoroughMap.of(.brooklyn)

    /// Brooklyn's box, with a little water round it. Coney Island is the south end,
    /// Greenpoint the north; the Narrows are the west and the Queens line the east.
    private let longitudes = -74.06...(-73.82)
    private let latitudes = 40.55...40.75

    func testTheFileIsThereAndHasLand() {
        let land = map.land
        XCTAssertFalse(land.isEmpty, "brooklyn.json did not load")
        XCTAssertEqual(map.borough, .brooklyn)

        let mainland = land.max { $0.count < $1.count } ?? []
        XCTAssertGreaterThan(mainland.count, 150, "Too coarse to read as Brooklyn")
    }

    func testTheLandIsWhereBrooklynIs() {
        for ring in map.land {
            for point in ring {
                XCTAssertTrue(longitudes.contains(point.longitude), "\(point) is not in Brooklyn")
                XCTAssertTrue(latitudes.contains(point.latitude), "\(point) is not in Brooklyn")
            }
        }
    }

    func testTheShorelineDoesNotCrossItself() {
        // The same fold that once turned Wards Island into a bow tie. Brooklyn's ring
        // is longer than Manhattan's, but it is the thinned one, and every pair of
        // edges on it is still a fraction of a second.
        let mainland = map.land.max { $0.count < $1.count } ?? []
        let points = mainland.map { CGPoint(x: $0.longitude * 10_000, y: $0.latitude * 10_000) }

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

    /// The streets anybody would look for first. Numbered avenues are in figures here —
    /// Brooklyn writes "86th Street" and "Avenue U", not "Eighty-sixth" — and North 7th
    /// is Williamsburg's own grid, which has a compass point in front of every number.
    func testTheStreetsPeopleKnowAreThere() {
        let named = Set(map.roads.map(\.name))
        for street in [
            "Flatbush Avenue", "Atlantic Avenue", "Bedford Avenue", "Ocean Parkway",
            "Eastern Parkway", "Kings Highway", "Nostrand Avenue", "Fulton Street",
            "Avenue U", "86th Street", "North 7th Street",
        ] {
            XCTAssertTrue(named.contains(street), "\(street) is missing from the map")
        }
    }

    /// The Belt Parkway is the longest road in the borough and nobody gives directions
    /// by it. It is a highway, and the roadway type is what keeps it out of the top
    /// rank — the same sorting that keeps the FDR off Manhattan's.
    func testTheBeltParkwayIsNotAnAvenue() {
        let avenues = Set(map.roads.filter { $0.kind == .avenue }.map(\.name))
        XCTAssertFalse(avenues.contains("Belt Parkway"), "Belt Parkway should not rank as an avenue")
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

    func testProspectParkIsAmongTheGreens() {
        let parks = map.parks
        XCTAssertGreaterThan(parks.count, 10)
        XCTAssertTrue(parks.contains { $0.name.localizedCaseInsensitiveContains("Prospect Park") })
        // Not in the parks table — the city does not run it — but four hundred acres of
        // trees in the middle of the borough, and a blank hole in the map without it.
        XCTAssertTrue(parks.contains { $0.name == "Green-Wood Cemetery" }, "Green-Wood is green")
        for park in parks {
            XCTAssertGreaterThanOrEqual(park.ring.count, 3, "\(park.name) is not a shape")
        }
    }

    func testTheNeighbourhoodsAreNotOnTheMap() {
        // The point of the quiz is that the map does not tell you. A street may share a
        // name with a district, so this checks for road names that are *only* a
        // neighbourhood.
        let forbidden = ["Park Slope", "Williamsburg", "Greenpoint", "Bushwick", "Red Hook", "DUMBO"]
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

    /// About fifty. Not an exact figure, because the pass over the tracts that decides
    /// what each place is called is a judgement and will be revised; a band catches a
    /// re-fetch that fell back to the city's own areas — there are far fewer — or one
    /// that kept every tract as its own place.
    func testBrooklynIsDividedIntoNeighborhoods() {
        let areas = map.neighborhoods
        XCTAssertGreaterThanOrEqual(areas.count, 45, "Too few: has the tool fallen back to the NTAs?")
        XCTAssertLessThanOrEqual(areas.count, 60, "Too many to ask about, and too many to name")

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

    func testTheNeighborhoodsAreWhereBrooklynIs() {
        for area in map.neighborhoods {
            for point in area.rings.flatMap({ $0 }) {
                XCTAssertTrue(longitudes.contains(point.longitude), "\(area.name) is not in Brooklyn")
                XCTAssertTrue(latitudes.contains(point.latitude), "\(area.name) is not in Brooklyn")
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
    /// Carroll Gardens, Cobble Hill, Gowanus and Red Hook as one area with all four
    /// names hyphenated together; a re-fetch that fell back to the NTA table would pass
    /// every other test in this file and fail this one four times over.
    func testTheNamesAreOnesAPlayerWouldSay() {
        for name in [
            "Park Slope", "Williamsburg", "Greenpoint", "Bay Ridge", "Coney Island",
            "Bushwick", "Red Hook", "DUMBO", "Brooklyn Heights", "Bedford-Stuyvesant",
            "Crown Heights", "Flatbush", "Sheepshead Bay", "Canarsie", "Bensonhurst",
            "Brighton Beach", "Fort Greene", "Sunset Park", "East New York", "Gowanus",
            "Carroll Gardens", "Cobble Hill", "Prospect Heights", "Clinton Hill",
            "Dyker Heights", "Borough Park", "Midwood", "Brownsville", "Marine Park",
            "Mill Basin", "Gerritsen Beach", "Manhattan Beach", "Windsor Terrace",
            "Kensington",
        ] {
            XCTAssertNotNil(named(name), "\(name) is missing from the map")
        }

        // Bedford-Stuyvesant has a hyphen and no space, which is how it is written; a
        // hyphen *and* a space is the shape of an NTA name, not of a place.
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
