import CryptoKit
import Foundation
import Observation

/// One thing worth knowing about, on its way off the phone.
///
/// A name, a handful of words about it, and at most one number — which is as much as any
/// question about how the game is played needs answering. Nothing here is about a person:
/// the fields are borough names, neighbourhood names, scores and go counts, and there is
/// no room in the shape for anything else.
struct AnalyticsSignal: Equatable, Sendable {
    /// What happened, in the dotted form the dashboards group by: `Round.finished`,
    /// `Place.settled`.
    let name: String
    /// The circumstances, as plain strings. Small on purpose — a signal carrying half the
    /// round is a signal nobody can ask a question of.
    let parameters: [String: String]
    /// The one number the signal is about, if it is about a number: the score a round
    /// came to, the price a borough went for. Charted directly, so it is worth choosing.
    let value: Double?

    init(_ name: String, _ parameters: [String: String] = [:], value: Double? = nil) {
        self.name = name
        self.parameters = parameters
        self.value = value
    }
}

/// Who a batch of signals is from — which is to say, not who at all.
///
/// The install is a random number minted on the device the first time the game is opened
/// and hashed before it ever leaves; the session is minted fresh every launch. Together
/// they say *these signals came from one phone, in one sitting*, and nothing else. No
/// advertising identifier, no vendor identifier, no account, nothing Apple asks a
/// tracking permission for.
struct AnalyticsIdentity: Equatable, Sendable {
    /// The hashed install. Hashed again and salted at the far end.
    let install: String
    /// This launch. Gone when the app is.
    let session: String
}

/// Where signals go once the game has finished with them.
///
/// A protocol rather than the uploader outright, so the tests can watch what the game
/// asks to send without anything leaving the machine they run on.
@MainActor
protocol AnalyticsSink {
    /// Takes a batch and is done with it. Nothing waits on this — a game is not held up
    /// by a dashboard, and a batch that never arrives is a batch nobody misses.
    func send(_ signals: [AnalyticsSignal], from identity: AnalyticsIdentity)
}

/// A sink that sends nothing. What the game runs on when no dashboard is configured, and
/// on the runs that take the screenshots — a photograph of the map is not a player.
struct SilentAnalytics: AnalyticsSink {
    func send(_ signals: [AnalyticsSignal], from identity: AnalyticsIdentity) {}
}

/// A sink that sends nothing and keeps a list of what it was handed.
@MainActor
final class RecordedAnalytics: AnalyticsSink {
    private(set) var batches: [[AnalyticsSignal]] = []
    private(set) var identities: [AnalyticsIdentity] = []

    /// Every signal handed over, in order, with the batching flattened out — which is
    /// what most questions about what the game sent are actually asking.
    var sent: [AnalyticsSignal] { batches.flatMap { $0 } }

    func send(_ signals: [AnalyticsSignal], from identity: AnalyticsIdentity) {
        batches.append(signals)
        identities.append(identity)
    }
}

/// Where the player's answer to *may we count this* is kept, along with the random number
/// that stands in for the install.
protocol AnalyticsStore {
    func loadIsOn() -> Bool
    func save(isOn: Bool)
    /// The install's own number, or nothing at all on a phone that has never minted one.
    func loadInstall() -> String?
    func save(install: String)
    /// Throws the install's number away, so the player is somebody nobody has counted
    /// before. Wired to the same button that throws the wallet away, since a player asking
    /// for the game back as they found it means all of it.
    ///
    /// The switch is deliberately left alone. It is a setting, not game data, and a
    /// delete-everything that quietly turned counting back on for somebody who had turned
    /// it off would be the worst thing in this file.
    func eraseInstall()
}

/// The real thing: the switch and the number survive the app being closed.
///
/// Two keys beside the wallet's one. They are the only other things the app writes down,
/// and `SettingsTests` holds it to that.
struct StoredAnalytics: AnalyticsStore {
    static let key = "analytics.on"
    static let installKey = "analytics.install"
    private let defaults: UserDefaults

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    func loadIsOn() -> Bool {
        // Nothing written means on. What is counted is anonymous and the switch is one
        // screen away, so the game ships counting rather than shipping deaf and asking.
        defaults.object(forKey: Self.key) as? Bool ?? true
    }

