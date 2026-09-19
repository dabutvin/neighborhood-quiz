import XCTest
@testable import NeighborhoodQuiz

/// The version string, and the one thing in the app that destroys something.
final class SettingsTests: XCTestCase {
    private let suite = "SettingsTests.\(UUID().uuidString)"
    private var defaults: UserDefaults!

    override func setUpWithError() throws {
        defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
    }

    override func tearDown() {
        defaults.removePersistentDomain(forName: suite)
        defaults = nil
        super.tearDown()
    }

    // MARK: - What build this is

    /// Both numbers, because two TestFlight builds of 0.1.0 are different software and
    /// the version alone cannot tell them apart.
    func testTheVersionIsShownWithTheBuildBehindIt() {
        let info: [String: Any] = ["CFBundleShortVersionString": "0.1.0", "CFBundleVersion": "7"]
        XCTAssertEqual(AppVersion.text(from: info), "0.1.0 (7)")
    }

    func testAMissingBuildNumberLeavesJustTheVersion() {
        XCTAssertEqual(AppVersion.text(from: ["CFBundleShortVersionString": "2.4"]), "2.4")
    }

    /// A bundle with nothing to say should not take the screen down with it.
    func testNothingToReadIsSaidRatherThanCrashed() {
        XCTAssertEqual(AppVersion.text(from: nil), AppVersion.unknown)
        XCTAssertEqual(AppVersion.text(from: [:]), AppVersion.unknown)
        XCTAssertEqual(AppVersion.text(from: ["CFBundleVersion": "9"]), AppVersion.unknown)
        XCTAssertEqual(
            AppVersion.text(from: ["CFBundleShortVersionString": "  ", "CFBundleVersion": "  "]),
            AppVersion.unknown,
            "blank is not a version"
        )
    }

    // MARK: - Throwing it all away

    func testAFreshWalletIsEmptyAndAPlayedOneIsNot() {
        XCTAssertTrue(Wallet().isEmpty)

        var played = Wallet()
        played.earn(38)
        XCTAssertFalse(played.isEmpty)

        // A round worth nothing still counts as having played, so it is still not empty.
        var beaten = Wallet()
        beaten.earn(0)
        XCTAssertFalse(beaten.isEmpty, "a round played is something to remember")
    }

    /// What the button promises. Everything goes, in this session and the next.
    func testErasingForgetsEverythingAndKeepsForgettingIt() {
        let bank = Bank(defaults: defaults)
        bank.earn(140)
        bank.earn(300)
        XCTAssertFalse(bank.wallet.isEmpty)

        bank.erase()

        XCTAssertTrue(bank.wallet.isEmpty)
        XCTAssertEqual(bank.wallet.balance, 0)
        XCTAssertEqual(bank.wallet.earned, 0, "the career total goes too")
        XCTAssertEqual(bank.wallet.rounds, 0)
        XCTAssertTrue(bank.wallet.bought.isEmpty)

        // And it is gone rather than set back to nought: the next launch finds nothing
        // saved, which is the state the app was in before it was ever played.
        XCTAssertNil(defaults.data(forKey: Bank.storageKey))
        XCTAssertTrue(Bank(defaults: defaults).wallet.isEmpty)
    }

    /// Erasing is the whole of it, so there must be nothing else left behind. The wallet
    /// is the only thing this app writes down anywhere; if that ever stops being true,
    /// this is the test that should start failing.
    func testTheWalletIsTheOnlyThingKept() {
        let bank = Bank(defaults: defaults)
        bank.earn(50)
        XCTAssertEqual(defaults.dictionaryRepresentation().keys.filter { $0 == Bank.storageKey }.count, 1)

        bank.erase()

        let ours = defaults.dictionaryRepresentation().keys.filter { $0.hasPrefix("wallet") }
        XCTAssertTrue(ours.isEmpty, "left behind: \(ours)")
    }

    func testErasingWhatIsAlreadyEmptyIsHarmless() {
        let bank = Bank(defaults: defaults)
        bank.erase()
        bank.erase()
        XCTAssertTrue(bank.wallet.isEmpty)
        XCTAssertNil(defaults.data(forKey: Bank.storageKey))
    }

    /// A staged bank writes nothing down, so the gallery's shot of the delete button can
    /// never reach a real player's money.
    func testErasingAStagedBankTouchesNothingOnDisk() {
        let real = Bank(defaults: defaults)
        real.earn(120)

        Bank.staged(Wallet(balance: 140, earned: 440, rounds: 11)).erase()

        XCTAssertEqual(Bank(defaults: defaults).wallet.balance, 120, "untouched")
    }
}
