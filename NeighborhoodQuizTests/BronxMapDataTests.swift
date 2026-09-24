import CoreGraphics
import XCTest
@testable import NeighborhoodQuiz

/// The same checks `BrooklynMapDataTests` makes, on the Bronx's file.
///
/// `bronx.json` comes out of the same tool as the others, so what could go wrong with
/// it is what could go wrong with any of them — a filter that swallowed the borough, a
/// ring that folded over, a stump the speller left. What is the Bronx's own: it is the
/// one piece of the city on the mainland, so its "shoreline" is mostly a county line;
/// Manhattan's numbered streets carry on over the Harlem River and then give out; and
/// three expressways run through it that are the longest roads in the borough and not
/// avenues at all.
final class BronxMapDataTests: XCTestCase {
    private let map = BoroughMap.of(.bronx)

    /// The Bronx's box, with a little water round it. Port Morris is the south end and
    /// Woodlawn the north; Spuyten Duyvil is the west and City Island the east.
    private let longitudes = -73.94...(-73.74)
    private let latitudes = 40.78...40.92

    func testTheFileIsThereAndHasLand() {
        let land = map.land
        XCTAssertFalse(land.isEmpty, "bronx.json did not load")
        XCTAssertEqual(map.borough, .bronx)

        let mainland = land.max { $0.count < $1.count } ?? []
        XCTAssertGreaterThan(mainland.count, 150, "Too coarse to read as the Bronx")
    }

    func testTheLandIsWhereTheBronxIs() {
        for ring in map.land {
            for point in ring {
                XCTAssertTrue(longitudes.contains(point.longitude), "\(point) is not in the Bronx")
                XCTAssertTrue(latitudes.contains(point.latitude), "\(point) is not in the Bronx")
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

    /// The streets anybody would look for first. Fordham Road and Tremont Avenue are
    /// each filed by the city as East and West halves, and the speller may keep the
    /// compass point or may not; either spelling is the street, so either is accepted.
    /// Broadway is here too — it is the same Broadway, and it does not stop at the
    /// Harlem River.
    func testTheStreetsPeopleKnowAreThere() {
        let named = Set(map.roads.map(\.name))
        for street in [
            "Grand Concourse", "Jerome Avenue", "Webster Avenue", "White Plains Road",
            "Boston Road", "Bruckner Boulevard", "Southern Boulevard", "Broadway",
        ] {
            XCTAssertTrue(named.contains(street), "\(street) is missing from the map")
        }
        for (plain, east) in [("Fordham Road", "East Fordham Road"), ("Tremont Avenue", "East Tremont Avenue")] {
            XCTAssertTrue(named.contains(plain) || named.contains(east), "\(plain) is missing from the map")
        }
    }

    /// The Major Deegan, the Cross Bronx and the Bronx River Parkway are among the
    /// longest roads in the borough and nobody gives directions by any of them. They
    /// are highways, and the roadway type is what keeps them out of the top rank — the
    /// same sorting that keeps the Belt Parkway off Brooklyn's and the FDR off
    /// Manhattan's.
    func testTheExpresswaysAreNotAvenues() {
        let avenues = Set(map.roads.filter { $0.kind == .avenue }.map(\.name))
        for pretender in ["Major Deegan Expressway", "Cross Bronx Expressway", "Bronx River Parkway"] {
            XCTAssertFalse(avenues.contains(pretender), "\(pretender) should not rank as an avenue")
        }
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

    /// The two biggest parks in the city are both here, and a greens filter that lost
    /// either of them would have lost something the size of a neighbourhood.
    func testVanCortlandtAndPelhamBayAreAmongTheGreens() {
        let parks = map.parks
        XCTAssertGreaterThan(parks.count, 10)
        XCTAssertTrue(parks.contains { $0.name.localizedCaseInsensitiveContains("Van Cortlandt Park") })
        XCTAssertTrue(parks.contains { $0.name.localizedCaseInsensitiveContains("Pelham Bay Park") })
        for park in parks {
            XCTAssertGreaterThanOrEqual(park.ring.count, 3, "\(park.name) is not a shape")
        }
    }

    func testTheNeighbourhoodsAreNotOnTheMap() {
        // The point of the quiz is that the map does not tell you. A street may share a
        // name with a district — Fordham Road, Tremont Avenue, Melrose Avenue — so this
        // checks for road names that are *only* a neighbourhood.
        let forbidden = ["Riverdale", "Fordham", "Belmont", "Tremont", "Melrose", "Kingsbridge"]
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
    func testTheBronxIsDividedIntoNeighborhoods() {
        let areas = map.neighborhoods
        XCTAssertGreaterThanOrEqual(areas.count, 40, "Too few: has the tool fallen back to the NTAs?")
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

    func testTheNeighborhoodsAreWhereTheBronxIs() {
        for area in map.neighborhoods {
            for point in area.rings.flatMap({ $0 }) {
                XCTAssertTrue(longitudes.contains(point.longitude), "\(area.name) is not in the Bronx")
                XCTAssertTrue(latitudes.contains(point.latitude), "\(area.name) is not in the Bronx")
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
    /// Mott Haven with Port Morris and Kingsbridge Heights with Van Cortlandt Village;
    /// a re-fetch that fell back to the NTA table would pass every other test in this
    /// file and fail this one many times over.
    func testTheNamesAreOnesAPlayerWouldSay() {
        for name in [
            "Mott Haven", "Port Morris", "Hunts Point", "Longwood", "Morrisania", "Melrose",
            "Highbridge", "Concourse", "Claremont", "Mount Eden", "Mount Hope", "Tremont",
            "East Tremont", "West Farms", "Belmont", "Fordham", "University Heights",
            "Morris Heights", "Bedford Park", "Norwood", "Kingsbridge", "Kingsbridge Heights",
            "Riverdale", "Spuyten Duyvil", "Williamsbridge", "Wakefield", "Woodlawn",
            "Co-op City", "Eastchester", "Baychester", "Edenwald", "Pelham Gardens",
            "Allerton", "Bronxdale", "Pelham Parkway", "Morris Park", "Van Nest",
            "Parkchester", "Westchester Square", "Castle Hill", "Soundview", "Clason Point",
            "Throgs Neck", "Country Club", "Pelham Bay", "City Island",
        ] {
            XCTAssertNotNil(named(name), "\(name) is missing from the map")
        }

        // A hyphen *and* a space is the shape of an NTA name, not of a place. Co-op
        // City is the one exception in the city: the hyphen is in the word, not
        // between two places.
        for area in map.neighborhoods where area.name != "Co-op City" {
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
