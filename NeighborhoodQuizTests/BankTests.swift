import XCTest
@testable import NeighborhoodQuiz

/// The reading and the writing. `Wallet` holds every rule about money and is tested on
/// its own; all that is left here is whether the money is still there next time.
final class BankTests: XCTestCase {
    private let suite = "BankTests.\(UUID().uuidString)"
    private var defaults: UserDefaults!

    override func setUpWithError() throws {
        defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
    }

    override func tearDown() {
        defaults.removePersistentDomain(forName: suite)
        defaults = nil
        super.tearDown()
    }

    func testAFreshBankStartsEmpty() {
        let bank = Bank(defaults: defaults)

        XCTAssertEqual(bank.wallet.balance, 0)
        XCTAssertEqual(bank.wallet.earned, 0)
        XCTAssertEqual(bank.wallet.rounds, 0)
    }

    /// The point of the class: quit the app, come back, still rich.
    func testMoneyIsStillThereNextLaunch() {
        let first = Bank(defaults: defaults)
        first.earn(38)
        first.earn(44)

        let second = Bank(defaults: defaults)

        XCTAssertEqual(second.wallet.balance, 82)
        XCTAssertEqual(second.wallet.earned, 82)
        XCTAssertEqual(second.wallet.rounds, 2)
    }

    func testTwoBanksOnDifferentShelvesDoNotSeeEachOther() throws {
        let other = try XCTUnwrap(UserDefaults(suiteName: "\(suite).other"))
        defer { other.removePersistentDomain(forName: "\(suite).other") }

        Bank(defaults: defaults).earn(100)

        XCTAssertEqual(Bank(defaults: other).wallet.balance, 0)
    }

    /// What the screenshot runs use. A staged bank can be spent from and earned into so
    /// the gallery can photograph any state, and none of it is ever written down — which
    /// is what keeps a photograph of the game away from a real player's money.
    func testAStagedBankRemembersNothing() {
        let staged = Bank.staged(Wallet(balance: 140, earned: 440, rounds: 11))
        staged.earn(38)

        XCTAssertEqual(staged.wallet.balance, 178, "it works while it is alive")
        XCTAssertNil(defaults.data(forKey: Bank.storageKey), "and writes nothing down")
        XCTAssertEqual(Bank(defaults: defaults).wallet.balance, 0)
    }

    /// Opening is more important than remembering.
    ///
    /// A preference that cannot be read is treated as no preference. Losing a wallet is
    /// bad; refusing to launch over a bad one would be worse, and it would be the app's
    /// own doing.
    func testUnreadableSavingsAreTreatedAsNoSavings() {
        defaults.set(Data("not a wallet".utf8), forKey: Bank.storageKey)

        let bank = Bank(defaults: defaults)

        XCTAssertEqual(bank.wallet.balance, 0)
        XCTAssertEqual(bank.wallet.rounds, 0)
    }

    /// A new wallet shape gets a new key rather than half-reading an old one.
    func testSavingsAreFiledUnderAVersionedKey() {
        XCTAssertTrue(Bank.storageKey.contains("v1"))
    }

    func testBuyingIsWrittenDownToo() {
        let bank = Bank(defaults: defaults)
        bank.earn(1_000)

        // Nothing but Manhattan is drawn, so nothing can actually be bought yet; what is
        // checked here is that the earning behind it survived the trip.
        XCTAssertFalse(bank.buy(.brooklyn))
        XCTAssertEqual(Bank(defaults: defaults).wallet.balance, 1_000)
        XCTAssertTrue(Bank(defaults: defaults).wallet.bought.isEmpty)
    }
}