    func save(isOn: Bool) {
        defaults.set(isOn, forKey: Self.key)
    }

    func loadInstall() -> String? {
        defaults.string(forKey: Self.installKey)
    }

    func save(install: String) {
        defaults.set(install, forKey: Self.installKey)
    }

    func eraseInstall() {
        defaults.removeObject(forKey: Self.installKey)
    }
}

/// A switch and a number that forget the moment they are put down. For the tests, and for
/// the screenshot runs, whose settings screen must not write into a real player's phone.
final class RememberedAnalytics: AnalyticsStore {
    private var isOn: Bool
    private var install: String?

    init(isOn: Bool = true, install: String? = nil) {
        self.isOn = isOn
        self.install = install
    }

    func loadIsOn() -> Bool { isOn }

    func save(isOn: Bool) { self.isOn = isOn }

    func loadInstall() -> String? { install }

    func save(install: String) { self.install = install }

    func eraseInstall() { install = nil }
}

/// Everything the game counts, and the one switch that stops it.
///
/// The whole game goes through `Analytics.record` rather than reaching for an uploader
/// where it stands, so that the switch in settings is the only place the question is ever
/// asked — and with it off, nothing is recorded, nothing is held and nothing is sent. Not
/// queued for later, not written down quietly: the signal is dropped at the door.
///
/// Signals are gathered into batches rather than going one at a time, because a quiz is
/// played in bursts on a phone that is often on a train. A batch goes when it fills up or
/// when the player puts the game down, whichever comes first, and whatever is still in
/// hand when the app is killed outright is simply lost. That is the trade the low overhead
/// buys: no background task, no disk queue, no retry ladder — a dropped batch costs a few
/// rows on a chart and nothing at all to the player.
@MainActor
@Observable
final class Analytics {
    /// The one the game counts through, and the one the settings toggle holds.
    static let shared = Analytics()

    /// How many signals gather before a batch goes on its own. A round of ten is about
    /// twelve signals, so a player who plays one round and leaves is counted when they
    /// put the phone down, and a long sitting is a request every other round.
    static let batchSize = 20

    /// Whether the game is allowed to count. Written the moment it changes, since a player
    /// who turns it off and puts the game down means it.
    ///
    /// Turning it off says so on the way out — that one last signal is sent before the
    /// gate shuts, because a dashboard that cannot tell *switched off* from *stopped
    /// playing* will read every opt-out as a player lost.
    var isOn: Bool {
        didSet {
            guard isOn != oldValue else { return }
            store.save(isOn: isOn)
            if isOn {
                record(.analyticsSwitched(on: true))
            } else {
                pending.append(.analyticsSwitched(on: false))
                flush()
            }
        }
    }

    /// Whether this launch is the first the game has ever been counted on. What tells a run
    /// of sessions apart from a run of installs, and the denominator under every funnel
    /// below it.
    @ObservationIgnored private(set) var isFirstRun: Bool

    @ObservationIgnored private let store: any AnalyticsStore
    @ObservationIgnored private let sink: any AnalyticsSink
    /// This launch. A sitting rather than a person: minted here and never written down.
    @ObservationIgnored private let session = UUID().uuidString
    /// Signals gathered since the last batch went.
    @ObservationIgnored private(set) var pending: [AnalyticsSignal] = []
    /// The hashed install, worked out once and kept, since hashing it on every signal is
    /// work for nothing.
    @ObservationIgnored private var install: String?

    /// What this build counts through: the uploader when there is a dashboard to send to,
    /// and silence when there is not.
    static func defaultSink() -> any AnalyticsSink {
        if let sink = TelemetryDeckSink.configured() { return sink }
        return SilentAnalytics()
    }

    /// A counter that remembers nothing and sends nowhere, for the screenshot runs and
    /// the previews — so the toggle in a photograph of the settings screen can never
    /// reach a real player's switch.
    static func staged() -> Analytics {
        Analytics(store: RememberedAnalytics(), sink: SilentAnalytics())
    }

