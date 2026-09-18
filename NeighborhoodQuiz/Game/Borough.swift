import Foundation

/// The five boroughs, in the order you can afford them.
///
/// Manhattan is free and always open — it is where the game starts and there has to be
/// somewhere to earn the first dollar. Everything after it has a price, and the prices
/// climb, which is the whole shape of the thing: a round of Manhattan is worth up to
/// fifty dollars, so Brooklyn is four good rounds away and Staten Island is a long
/// winter.
///
/// `isDrawn` is the honest part. A borough in this list is somewhere the game intends to
/// go; a borough that is drawn is somewhere it can actually take you. Only Manhattan is
/// drawn today. The rest are priced and visible on purpose — knowing what you are saving
/// for is most of why saving is worth doing — but the game says plainly that their maps
/// are not built yet rather than taking money for a blank page.
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

    /// What it costs to open up, in dollars. Zero means it was never locked.
    var price: Int {
        switch self {
        case .manhattan: return 0
        case .brooklyn: return 200
        case .queens: return 600
        case .bronx: return 1_200
        case .statenIsland: return 2_000
        }
    }

    /// The ones with a map behind them. One entry today; this is the line that grows
    /// as each borough gets drawn, and the only line that has to change to open one.
    static let drawn: Set<Borough> = [.manhattan]

    /// Whether there is a map behind it yet.
    var isDrawn: Bool { Borough.drawn.contains(self) }

    /// The ones that cost something, which is everywhere the money is for.
    static var forSale: [Borough] { allCases.filter { $0.price > 0 } }
}

/// Dollars, written the way a price is written. One place, so the wallet, the ladder and
/// the end of a round cannot drift into three different spellings of the same number.
enum Money {
    static func text(_ amount: Int) -> String {
        "$\(amount.formatted())"
    }
}
