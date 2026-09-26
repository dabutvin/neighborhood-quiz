import Foundation

/// How a first-time player is shown the game: four tips, over their first real round,
/// each one arriving at the moment it is about.
///
/// Not a slideshow in front of the game. The app already drops a new player straight
/// into a round because the map with a question over it is the whole pitch, and four
/// pages of rules before it would be four pages between somebody and the thing they
/// downloaded. So the round is the tutorial, and the tips say what the next thing to do
/// is only once it is the next thing to do:
///
/// 1. `pick` — as the first question is asked: tap where you think it is, and the
///    streets are the clues.
/// 2. `answer` — once something is picked: the outline is the place picked, and Answer
///    is what locks it in.
/// 3. `goes` — once the first answer is in: what a try is worth, said about the try the
///    player has just had. The one tip with a Got it on it, since it is the one a player
///    reads and is then done with before the game has moved on.
/// 4. `money` — on the card at the end of the round: the money is kept, and what it buys.
///
/// Nothing here knows about views or storage. It is told what happened and says which
/// tip, if any, is up — which is what lets the order be argued about in a test.
struct Tutorial: Equatable {
    enum Step: Equatable {
        case pick
        case answer
        /// Whether the first answer found the place, since the tip is about the go the
        /// player has just had.
        case goes(found: Bool)
        case money

        /// Which tip this is, counted from one, for the "tip 2 of 4" on the card.
        var number: Int {
            switch self {
            case .pick: return 1
            case .answer: return 2
            case .goes: return 3
            case .money: return 4
            }
        }

        /// Whether the card has a Got it that puts this one tip away, rather than a Skip
        /// that ends them all. Only the tip about tries: it stays up until the next pick
        /// otherwise, and a player who has read it should not have to look past it.
        var isDismissible: Bool {
            if case .goes = self { return true }
            return false
        }

        /// The word it goes under on a chart. `goes` is one tip whichever way the first
        /// answer went, and keeps its name so the charts drawn off it carry on.
        var name: String {
            switch self {
            case .pick: return "pick"
            case .answer: return "answer"
            case .goes: return "goes"
            case .money: return "money"
            }
        }
    }

    /// What happened, as far as the tips care.
    enum Event: Equatable {
        case roundStarted
        /// Something picked out on the map, waiting on the button.
        case picked
        /// The pick put down again: tapped twice, or a tap on water.
        case unpicked
        case answered(QuizRound.Answer)
        case roundFinished
        /// Off the end-of-round card: Play again, Menu, or a new pick.
        case summaryLeft
        /// A round walked away from part-way.
        case roundLeft
        /// The Skip on a tip.
        case skipped
        /// The Got it on the tip about tries: this tip read, the rest still to come.
        case dismissed
    }

    /// Whether this player is still being shown how to play.
    private(set) var isCoaching: Bool

    /// The tip up right now, or nothing between tips.
    private(set) var step: Step?

    init(coaching: Bool) {
        isCoaching = coaching
    }

    /// One tip up, for the screenshot runs.
    static func showing(_ step: Step) -> Tutorial {
        var tutorial = Tutorial(coaching: true)
        tutorial.step = step
        return tutorial
    }

    mutating func handle(_ event: Event) {
        guard isCoaching else { return }

        switch event {
        case .roundStarted:
            // A round left part-way and started again starts the tips again: the player
            // never got to the end of them.
            step = .pick
        case .picked:
            if step == .pick {
                step = .answer
            } else if case .goes = step {
                // Read, and acted on. Nothing more to say until the round is over.
                step = nil
            }
        case .unpicked:
            // The Answer tip is about a button that has just gone away.
            if step == .answer { step = .pick }
        case .answered(let outcome):
            guard step == .answer else { return }
            switch outcome {
            case .right: step = .goes(found: true)
            case .wrong, .missed: step = .goes(found: false)
            case .ignored: break
            }
        case .roundFinished:
            step = .money
        case .summaryLeft:
            // The last tip read: that is the whole of it.
            guard step == .money else { return }
            step = nil
            isCoaching = false
        case .roundLeft:
            step = nil
        case .skipped:
            step = nil
            isCoaching = false
        case .dismissed:
            if case .goes = step { step = nil }
        }
    }
}

// MARK: - What the tips say

extension Tutorial.Step {
    struct Tip: Equatable {
        let title: String
        let body: String
    }

    /// The words on the card. Every number in them is read from the rules rather than
    /// typed in, so a change to the points or the ladder cannot leave a tip saying
    /// something the game no longer does.
    func tip(for wallet: Wallet) -> Tip {
        let points = QuizRound.points.map(Money.text)
        let tries = "The first try pays \(points[0]), the second \(points[1]) and the third "
            + "\(points[2]). Three misses and the map shows you where it was."

        switch self {
        case .pick:
            return Tip(
                title: "Zoom in and find",
                body: "Tap the neighborhood you think it is. Nothing is labeled, so the "
                    + "streets are your clues. Pinch or use + and − to zoom, and drag to "
                    + "look around."
            )
        case .answer:
            return Tip(
                title: "Now tap Answer",
                body: "The outline shows the boundaries of the neighborhood you picked. "
                    + "Not the one you meant? Tap somewhere else to pick again."
            )
        case .goes(found: true):
            return Tip(title: "Found it, first try!", body: tries)
        case .goes(found: false):
            return Tip(
                title: "Not there",
                body: "That place is crossed off, and you have \(QuizRound.tries - 1) tries "
                    + "left. \(tries)"
            )
        case .money:
            guard let price = wallet.nextPrice else {
                return Tip(title: "Your money is kept", body: "It adds up across rounds.")
            }
            let body = wallet.balance >= price
                ? "It adds up across rounds, and you have enough for another borough. "
                    + "Pick one from the Boroughs menu below."
                : "It adds up across rounds. At \(Money.text(price)) you can unlock "
                    + "another borough, whichever you like, from the Boroughs menu below."
            return Tip(title: "Your money is kept", body: body)
        }
    }
}

// MARK: - Remembering it

/// Whether this phone has been shown how to play.
///
/// A key of its own rather than a field on the wallet, because it is not game data: it
/// says nothing about what anybody has earned, and a wallet with nothing in it but "has
/// seen the tips" would stop being empty — which is what decides whether the app opens
/// on a round or on the menu, and whether Settings has anything to delete.
///
/// Three states, not two. Nothing written means nobody has decided yet, and the wallet
/// decides: a player with rounds behind them learned the game before there were tips, and
/// an update should not start coaching them. Written `true` once the tips are read or
/// skipped; written `false` by "How to play", which asks for them again whatever the
/// wallet says.
///
/// "Delete all saved data" erases it along with the wallet, because what that button
/// promises is the app as it was on a fresh install — and a fresh install is shown the
/// tips. With nothing written and an empty wallet, the next round is coached.
///
/// With no `defaults` it coaches nobody and writes nothing, which is what the screenshot
/// runs use.
struct TutorialRecord {
    static let key = "tutorial.done"
    private let defaults: UserDefaults?

    init(defaults: UserDefaults? = .standard) {
        self.defaults = defaults
    }

    func shouldCoach(_ wallet: Wallet) -> Bool {
        guard let defaults else { return false }
        if let done = defaults.object(forKey: Self.key) as? Bool { return !done }
        return wallet.rounds == 0
    }

    func finish() {
        defaults?.set(true, forKey: Self.key)
    }

    func replay() {
        defaults?.set(false, forKey: Self.key)
    }

    /// Forgets it was ever decided, for "Delete all saved data".
    func erase() {
        defaults?.removeObject(forKey: Self.key)
    }
}
