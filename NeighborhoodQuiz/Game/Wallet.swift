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

    /// Where the player is: the borough the next round will ask about.
    ///
    /// Kept in the wallet rather than somewhere of its own because the wallet is the one
    /// thing the app writes down, and "where they have been" is already its business —
    /// the doc comment at the top says so. A player who bought Brooklyn and moved there
    /// should open the app in Brooklyn, and a second preference to remember that would
    /// be a second thing for settings to promise to delete.
    ///
    /// Read through `current`, not directly: this is what was asked for, and `current`
    /// is what can actually be had.
    private(set) var playing: Borough = .manhattan

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

    /// The borough being played, checked against what is playable.
    ///
    /// `playing` is what the player last chose; this is what the game can honour. The
    /// two come apart in exactly one way — a wallet that says Brooklyn when Brooklyn is
    /// not on the list — and there are two roads to it: a wallet written by a build in
    /// which Brooklyn was drawn and read by one in which it is not, or a purchase that
    /// has since been erased. Either way the player is put back in Manhattan, which is
    /// always open, rather than stranded in a borough the map cannot show.
    var current: Borough {
        playable.contains(playing) ? playing : .manhattan
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
    /// tested against a city of the test's choosing. It dates from when nothing but
    /// Manhattan was drawn and a test that could only ever watch a purchase fail would
    /// not have been testing buying at all; it stays because the same will be true of
    /// Queens until it is drawn, and of whatever comes after.
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

    /// Go and play a borough. Returns whether the move was allowed.
    ///
    /// Two things have to be true: it is open — bought, or Manhattan — and there is a
    /// map behind it. Buying does not move the player there on its own; that is a
    /// choice, and the menu offers it.
    @discardableResult
    mutating func play(_ borough: Borough) -> Bool {
        guard has(borough), borough.isDrawn else { return false }
        playing = borough
        return true
    }

    // MARK: - Reading it back

    private enum CodingKeys: String, CodingKey {
        case balance, earned, rounds, bought, playing
    }

    /// Written by hand so that a wallet saved before `playing` existed still reads.
    ///
    /// The saved copy lives under `wallet.v1`, and every wallet written before Brooklyn
    /// was drawn has no `playing` in it. The synthesised decoder would refuse the whole
    /// thing over the missing key, the bank would treat that as nothing saved, and a
    /// player would open the update to an empty balance. A missing field means
    /// Manhattan, which is where everybody was. Encoding is still the compiler's.
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        balance = try container.decode(Int.self, forKey: .balance)
        earned = try container.decode(Int.self, forKey: .earned)
        rounds = try container.decode(Int.self, forKey: .rounds)
        bought = try container.decode(Set<Borough>.self, forKey: .bought)
        playing = try container.decodeIfPresent(Borough.self, forKey: .playing) ?? .manhattan
    }
}
