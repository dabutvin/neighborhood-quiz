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

        XCTAssertTrue(bank.buy(.brooklyn))

        let next = Bank(defaults: defaults)
        XCTAssertEqual(next.wallet.balance, 1_000 - Borough.ladder[0])
        XCTAssertEqual(next.wallet.bought, [.brooklyn])
    }

    /// Where the player is goes down with the money, so the app opens where it was
    /// closed. And a move that is refused writes nothing: there is nothing to write.
    func testWhereThePlayerIsIsWrittenDownToo() {
        let bank = Bank(defaults: defaults)
        XCTAssertFalse(bank.play(.brooklyn), "not bought")
        XCTAssertNil(defaults.data(forKey: Bank.storageKey), "a refusal is not worth a write")

        bank.earn(1_000)
        bank.buy(.brooklyn)
        XCTAssertTrue(bank.play(.brooklyn))

        XCTAssertEqual(Bank(defaults: defaults).wallet.current, .brooklyn)
    }

    /// Asking for the whole city is written down like a move to a borough is, and a
    /// refusal — one borough is no city — writes nothing. Picking a borough afterwards
    /// takes the anywhere flag down, and that is written too.
    func testAskingForTheWholeCityIsWrittenDownToo() {
        let bank = Bank(defaults: defaults)
        XCTAssertFalse(bank.playAnywhere(), "only Manhattan is open")
        XCTAssertNil(defaults.data(forKey: Bank.storageKey), "a refusal is not worth a write")

        bank.earn(1_000)
        bank.buy(.brooklyn)
        XCTAssertTrue(bank.playAnywhere())
        XCTAssertEqual(Bank(defaults: defaults).wallet.pick, .anywhere)

        XCTAssertTrue(bank.play(.brooklyn))
        XCTAssertEqual(Bank(defaults: defaults).wallet.pick, .borough(.brooklyn))
    }

    /// Erasing puts the player back in Manhattan along with everything else: a fresh
    /// wallet is in Manhattan, and erasing gives a fresh wallet.
    func testErasingSendsThePlayerHome() {
        let bank = Bank(defaults: defaults)
        bank.earn(1_000)
        bank.buy(.brooklyn)
        bank.play(.brooklyn)
        XCTAssertEqual(bank.wallet.current, .brooklyn)

        bank.erase()

        XCTAssertEqual(bank.wallet.current, .manhattan)
        XCTAssertEqual(bank.wallet.pick, .borough(.manhattan))
        XCTAssertEqual(Bank(defaults: defaults).wallet.current, .manhattan)
    }

    /// A round's score is written down against what it was about, in the same write as
    /// the money, and is still there next launch.
    func testABestIsKeptAcrossLaunches() {
        let bank = Bank(defaults: defaults)
        XCTAssertTrue(bank.earn(38, on: .borough(.manhattan)), "a first round sets the best")
        XCTAssertFalse(bank.earn(20, on: .borough(.manhattan)), "a worse one does not")

        let next = Bank(defaults: defaults)

        XCTAssertEqual(next.wallet.best(for: .borough(.manhattan)), 38)
        XCTAssertEqual(next.wallet.balance, 58)
    }

    /// Earning without saying what the round was about records no best — which is how
    /// every test above pays, and must stay harmless.
    func testEarningWithoutAChoiceRecordsNoBest() {
        let bank = Bank(defaults: defaults)
        XCTAssertFalse(bank.earn(38))
        XCTAssertNil(bank.wallet.best(for: .borough(.manhattan)))
    }

    /// "Delete all saved data" takes the records with the money.
    func testErasingForgetsTheBests() {
        let bank = Bank(defaults: defaults)
        bank.earn(44, on: .anywhere)

        bank.erase()

        XCTAssertNil(bank.wallet.best(for: .anywhere))
        XCTAssertNil(Bank(defaults: defaults).wallet.best(for: .anywhere))
    }
}
