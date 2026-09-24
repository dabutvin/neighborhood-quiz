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
/// go; a borough that is drawn is somewhere it can actually take you. Manhattan and
/// Brooklyn are drawn today. The rest are listed on purpose — knowing what there is to
/// save for is most of why saving is worth doing — but the game says plainly that their
/// maps are not built yet rather than taking money for a blank page.
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

    /// The ones with a map behind them. Two entries today; this is the line that grows
    /// as each borough gets drawn. A file in `Resources/` and a cache line in
    /// `BoroughMap.of` go with it, and nothing else has to change to open one.
    static let drawn: Set<Borough> = [.manhattan, .brooklyn]

    /// Whether there is a map behind it yet.
    var isDrawn: Bool { Borough.drawn.contains(self) }

    /// The file its map is read from, without the `.json`. Only the drawn ones exist;
    /// the rest are named here so that drawing one is a matter of writing the file.
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