    init(
        store: any AnalyticsStore = StoredAnalytics(),
        sink: any AnalyticsSink = Analytics.defaultSink()
    ) {
        self.store = store
        self.sink = sink
        self.isFirstRun = store.loadInstall() == nil
        self.isOn = store.loadIsOn()
        // Minted at launch rather than at the first batch, so that a session killed before
        // it could send anything is still not counted as a fresh install the next morning.
        if isOn { _ = installID() }
    }

    /// Counts one thing, if counting is allowed. Everything the game counts comes through
    /// here, and with the switch off nothing beyond it is even built.
    func record(_ signal: AnalyticsSignal) {
        guard isOn else { return }
        pending.append(signal)
        if pending.count >= Self.batchSize {
            flush()
        }
    }

    /// Hands whatever has gathered to the sink. Called when a batch fills up and when the
    /// player puts the game down, and safe to call on an empty hand.
    func flush() {
        guard !pending.isEmpty else { return }
        let batch = pending
        pending = []
        sink.send(batch, from: AnalyticsIdentity(install: installID(), session: session))
    }

    /// Throws the install's number away, for the player who wants the game back as they
    /// found it. Anything still in hand goes with it rather than being sent under a number
    /// that no longer exists.
    ///
    /// The switch survives, on purpose: a player who turned counting off and then deleted
    /// their wallet has not asked to be counted again.
    func eraseEverything() {
        pending = []
        install = nil
        store.eraseInstall()
        isFirstRun = true
    }

    /// The number that stands in for this install, minted on first use and hashed before
    /// it goes anywhere. Random rather than anything the phone already knows about itself,
    /// so there is nothing on the far end to join it up to.
    private func installID() -> String {
        if let install { return install }
        let raw = store.loadInstall() ?? {
            let minted = UUID().uuidString
            store.save(install: minted)
            return minted
        }()
        let hashed = Self.hashed(raw)
        install = hashed
        return hashed
    }

    static func hashed(_ raw: String) -> String {
        let digest = SHA256.hash(data: Data((raw + "nycquiz").utf8))
        return digest.map { String(format: "%02x", $0) }.joined()
    }

    static func record(_ signal: AnalyticsSignal) { shared.record(signal) }

    static func flush() { shared.flush() }
}

// MARK: - What the game counts

/// Every signal the game sends, written out in one place.
///
/// One file rather than a name typed out wherever it is sent from, so that the list of
/// what this game knows about its players can be read end to end — by whoever is reading
/// the dashboards, and by whoever is filling in the App Store's privacy questionnaire.
///
/// The rule every one of these keeps: nothing that identifies a player, nothing they typed,
/// nothing about the phone beyond what the platform attaches anyway. Borough names,
/// neighbourhood names out of the app's own data, scores, go counts and prices.
extension AnalyticsSignal {
    // MARK: Opening the game

    /// A launch. The count of these against the count of installs is the first thing worth
    /// knowing: whether anybody comes back.
    static func sessionStarted(isFirstRun: Bool) -> AnalyticsSignal {
        AnalyticsSignal("Session.started", ["firstRun": String(isFirstRun)])
    }

    // MARK: A round, start to finish

    /// A round begun, and what it is about: one borough's name, or `anywhere` for a round
    /// drawn from every borough the player has open. `open` is how many that is, which is
    /// how far up the ladder the player playing it has got.
    static func roundStarted(_ pick: Wallet.Pick, open: Int) -> AnalyticsSignal {
        AnalyticsSignal(
            "Round.started",
            ["where": word(for: pick), "open": String(open)],
            value: Double(open)
        )
    }

    /// A round played to the end and paid. The score is the number worth charting; the
    /// breakdown beside it is how the score was made — how many first go, how many
    /// second, how many third, how many never — which is the difficulty of the game read
    /// off the players rather than guessed at. `rounds` is the career count including
    /// this one, so a chart can tell a first round from a fiftieth.
    static func roundFinished(_ round: QuizRound, pick: Wallet.Pick, rounds: Int) -> AnalyticsSignal {
        AnalyticsSignal(
            "Round.finished",
            [
                "where": word(for: pick),
                "score": String(round.score),
                "perfect": String(round.perfectScore),
                "firstGo": String(round.foundOn[safe: 0] ?? 0),
                "secondGo": String(round.foundOn[safe: 1] ?? 0),
                "thirdGo": String(round.foundOn[safe: 2] ?? 0),
                "missed": String(round.missed.count),
                "rounds": String(rounds)
            ],
            value: Double(round.score)
        )
    }

