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
    /// The other eight hundred, which are most of the island.
    case side = 2
}

/// One road, as drawn: where it runs, what it is called, and whether this is the piece
/// of it that carries the name.
struct Road {
    var name: String
    var coordinates: [Coordinate]
    var kind: RoadKind
    /// A street the city stores in pieces — Broadway is 389 rows — comes back as
    /// several runs. Exactly one of them, the longest, is written on.
    var carriesName: Bool
}

/// Manhattan, as the city has it.
///
/// Everything here is read from `manhattan.json`, which `Tools/fetch_map_data.py`
/// writes from NYC Open Data and which is committed to the repository. Nothing is
/// generated, nothing is guessed, and nothing is fetched at runtime: the streets below
/// Houston are the streets that are there, and Washington Heights is laid out the way
/// it was actually laid out rather than the way the 1811 grid would have continued.
enum ManhattanMapData {
    /// The island, and the three others in the frame: Roosevelt, Randalls and the
    /// scrap of Marble Hill that is legally Manhattan and physically the Bronx.
    static var land: [[Coordinate]] { loaded.land }

    /// Central Park and ninety-five other greens over eight acres.
    static var parks: [Park] { loaded.parks }

    /// The forty neighborhoods, which are the point of the whole app.
    ///
    /// They are built out of the city's 2020 census tracts — the same tracts its
    /// Neighborhood Tabulation Areas are built out of, regrouped by `fetch_map_data.py`
    /// so that the compound names come apart and the split ones go back together. Which
    /// is to say SoHo is SoHo here, and not "SoHo-Little Italy-Hudson Square".
    ///
    /// The parks and the United Nations are left out, being places nobody lives and
    /// nobody could be asked to name. Everywhere else tiles the island, so a tap on land
    /// falls in exactly one of them or, over Central Park, in none.
    static var neighborhoods: [Neighborhood] { loaded.neighborhoods }

    /// Every road, longest first — which is the order the names are offered in when
    /// two of them want the same piece of paper. The drawing sorts its own copy the
    /// other way round, so the heavy lines go over the light ones.
    static var roads: [Road] { loaded.roads }

    /// Who the map belongs to, for the credit the app shows.
    static var source: String { loaded.source }

    struct Park {
        var name: String
        var ring: [Coordinate]
    }

    struct Neighborhood {
        var name: String
        /// Most are one shape. A couple are several — the Financial District takes in
        /// the piers along both rivers — so every one of them is a list.
        var rings: [[Coordinate]]
    }

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

    private struct Loaded {
        var land: [[Coordinate]]
        var parks: [Park]
        var neighborhoods: [Neighborhood]
        var roads: [Road]
        var source: String
    }

    /// Parsed once. Two hundred kilobytes of JSON is a few milliseconds, and it happens
    /// before the first frame rather than during one.
    private static let loaded: Loaded = {
        guard let url = Bundle(for: BundleToken.self).url(forResource: "manhattan", withExtension: "json"),
              let data = try? Data(contentsOf: url),
              let document = try? JSONDecoder().decode(Document.self, from: data)
        else {
            // The map is the app. If this file is missing the bundle is broken, and an
            // island-shaped hole is a worse way to find that out than a crash is.
            preconditionFailure("manhattan.json is missing from the app bundle")
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

        return Loaded(
            land: document.land.map(coordinates),
            parks: document.parks.map { Park(name: $0.name, ring: coordinates($0.ring)) },
            neighborhoods: document.neighborhoods.map {
                Neighborhood(name: $0.name, rings: $0.rings.map(coordinates))
            },
            roads: roads,
            source: document.source
        )
    }()

    /// Locates the bundle the app's own code lives in, which is where the data sits.
    /// `Bundle.main` would be the test runner rather than the app when the tests run
    /// without a host, and the map would be missing exactly where it is being checked.
    private final class BundleToken {}
}
