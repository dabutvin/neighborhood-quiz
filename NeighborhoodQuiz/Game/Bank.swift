import Foundation
import Observation

/// The wallet, kept between launches.
///
/// `Wallet` holds the rules and knows nothing about where it lives; this holds the one
/// copy the app is playing with and writes it down after anything that changes it. The
/// split is so that every rule about money can be tested against a plain value, and the
/// only thing left to get wrong here is the reading and the writing.
///
/// A bank with no `defaults` remembers nothing. That is what the screenshot runs use, so
/// the gallery shows the same numbers every time and a staged round can never spend, add
/// to or inherit a real player's money.
@Observable
final class Bank {
    static let storageKey = "wallet.v1"

    private(set) var wallet: Wallet

    @ObservationIgnored private let defaults: UserDefaults?
    @ObservationIgnored private let key: String

    init(defaults: UserDefaults? = .standard, key: String = Bank.storageKey, starting: Wallet = Wallet()) {
        self.defaults = defaults
        self.key = key
        self.wallet = Bank.read(from: defaults, key: key) ?? starting
    }

    /// A bank for the gallery: money on it, nothing written down.
    static func staged(_ wallet: Wallet) -> Bank {
        Bank(defaults: nil, starting: wallet)
    }

    func earn(_ amount: Int) {
        wallet.earn(amount)
        write()
    }

    @discardableResult
    func buy(_ borough: Borough) -> Bool {
        let bought = wallet.buy(borough)
        if bought { write() }
        return bought
    }

    /// Move to a borough, and remember it for next launch.
    @discardableResult
    func play(_ borough: Borough) -> Bool {
        let moved = wallet.play(borough)
        if moved { write() }
        return moved
    }

    /// Ask for the whole city, and remember that for next launch too.
    @discardableResult
    func playAnywhere() -> Bool {
        let moved = wallet.playAnywhere()
        if moved { write() }
        return moved
    }

    /// Forget all of it: the money, the career, the boroughs bought, and where the
    /// player was — a fresh wallet is in Manhattan.
    ///
    /// The saved copy is removed rather than overwritten with an empty one, because the
    /// promise settings makes is that the data is gone, not that it has been set back to
    /// nought. After this the app is in the state it was in before it was ever played.
    ///
    /// This wallet is the only game data the app keeps anywhere, so this really is all of
    /// it — no file, no keychain entry, nothing on a server. The counting keeps two things
    /// of its own beside it, a switch and a random number, and `Analytics.eraseEverything`
    /// deals with the number; settings calls both.
    func erase() {
        wallet = Wallet()
        defaults?.removeObject(forKey: key)
    }

    // MARK: - Reading and writing

    /// Anything unreadable is treated as nothing saved.
    ///
    /// Losing a wallet is bad; refusing to open is worse, and a crash on launch over a
    /// corrupted preference would be the app's own doing. The version is in the key
    /// rather than in the data, so a future shape gets a new key and an old one is left
    /// where it is instead of being half-read.
    private static func read(from defaults: UserDefaults?, key: String) -> Wallet? {
        guard let data = defaults?.data(forKey: key) else { return nil }
        return try? JSONDecoder().decode(Wallet.self, from: data)
    }

    private func write() {
        guard let defaults, let data = try? JSONEncoder().encode(wallet) else { return }
        defaults.set(data, forKey: key)
    }
}
