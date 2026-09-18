import XCTest
@testable import NeighborhoodQuiz

/// The money: what a round pays, what a borough costs, and the one thing the game must
/// never do, which is take payment for a place it cannot open.
final class WalletTests: XCTestCase {

    // MARK: - Earning

    func testEarningRaisesTheBalanceAndTheCareerTotalTogether() {
        var wallet = Wallet()
        wallet.earn(38)
        wallet.earn(12)

        XCTAssertEqual(wallet.balance, 50)
        XCTAssertEqual(wallet.earned, 50)
        XCTAssertEqual(wallet.rounds, 2)
    }

    /// A round worth nothing is still a round played. Somebody who has been beaten ten
    /// times running has played ten rounds, and a counter that disagreed would be
    /// calling them a liar.
    func testARoundWorthNothingStillCounts() {
        var wallet = Wallet()
        wallet.earn(0)

        XCTAssertEqual(wallet.rounds, 1)
        XCTAssertEqual(wallet.balance, 0)
        XCTAssertEqual(wallet.earned, 0)
    }

    // MARK: - Manhattan

    func testManhattanIsOpenFromTheStartAndIsNeverBought() {
        let wallet = Wallet()

        XCTAssertTrue(wallet.has(.manhattan))
        XCTAssertTrue(wallet.bought.isEmpty)
        XCTAssertEqual(wallet.playable, [.manhattan])
    }

    // MARK: - Spending

    /// The heart of it: spending takes the money out, and leaves the career total alone.
    /// Buying Brooklyn must not make it look like you played less than you did.
    ///
    /// Played out in a city where Brooklyn is drawn, which is the whole point of `drawn`
    /// being a parameter — otherwise the one path that completes a purchase could never
    /// be run.
    func testBuyingSpendsTheBalanceAndLeavesTheCareerTotalWhereItIs() {
        let city: Set<Borough> = [.manhattan, .brooklyn]
        var wallet = Wallet(balance: 500, earned: 500, rounds: 14)

        XCTAssertTrue(wallet.buy(.brooklyn, drawn: city))

        XCTAssertEqual(wallet.balance, 500 - Borough.brooklyn.price)
        XCTAssertEqual(wallet.earned, 500, "a career total never goes down")
        XCTAssertEqual(wallet.rounds, 14, "buying is not playing")
        XCTAssertTrue(wallet.has(.brooklyn))
        XCTAssertEqual(wallet.saving, .queens, "on to the next rung")
    }

    func testTheSameBoroughCannotBeBoughtTwice() {
        let city: Set<Borough> = [.manhattan, .brooklyn]
        var wallet = Wallet(balance: 1_000, earned: 1_000)

        XCTAssertTrue(wallet.buy(.brooklyn, drawn: city))
        let afterFirst = wallet.balance

        XCTAssertFalse(wallet.canAfford(.brooklyn), "already owned, so nothing to afford")
        XCTAssertFalse(wallet.buy(.brooklyn, drawn: city))
        XCTAssertEqual(wallet.balance, afterFirst, "charged once")
    }

    func testBuyingOpensItForPlayingOnceItIsDrawn() {
        let city: Set<Borough> = [.manhattan, .brooklyn]
        var wallet = Wallet(balance: 500)
        XCTAssertTrue(wallet.buy(.brooklyn, drawn: city))

        // `playable` asks the real city, where Brooklyn still has no map: it is owned,
        // but there is nowhere to go until it is drawn.
        XCTAssertTrue(wallet.has(.brooklyn))
        XCTAssertEqual(wallet.playable, [.manhattan])
    }

    func testWhatCannotBeAffordedCannotBeBought() {
        var wallet = Wallet(balance: Borough.brooklyn.price - 1)

        XCTAssertFalse(wallet.canAfford(.brooklyn))
        XCTAssertFalse(wallet.canBuy(.brooklyn))
        XCTAssertFalse(wallet.buy(.brooklyn))
        XCTAssertEqual(wallet.balance, Borough.brooklyn.price - 1)
    }

