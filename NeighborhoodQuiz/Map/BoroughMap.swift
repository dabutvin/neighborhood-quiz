import Foundation

/// What a road is, which is all the drawing needs to know to pick a weight, a colour
/// and when to show it.
///
/// The city's data has no notion of "avenue" — it has 9,297 numbered segments and a
/// roadway type that tells apart a street from a bridge. So the rank is worked out
/// from the one thing that does distinguish an avenue: an avenue is long. The streets
/// are sorted by how far they run and cut into three bands when the data is fetched,
/// which means the map re-ranks itself if the city ever re-surveys a block, and
/// nothing here holds a hand-written list of which streets matter.
enum RoadKind: Int, CaseIterable {
    /// The two dozen longest: the avenues, the drives, the parkways.
    case avenue = 0
    /// The next hundred and fifty: the cross streets people give directions by.
    case major = 1
    /// The other eight hundred, which are most of the borough.
    case side = 2
}

/// One road, as drawn: where it runs, what it is called, and whether this is the piece
/// of it that carries the name.
struct Road: Sendable {
    var name: String
    var coordinates: [Coordinate]
    var kind: RoadKind
    /// A street the city stores in pieces — Broadway is 389 rows — comes back as
    /// several runs. Exactly one of them, the longest, is written on.
    var carriesName: Bool
}

/// A borough, as the city has it.
///
/// Everything here is read from the borough's own file — `manhattan.json`,
/// `brooklyn.json` — which `Tools/fetch_map_data.py` writes from NYC Open Data and
/// which is committed to the repository. Nothing is generated, nothing is guessed, and
/// nothing is fetched at runtime: the streets below Houston are the streets that are
/// there, and Washington Heights is laid out the way it was actually laid out rather
/// than the way the 1811 grid would have continued.
///
/// Sendable by construction — every part of it is a value — and said so out loud,
/// because the cached copies below are `static let`s and Swift 6 wants to be told.
struct BoroughMap: Sendable {
    /// Whose map this is.
    let borough: Borough

    /// The land, as a list of rings. For Manhattan that is the island and the three
    /// others in the frame: Roosevelt, Randalls and the scrap of Marble Hill that is
    /// legally Manhattan and physically the Bronx. For Brooklyn it is most of the west
    /// end of Long Island.
    let land: [[Coordinate]]

    /// The greens over eight acres — Central Park chief among Manhattan's, Prospect
    /// Park among Brooklyn's.
    let parks: [Park]

    /// The neighborhoods, which are the point of the whole app.
    ///
    /// They are built out of the city's 2020 census tracts — the same tracts its
    /// Neighborhood Tabulation Areas are built out of, regrouped by `fetch_map_data.py`
    /// so that the compound names come apart and the split ones go back together. Which
    /// is to say SoHo is SoHo here, and not "SoHo-Little Italy-Hudson Square".
    ///
    /// The parks and the like are left out, being places nobody lives and nobody could
    /// be asked to name. Everywhere else tiles the land, so a tap on it falls in exactly
    /// one of them or, over Central Park, in none.
    let neighborhoods: [Neighborhood]

    /// Every road, longest first — which is the order the names are offered in when
    /// two of them want the same piece of paper. The drawing sorts its own copy the
    /// other way round, so the heavy lines go over the light ones.
    let roads: [Road]

    /// Who the map belongs to, for the credit the app shows.
    let source: String

    struct Park: Sendable {
        var name: String
        var ring: [Coordinate]
    }

    struct Neighborhood: Sendable {
        var name: String
        /// Most are one shape. A couple are several — the Financial District takes in
        /// the piers along both rivers — so every one of them is a list.
        var rings: [[Coordinate]]
    }

    // MARK: - Which one

    /// The map of a borough, parsed once and kept.
    ///
    /// One cached copy per drawn borough rather than a load per call: a file is two
    /// hundred kilobytes and more, and the drawing asks for its parts several times over
    /// while it is being built. The copies are `static let`s, which is what makes them
    /// safe to read from anywhere — nothing here is ever written to after it is made.
    ///
    /// Asking for a borough with no file behind it is a programming error, not a state
    /// of the game: `Wallet.play` will not let a player in, so a crash here means some
    /// code path forgot to ask `isDrawn` first.
    static func of(_ borough: Borough) -> BoroughMap {
        switch borough {
        case .manhattan: return manhattan
        case .brooklyn: return brooklyn
        case .queens, .bronx, .statenIsland:
            preconditionFailure("\(borough.name) is not drawn yet; there is no \(borough.mapFile).json to read")
        }
    }

    private static let manhattan = load(.manhattan)
    private static let brooklyn = load(.brooklyn)

    // MARK: - Reading the file

    private struct Document: Decodable {
        struct Road: Decodable {
            let n: Int
            let t: Int
            let l: Int
            let p: [[Double]]
        }
        struct Park: Decodable {
            let name: String
            let ring: [[Double]]
        }
        struct Neighborhood: Decodable {
            let name: String
            let rings: [[[Double]]]
        }
        let source: String
        let names: [String]
        let roads: [Road]
        let land: [[[Double]]]
        let parks: [Park]
        let neighborhoods: [Neighborhood]
    }

    /// Parsed once per borough. Two hundred kilobytes of JSON is a few milliseconds,
    /// and it happens before the first frame rather than during one.
    private static func load(_ borough: Borough) -> BoroughMap {
        guard let url = Bundle(for: BundleToken.self).url(forResource: borough.mapFile, withExtension: "json"),
              let data = try? Data(contentsOf: url),
              let document = try? JSONDecoder().decode(Document.self, from: data)
        else {
            // The map is the app. If this file is missing the bundle is broken, and a
            // borough-shaped hole is a worse way to find that out than a crash is.
            preconditionFailure("\(borough.mapFile).json is missing from the app bundle")
        }

        func coordinates(_ raw: [[Double]]) -> [Coordinate] {
            raw.compactMap { $0.count >= 2 ? Coordinate($0[0], $0[1]) : nil }
        }

        let roads = document.roads.map { road in
            Road(
                name: document.names.indices.contains(road.n) ? document.names[road.n] : "",
                coordinates: coordinates(road.p),
                kind: RoadKind(rawValue: road.t) ?? .side,
                carriesName: road.l == 1
            )
        }

        return BoroughMap(
            borough: borough,
            land: document.land.map(coordinates),
            parks: document.parks.map { Park(name: $0.name, ring: coordinates($0.ring)) },
            neighborhoods: document.neighborhoods.map {
                Neighborhood(name: $0.name, rings: $0.rings.map(coordinates))
            },
            roads: roads,
            source: document.source
        )
    }

    /// Locates the bundle the app's own code lives in, which is where the data sits.
    /// `Bundle.main` would be the test runner rather than the app when the tests run
    /// without a host, and the map would be missing exactly where it is being checked.
    private final class BundleToken {}
}
