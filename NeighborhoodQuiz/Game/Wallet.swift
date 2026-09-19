import Foundation

/// What a player has earned, what they have left, and where they have been.
///
/// Two numbers, not one, and they answer different questions. `balance` is money you can
/// spend and it goes down when you spend it. `earned` is every dollar the game has ever
/// paid you and it only ever goes up — it is the career figure, the one that says how
/// much of this you have played, and buying Brooklyn must not make it look like you
/// played less.
///
/// Nothing here knows about maps, views or storage. A wallet is a value you can hand to
/// a test, spend from, and compare — which is why the rules below can be argued about in
/// a test file rather than by tapping a phone forty times.
struct Wallet: Equatable, Codable {
    /// Spendable dollars.
    private(set) var balance = 0

    /// Every dollar ever earned. Never decreases, not even to buy something.
    private(set) var earned = 0

    /// Rounds played to the end.
    private(set) var rounds = 0

    /// The ones that have been paid for. Manhattan is never in here — it was never for
    /// sale — which is why `has(_:)` asks about the price rather than about this set.
    private(set) var bought: Set<Borough> = []

    init() {}

    /// A wallet part-way through, for tests and for the screenshot runs.
    init(balance: Int, earned: Int? = nil, rounds: Int = 0, bought: Set<Borough> = []) {
        self.balance = max(balance, 0)
        self.earned = max(earned ?? balance, self.balance)
        self.rounds = max(rounds, 0)
        self.bought = bought
    }

    /// Whether there is anything here worth keeping. What settings asks before it
    /// offers to throw it away.
    var isEmpty: Bool { self == Wallet() }

    /// Whether a borough is open. Free ones always are.
    func has(_ borough: Borough) -> Bool {
        borough.price == 0 || bought.contains(borough)
    }

    /// Everywhere that can be played right now: open, and with a map behind it.
    var playable: [Borough] {
        Borough.allCases.filter { has($0) && $0.isDrawn }
    }

    /// The next thing being saved for — the cheapest one not yet owned. Nothing once
    /// the whole city is bought.
    var saving: Borough? {
        Borough.allCases.first { !has($0) }
    }

    /// How far along the way to `saving`, from 0 to 1. A full bar means the money is
    /// there, which is not the same as the map being there.
    var progress: Double {
        guard let saving, saving.price > 0 else { return 1 }
        return min(Double(balance) / Double(saving.price), 1)
    }

    /// How much of a borough's price is covered so far, which is never more than the
    /// price. The balance itself can be more, and saying so out loud reads as a mistake:
    /// "$240 of $200" is not a thing anybody has ever said about saving up.
    func saved(towards borough: Borough) -> Int {
        min(balance, borough.price)
    }

    /// Whether there is enough money for it. Says nothing about whether it is drawn.
    func canAfford(_ borough: Borough) -> Bool {
        !has(borough) && balance >= borough.price
    }

    /// Whether it can actually be bought: affordable, and somewhere the game can take
    /// you once it is paid for. The second half is why money can be ready and the
    /// button still says the map is coming.
    ///
    /// `drawn` is a parameter rather than a lookup so that the spending rules can be
    /// tested against a city where something other than Manhattan exists. Today nothing
    /// else does, and a test that could only ever watch a purchase fail would not be
    /// testing buying at all.
    func canBuy(_ borough: Borough, drawn: Set<Borough> = Borough.drawn) -> Bool {
        canAfford(borough) && drawn.contains(borough)
    }

    /// Take the money for a round.
    mutating func earn(_ amount: Int) {
        guard amount > 0 else { rounds += 1; return }
        balance += amount
        earned += amount
        rounds += 1
    }

    /// Buy a borough, if it can be bought. Returns whether it was.
    ///
    /// Refuses anything that is not drawn even when the money is there. Charging for a
    /// place the game cannot open is the one outcome worth writing a guard against.
    @discardableResult
    mutating func buy(_ borough: Borough, drawn: Set<Borough> = Borough.drawn) -> Bool {
        guard canBuy(borough, drawn: drawn) else { return false }
        balance -= borough.price
        bought.insert(borough)
        return true
    }
}
