import CoreGraphics
import XCTest
@testable import NeighborhoodQuiz

/// The same checks `BrooklynMapDataTests` makes, on the biggest file.
///
/// `queens.json` comes out of the same tool as the others, so what could go wrong with
/// it is what could go wrong with any of them — a filter that swallowed the borough, a
/// ring that folded over, a stump the speller left. What is Queens's own is the size of
/// the place: the most neighbourhoods of any borough, a dozen grids that never agreed
/// on a number, two long parkways that are highways and not avenues, and the Rockaways
/// hanging off the bottom of the frame on their own.
final class QueensMapDataTests: XCTestCase {
    private let map = BoroughMap.of(.queens)

    /// Queens's box, with a little water round it. Breezy Point is the south-west
    /// corner and Far Rockaway the south-east; Long Island City is the west, Little
    /// Neck the east, and the north is the East River off College Point.
    private let longitudes = -74.05...(-73.68)
    private let latitudes = 40.52...40.82

    func testTheFileIsThereAndHasLand() {
        let land = map.land
        XCTAssertFalse(land.isEmpty, "queens.json did not load")
        XCTAssertEqual(map.borough, .queens)

        let mainland = land.max { $0.count < $1.count } ?? []
        XCTAssertGreaterThan(mainland.count, 150, "Too coarse to read as Queens")
    }

    func testTheLandIsWhereQueensIs() {
        for ring in map.land {
            for point in ring {
                XCTAssertTrue(longitudes.contains(point.longitude), "\(point) is not in Queens")
                XCTAssertTrue(latitudes.contains(point.latitude), "\(point) is not in Queens")
            }
        }
    }

    func testTheShorelineDoesNotCrossItself() {
        // The same fold that once turned Wards Island into a bow tie. Every pair of
        // edges on the thinned ring is still a fraction of a second.
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

    /// The streets anybody would look for first: the boulevards that run the length
    /// of the borough and the avenues that cross them.
    func testTheStreetsPeopleKnowAreThere() {
        let named = Set(map.roads.map(\.name))
        for street in [
            "Queens Boulevard", "Northern Boulevard", "Jamaica Avenue", "Hillside Avenue",
            "Astoria Boulevard", "Rockaway Boulevard", "Woodhaven Boulevard", "Union Turnpike",
            "Francis Lewis Boulevard", "Cross Bay Boulevard",
        ] {
            XCTAssertTrue(named.contains(street), "\(street) is missing from the map")
        }
    }

    /// The Grand Central and the Long Island Expressway run the length of the borough
    /// and nobody gives directions by either. They are highways, and the roadway type
    /// is what keeps them out of the top rank — the same sorting that keeps the Belt
    /// Parkway off Brooklyn's and the FDR off Manhattan's.
    func testTheParkwaysAreNotAvenues() {
        let avenues = Set(map.roads.filter { $0.kind == .avenue }.map(\.name))
        XCTAssertFalse(avenues.contains("Grand Central Parkway"), "Grand Central Parkway should not rank as an avenue")
        XCTAssertFalse(avenues.contains("Long Island Expressway"), "Long Island Expressway should not rank as an avenue")
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

    func testFlushingMeadowsIsAmongTheGreens() {
        let parks = map.parks
        XCTAssertGreaterThan(parks.count, 10)
        XCTAssertTrue(parks.contains { $0.name.localizedCaseInsensitiveContains("Flushing Meadows") })
        for park in parks {
            XCTAssertGreaterThanOrEqual(park.ring.count, 3, "\(park.name) is not a shape")
        }
    }

    func testTheNeighbourhoodsAreNotOnTheMap() {
        // The point of the quiz is that the map does not tell you. A street may share a
        // name with a district — there is a Flushing Avenue and a Jamaica Avenue — so
        // this checks for road names that are *only* a neighbourhood.
        let forbidden = ["Astoria", "Flushing", "Jamaica", "Ridgewood", "Sunnyside", "Corona"]
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

    /// About sixty. Not an exact figure, because the pass over the tracts that decides
    /// what each place is called is a judgement and will be revised; a band catches a
    /// re-fetch that fell back to the city's own areas — there are far fewer — or one
    /// that kept every tract as its own place, of which Queens has more than anywhere.
    func testQueensIsDividedIntoNeighborhoods() {
        let areas = map.neighborhoods
        XCTAssertGreaterThanOrEqual(areas.count, 50, "Too few: has the tool fallen back to the NTAs?")
        XCTAssertLessThanOrEqual(areas.count, 75, "Too many to ask about, and too many to name")

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

    func testTheNeighborhoodsAreWhereQueensIs() {
        for area in map.neighborhoods {
            for point in area.rings.flatMap({ $0 }) {
                XCTAssertTrue(longitudes.contains(point.longitude), "\(area.name) is not in Queens")
                XCTAssertTrue(latitudes.contains(point.latitude), "\(area.name) is not in Queens")
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
    /// Elmhurst and Corona together, and Woodside with Sunnyside; a re-fetch that fell
    /// back to the NTA table would pass every other test in this file and fail this
    /// one many times over.
    func testTheNamesAreOnesAPlayerWouldSay() {
        for name in [
            "Astoria", "Long Island City", "Sunnyside", "Woodside", "Jackson Heights",
            "East Elmhurst", "Elmhurst", "Corona", "Flushing", "Forest Hills", "Rego Park",
            "Kew Gardens", "Kew Gardens Hills", "Briarwood", "Jamaica", "Hollis", "St. Albans",
            "Queens Village", "Cambria Heights", "Laurelton", "Rosedale", "Springfield Gardens",
            "Bayside", "Auburndale", "Whitestone", "College Point", "Fresh Meadows",
            "Douglaston", "Little Neck", "Bellerose", "Ridgewood", "Glendale", "Maspeth",
            "Middle Village", "Richmond Hill", "Woodhaven", "Ozone Park", "South Ozone Park",
            "Howard Beach", "Far Rockaway", "Rockaway Beach", "Breezy Point", "Broad Channel",
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