    /// A round walked away from part-way, and how far it had got. Nothing is banked for
    /// one of these, so against `Round.finished` this is how often a round is worth
    /// finishing — and a high count at question one is a player who pressed Start by
    /// mistake, which says something about the menu.
    static func roundLeft(_ round: QuizRound, pick: Wallet.Pick) -> AnalyticsSignal {
        AnalyticsSignal(
            "Round.left",
            [
                "where": word(for: pick),
                "asked": String(round.index),
                "of": String(round.questions.count),
                "score": String(round.score)
            ],
            value: Double(round.index)
        )
    }

    /// One question settled: a neighbourhood found on some go, or never found and shown.
    /// The one signal that says which neighbourhoods are hard, which is the thing this
    /// game most wants to know about itself — the names in the outer boroughs are a
    /// judgement, and a place nobody ever finds is one that may be drawn or named wrong.
    ///
    /// `go` is `1`, `2` or `3` for a find and `missed` for three goes that were not enough;
    /// the value is what the go was worth, so an average of it per place is a difficulty.
    static func placeSettled(_ place: Place, go: Int?, worth: Int) -> AnalyticsSignal {
        AnalyticsSignal(
            "Place.settled",
            [
                "borough": place.borough.rawValue,
                "place": place.name,
                "go": go.map { String($0 + 1) } ?? "missed",
                "worth": String(worth)
            ],
            value: Double(worth)
        )
    }

    // MARK: The city

    /// A borough bought, which rung of the ladder it was, and what it cost. `rounds` is
    /// how many rounds it took to get there — the one number that says whether the
    /// ladder is set right.
    static func boroughBought(_ borough: Borough, rung: Int, price: Int, rounds: Int) -> AnalyticsSignal {
        AnalyticsSignal(
            "Borough.bought",
            [
                "borough": borough.rawValue,
                "rung": String(rung),
                "price": String(price),
                "rounds": String(rounds)
            ],
            value: Double(price)
        )
    }

    /// What the next round was pointed at — a borough, or the whole city — and from
    /// where: the row of pills on the menu, or the Play button on the ladder.
    static func boroughPicked(_ pick: Wallet.Pick, from source: String) -> AnalyticsSignal {
        AnalyticsSignal("Borough.picked", ["where": word(for: pick), "from": source])
    }

    /// The ladder opened, and from where: the menu, or the end of a round. Against
    /// `Borough.bought` it is how often a look at the prices turns into a purchase.
    static func boroughsOpened(from source: String) -> AnalyticsSignal {
        AnalyticsSignal("Boroughs.opened", ["from": source])
    }

    // MARK: Settings

    static let settingsOpened = AnalyticsSignal("Settings.opened")

    /// The button that hands everything back. Rare, and worth knowing when it is not.
    static let dataCleared = AnalyticsSignal("Settings.dataCleared")

    static func analyticsSwitched(on: Bool) -> AnalyticsSignal {
        AnalyticsSignal("Settings.analyticsSwitched", ["on": String(on)])
    }

    // MARK: Being rated

    /// Apple's own rating sheet asked for, and after how many rounds. Whether the player
    /// saw anything is Apple's to decide and nothing on the phone will say — so this counts
    /// the asking, which is the only half the game knows.
    static func ratingAsked(afterRounds rounds: Int) -> AnalyticsSignal {
        AnalyticsSignal("Rating.asked", ["rounds": String(rounds)], value: Double(rounds))
    }

    /// The store page opened from Settings to leave a rating. A different question from
    /// the sheet above: that one is the game asking, and this is a player who went looking
    /// for the box to type in.
    static let ratingPageOpened = AnalyticsSignal("Rating.pageOpened")

    /// The word a pick goes under on a chart: the borough's raw name, or `anywhere`.
    static func word(for pick: Wallet.Pick) -> String {
        switch pick {
        case .borough(let borough): return borough.rawValue
        case .anywhere: return "anywhere"
        }
    }
}

private extension Array {
    subscript(safe index: Int) -> Element? {
        indices.contains(index) ? self[index] : nil
    }
}