    /// The guard that matters most.
    ///
    /// Every borough but Manhattan is priced and visible, and none of them is drawn yet.
    /// A player can therefore reach the money for Brooklyn today — and if the button took
    /// it, they would have paid two hundred dollars for a blank page. Affordable and
    /// buyable are two different questions for exactly this reason.
    ///
    /// When a borough does get a map, this test stops applying to it and applies to the
    /// next one along; when they are all drawn it has nothing left to guard and says so.
    func testMoneyIsNeverTakenForABoroughWithNoMapBehindIt() {
        guard let undrawn = Borough.forSale.first(where: { !$0.isDrawn }) else {
            return  // every borough is drawn; there is nothing left to protect against
        }

        var wallet = Wallet(balance: undrawn.price * 2)

        XCTAssertTrue(wallet.canAfford(undrawn), "the money is there")
        XCTAssertFalse(wallet.canBuy(undrawn), "but there is nowhere to go")
        XCTAssertFalse(wallet.buy(undrawn))
        XCTAssertEqual(wallet.balance, undrawn.price * 2, "not a dollar of it was taken")
        XCTAssertFalse(wallet.has(undrawn))
    }

    // MARK: - The ladder

    func testTheLadderClimbsInPrice() {
        let prices = Borough.allCases.map(\.price)
        XCTAssertEqual(prices, prices.sorted(), "allCases is the order you can afford them")
        XCTAssertEqual(Borough.manhattan.price, 0)
        XCTAssertTrue(Borough.forSale.allSatisfy { $0.price > 0 })
        XCTAssertEqual(Borough.forSale.count, Borough.allCases.count - 1)
    }

    func testTheNextThingSavedForIsTheCheapestOneNotOwned() {
        var wallet = Wallet()
        XCTAssertEqual(wallet.saving, .brooklyn)

        wallet = Wallet(balance: 0, bought: [.brooklyn])
        XCTAssertEqual(wallet.saving, .queens)

        wallet = Wallet(balance: 0, bought: Set(Borough.forSale))
        XCTAssertNil(wallet.saving, "nothing left to save for")
        XCTAssertEqual(wallet.progress, 1)
    }

    func testProgressRunsFromEmptyToFullAndStopsThere() {
        XCTAssertEqual(Wallet().progress, 0)
        XCTAssertEqual(Wallet(balance: Borough.brooklyn.price / 2).progress, 0.5, accuracy: 0.001)
        XCTAssertEqual(Wallet(balance: Borough.brooklyn.price).progress, 1)
        XCTAssertEqual(Wallet(balance: Borough.brooklyn.price * 10).progress, 1, "never past full")
    }

    // MARK: - How long the first one takes

    /// Not a rule so much as the tuning written down. A perfect round is fifty dollars,
    /// so Brooklyn is four of them — and since nobody plays perfectly, really more like
    /// six or seven. If either number moves, this is the line that says what it did to
    /// the climb.
    func testBrooklynIsAboutFourPerfectRoundsAway() {
        let perfect = QuizRound.questionCount * (QuizRound.points.first ?? 0)
        XCTAssertEqual(perfect, 50)
        XCTAssertEqual(Borough.brooklyn.price / perfect, 4)
    }

    // MARK: - Writing it down

    func testAWalletSurvivesBeingWrittenDownAndReadBack() throws {
        var wallet = Wallet(balance: 140, earned: 440, rounds: 11)
        wallet.earn(38)

        let data = try JSONEncoder().encode(wallet)
        let read = try JSONDecoder().decode(Wallet.self, from: data)

        XCTAssertEqual(read, wallet)
        XCTAssertEqual(read.balance, 178)
        XCTAssertEqual(read.earned, 478)
        XCTAssertEqual(read.rounds, 12)
    }

    /// A career total below the balance would mean spending money that was never earned.
    func testACareerTotalIsNeverLessThanWhatIsInHand() {
        XCTAssertEqual(Wallet(balance: 500, earned: 10).earned, 500)
        XCTAssertEqual(Wallet(balance: 500).earned, 500)
    }

    // MARK: - Spelling

    func testMoneyIsWrittenAsMoney() {
        XCTAssertEqual(Money.text(0), "$0")
        XCTAssertEqual(Money.text(38), "$38")
        XCTAssertTrue(Money.text(1_200).hasPrefix("$1"), "grouped however the locale groups")
    }
}
