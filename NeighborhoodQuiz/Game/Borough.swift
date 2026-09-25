import Foundation

/// The five boroughs.
///
/// Manhattan is free and always open — it is where the game starts and there has to be
/// somewhere to earn the first dollar. The other four are bought, one at a time, in
/// whatever order the player likes, and what climbs is not any borough's own price but
/// the `ladder`: the first borough bought costs the first rung, the second the second,
/// whichever boroughs they are. `allCases` is just the list; it says nothing about which
/// comes next, because that is the player's to decide.
///
/// `isDrawn` is the honest part. A borough in this list is somewhere the game intends to
/// go; a borough that is drawn is somewhere it can actually take you. The whole city is
/// drawn now, all five, so the two lists agree — but they are still two lists. A file
/// pulled for a re-survey, or a sixth "borough" added before its map is, would put a
/// borough back on the first list and off the second, and the game would say plainly
/// that its map is not built yet rather than take money for a blank page.
enum Borough: String, CaseIterable, Identifiable, Codable, Sendable {
    case manhattan
    case brooklyn
    case queens
    case bronx
    case statenIsland

    var id: String { rawValue }

    var name: String {
        switch self {
        case .manhattan: return "Manhattan"
        case .brooklyn: return "Brooklyn"
        case .queens: return "Queens"
        case .bronx: return "The Bronx"
        case .statenIsland: return "Staten Island"
        }
    }

    /// The one that was never locked. Everything the wallet knows about being open
    /// starts from here.
    static let free: Borough = .manhattan

    /// Whether it was ever for sale.
    var isFree: Bool { self == Borough.free }

    /// The ones that cost something, which is everywhere the money is for.
    static var buyable: [Borough] { allCases.filter { !$0.isFree } }

    /// What the first, second, third and fourth borough bought cost, in dollars — one
    /// rung per borough in `buyable`, and the order the rungs are climbed in is the
    /// player's, not this list's.
    ///
    /// The shape is the whole idea: a round of Manhattan is worth up to fifty dollars,
    /// so the first borough is four good rounds away and the fourth is a long winter.
    /// Tying the price to how many have been bought rather than to which one means the
    /// climb is the same whichever way round the city is taken.
    static let ladder = [200, 600, 1_200, 2_000]

    /// The ones with a map behind them. All five, now: the city is drawn. It stays a
    /// set of its own rather than becoming `allCases` because it is the line a borough
    /// comes off if its file is ever pulled, and the line the next one goes on once its
    /// file lands — a file in `Resources/` and a cache line in `BoroughMap.of` go with
    /// each entry, and nothing else has to change to open one.
    static let drawn: Set<Borough> = Set(allCases)

    /// Whether there is a map behind it yet.
    var isDrawn: Bool { Borough.drawn.contains(self) }

    /// The file its map is read from, without the `.json`. One per borough, spelled the
    /// way `Tools/fetch_map_data.py` writes them — which for Staten Island is
    /// `staten-island`, hyphenated, because a resource name with a space in it is a
    /// bug waiting for a shell.
    var mapFile: String {
        switch self {
        case .manhattan: return "manhattan"
        case .brooklyn: return "brooklyn"
        case .queens: return "queens"
        case .bronx: return "bronx"
        case .statenIsland: return "staten-island"
        }
    }

    /// How far the borough's grid runs east of north, in degrees. The projection turns
    /// the plane back by this much before drawing, which is what makes the drawing read
    /// as a drawing rather than as a satellite photograph.
    ///
    /// Manhattan is the one this is for. The streets themselves come from the city now,
    /// but the 1811 grid still runs about twenty-nine degrees east of north, and turning
    /// the plane back by that much stands the avenues upright and lays the cross streets
    /// flat — which is how every hand-drawn map of the island has ever been drawn.
    ///
    /// Brooklyn is north-up, and not for want of a grid: it has half a dozen of them,
    /// at different angles — Williamsburg's, Bushwick's, Park Slope's, Bay Ridge's, the
    /// Flatbush avenues — and no one of them is the borough. There is no turn that stands
    /// Brooklyn's streets up the way the twenty-nine degrees stands Manhattan's; whichever
    /// grid you chose, the others would lean. North-up is how a Brooklyn map is drawn.
    ///
    /// The other three are north-up for their own reasons. Queens has a dozen grids
    /// and none of them is the borough, which is Brooklyn's problem twice over. The
    /// Bronx does have Manhattan's grid — the numbered streets carry on over the Harlem
    /// River — but they bend and give out a mile or two in, and a turn that suited
    /// Mott Haven would put Riverdale and Throgs Neck on a slant for nothing. Staten
    /// Island has no grid to speak of, and it runs north-east to south-west as it is.
    var gridBearingDegrees: Double {
        switch self {
        case .manhattan: return 29
        case .brooklyn, .queens, .bronx, .statenIsland: return 0
        }
    }
}

/// Dollars, written the way a price is written. One place, so the wallet, the ladder and
/// the end of a round cannot drift into three different spellings of the same number.
enum Money {
    static func text(_ amount: Int) -> String {
        "$\(amount.formatted())"
    }
}
