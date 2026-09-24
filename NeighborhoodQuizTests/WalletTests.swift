import XCTest
@testable import NeighborhoodQuiz

/// The money: what a round pays, what the next borough costs, and the one thing the
/// game must never do, which is take payment for a place it cannot open.
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

        XCTAssertEqual(wallet.balance, 500 - Borough.ladder[0])
        XCTAssertEqual(wallet.earned, 500, "a career total never goes down")
        XCTAssertEqual(wallet.rounds, 14, "buying is not playing")
        XCTAssertTrue(wallet.has(.brooklyn))
        XCTAssertEqual(wallet.nextPrice, Borough.ladder[1], "on to the next rung")
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
        var wallet = Wallet(balance: 500)
        XCTAssertTrue(wallet.buy(.brooklyn))

        // `playable` asks the real city, and Brooklyn is drawn in it now: bought means
        // there is somewhere to go. It is not *where you are* until you go there,
        // which is the next section.
        XCTAssertTrue(wallet.has(.brooklyn))
        XCTAssertEqual(wallet.playable, [.manhattan, .brooklyn])
        XCTAssertEqual(wallet.current, .manhattan, "buying is not moving")
    }

    func testWhatCannotBeAffordedCannotBeBought() {
        var wallet = Wallet(balance: Borough.ladder[0] - 1)

        XCTAssertFalse(wallet.canAfford(.brooklyn))
        XCTAssertFalse(wallet.canBuy(.brooklyn))
        XCTAssertFalse(wallet.buy(.brooklyn))
        XCTAssertEqual(wallet.balance, Borough.ladder[0] - 1)
    }

    /// The guard that matters most.
    ///
    /// Every borough is listed, and from Queens on none of them is drawn yet. The next
    /// borough costs the same whichever one it is, so a player with the price of one
    /// in hand has the price of Queens in hand — and if the button took it, they would
    /// have paid for a blank page. Affordable and buyable are two different questions
    /// for exactly this reason.
    ///
    /// This picks the first undrawn borough rather than naming one, so when a borough
    /// does get a map it stops applying to it and applies to the next one along — it
    /// moved from Brooklyn to Queens without being touched — and when they are all
    /// drawn it has nothing left to guard and says so.
    func testMoneyIsNeverTakenForABoroughWithNoMapBehindIt() {
        guard let undrawn = Borough.buyable.first(where: { !$0.isDrawn }) else {
            return  // every borough is drawn; there is nothing left to protect against
        }

        var wallet = Wallet(balance: Borough.ladder[0] * 2)

        XCTAssertTrue(wallet.canAfford(undrawn), "the money is there")
        XCTAssertFalse(wallet.canBuy(undrawn), "but there is nowhere to go")
        XCTAssertFalse(wallet.buy(undrawn))
        XCTAssertEqual(wallet.balance, Borough.ladder[0] * 2, "not a dollar of it was taken")
        XCTAssertFalse(wallet.has(undrawn))
    }

    // MARK: - Where the player is

    func testAFreshWalletIsInManhattan() {
        XCTAssertEqual(Wallet().playing, .manhattan)
        XCTAssertEqual(Wallet().current, .manhattan)
    }

    /// The two halves of the guard: not yours, and not drawn. Either one refuses, and
    /// a refusal leaves the player where they were.
    func testYouCannotGoSomewhereYouDoNotOwnOrThatIsNotDrawn() {
        var wallet = Wallet(balance: 5_000)

        XCTAssertFalse(wallet.play(.brooklyn), "drawn, but not bought")
        XCTAssertEqual(wallet.current, .manhattan)

        guard let undrawn = Borough.buyable.first(where: { !$0.isDrawn }) else { return }
        wallet = Wallet(balance: 0, bought: [undrawn])
        XCTAssertTrue(wallet.has(undrawn), "owned, however that happened")
        XCTAssertFalse(wallet.play(undrawn), "but there is no map to play it on")
        XCTAssertEqual(wallet.current, .manhattan)
    }

    func testBrooklynCanBePlayedOnceItIsBought() {
        var wallet = Wallet(balance: 500)
        XCTAssertTrue(wallet.buy(.brooklyn))
        XCTAssertTrue(wallet.play(.brooklyn))

        XCTAssertEqual(wallet.playing, .brooklyn)
        XCTAssertEqual(wallet.current, .brooklyn)
        XCTAssertTrue(wallet.play(.manhattan), "and back again, which is always allowed")
        XCTAssertEqual(wallet.current, .manhattan)
    }

    /// A wallet can say Brooklyn and not be able to mean it. There are two ways there:
    /// written by a build in which Brooklyn was drawn and read by one in which it is
    /// not, or a purchase that has since been erased. Both look the same to the wallet —
    /// `playing` names a borough `playable` does not hold — and both land the player in
    /// Manhattan rather than nowhere. Reached through the decoder because it is the
    /// only door: `play` will not put the wallet in this state on purpose.
    func testCurrentFallsBackToManhattanWhenPlayingIsNotPlayable() throws {
        let json = """
        {"balance": 0, "earned": 500, "rounds": 12, "bought": [], "playing": "brooklyn"}
        """
        let wallet = try JSONDecoder().decode(Wallet.self, from: Data(json.utf8))

        XCTAssertEqual(wallet.playing, .brooklyn, "what was written down is kept")
        XCTAssertEqual(wallet.current, .manhattan, "but not honoured")
    }

    // MARK: - The whole city

    /// A choice of one is not a choice. With only Manhattan open there is nothing for
    /// "anywhere" to add, so the wallet refuses and the pick stays the borough.
    func testAnywhereNeedsMoreThanOneBoroughToDrawFrom() {
        var wallet = Wallet()

        XCTAssertFalse(wallet.playAnywhere())
        XCTAssertFalse(wallet.anywhere)
        XCTAssertEqual(wallet.pick, .borough(.manhattan))
    }

    func testAnywhereIsAllowedOnceBrooklynIsOpen() {
        var wallet = Wallet(balance: 500)
        wallet.buy(.brooklyn)

        XCTAssertTrue(wallet.playAnywhere())
        XCTAssertTrue(wallet.anywhere)
        XCTAssertEqual(wallet.pick, .anywhere)
        XCTAssertEqual(wallet.current, .manhattan, "still somewhere, for the map to open on")
    }

    /// Asking for a borough is asking for that borough and not the whole city, so it
    /// takes the anywhere flag down with it — and the pick says so.
    func testPickingABoroughClearsAnywhere() {
        var wallet = Wallet(balance: 500)
        wallet.buy(.brooklyn)
        wallet.playAnywhere()
        XCTAssertEqual(wallet.pick, .anywhere)

        XCTAssertTrue(wallet.play(.brooklyn))

        XCTAssertFalse(wallet.anywhere)
        XCTAssertEqual(wallet.pick, .borough(.brooklyn))
        XCTAssertEqual(wallet.current, .brooklyn)
    }

    /// A wallet that asked for the whole city and then lost Brooklyn — erased, or read
    /// by a build that stopped drawing it — is a wallet with one borough, and a round
    /// "across the city" drawn from one borough would be an ordinary round wearing the
    /// wrong label. So the pick falls back to a borough, the way `current` falls back
    /// to Manhattan. Reached through the decoder, which is the only door: neither
    /// `play` nor `playAnywhere` will put the wallet in this state on purpose.
    func testThePickFallsBackToABoroughWhenBrooklynIsGone() throws {
        let json = """
        {"balance": 0, "earned": 500, "rounds": 12, "bought": [],
         "playing": "brooklyn", "anywhere": true}
        """
        let wallet = try JSONDecoder().decode(Wallet.self, from: Data(json.utf8))

        XCTAssertTrue(wallet.anywhere, "what was written down is kept")
        XCTAssertEqual(wallet.pick, .borough(.manhattan), "but not honoured")
    }

    // MARK: - The ladder

    /// One rung per borough that can be bought, each dearer than the last. Strictly:
    /// two rungs at the same price would mean a borough that cost nothing extra, and
    /// the climb is the point.
    func testTheLadderClimbsInPrice() {
        let ladder = Borough.ladder
        XCTAssertTrue(zip(ladder, ladder.dropFirst()).allSatisfy { $0 < $1 }, "every rung dearer than the last")
        XCTAssertTrue(ladder.allSatisfy { $0 > 0 })
        XCTAssertEqual(ladder.count, Borough.buyable.count, "a rung for every borough there is to buy")
    }

    func testManhattanIsTheFreeOneAndTheRestAreBuyable() {
        XCTAssertEqual(Borough.free, .manhattan)
        XCTAssertTrue(Borough.manhattan.isFree)
        XCTAssertFalse(Borough.buyable.contains(.manhattan))
        XCTAssertTrue(Borough.buyable.allSatisfy { !$0.isFree })
        XCTAssertEqual(Borough.buyable.count, Borough.allCases.count - 1)
    }

    /// The next price is the next rung, and the rung is counted by purchases: fresh,
    /// it is the first; after one borough — whichever — it is the second; with the
    /// whole city bought there is no rung left and nothing to save for.
    func testTheNextPriceClimbsWithEachPurchase() {
        let city: Set<Borough> = [.manhattan, .brooklyn, .queens]
        var wallet = Wallet(balance: 1_000)
        XCTAssertEqual(wallet.nextPrice, Borough.ladder[0])

        XCTAssertTrue(wallet.buy(.brooklyn, drawn: city))
        XCTAssertEqual(wallet.nextPrice, Borough.ladder[1])

        wallet = Wallet(balance: 0, bought: Set(Borough.buyable))
        XCTAssertNil(wallet.nextPrice, "nothing left to save for")
        XCTAssertEqual(wallet.progress, 1)
        XCTAssertEqual(wallet.saved, 0)
        XCTAssertTrue(Borough.allCases.allSatisfy { !wallet.canAfford($0) }, "and nothing left to buy")
    }

    /// The order is the player's. The price is about how far along the ladder they
    /// are, not about which borough is which: Queens first is the first rung, and
    /// Brooklyn after it is the second, exactly as it would be the other way round.
    func testTheOrderIsThePlayersAndThePriceDoesNotCare() {
        let city: Set<Borough> = [.manhattan, .brooklyn, .queens]
        let start = Borough.ladder[0] + Borough.ladder[1]

        var queensFirst = Wallet(balance: start)
        XCTAssertTrue(queensFirst.buy(.queens, drawn: city))
        XCTAssertEqual(queensFirst.balance, start - Borough.ladder[0], "the first borough is the first rung, even Queens")
        XCTAssertTrue(queensFirst.buy(.brooklyn, drawn: city))
        XCTAssertEqual(queensFirst.balance, 0, "and the second is the second, even Brooklyn")

        var brooklynFirst = Wallet(balance: start)
        XCTAssertTrue(brooklynFirst.buy(.brooklyn, drawn: city))
        XCTAssertEqual(brooklynFirst.balance, start - Borough.ladder[0])
        XCTAssertTrue(brooklynFirst.buy(.queens, drawn: city))
        XCTAssertEqual(brooklynFirst.balance, 0)

        XCTAssertEqual(queensFirst.bought, brooklynFirst.bought, "both roads end in the same city")
    }

    func testProgressRunsFromEmptyToFullAndStopsThere() {
        XCTAssertEqual(Wallet().progress, 0)
        XCTAssertEqual(Wallet(balance: Borough.ladder[0] / 2).progress, 0.5, accuracy: 0.001)
        XCTAssertEqual(Wallet(balance: Borough.ladder[0]).progress, 1)
        XCTAssertEqual(Wallet(balance: Borough.ladder[0] * 10).progress, 1, "never past full")
    }

    /// What the ladder prints under the bar. Once the money is there the bar is full, and
    /// the count beside it has to agree with the bar rather than with the balance —
    /// "$240 of $200" reads as a bug even though both numbers are true. And it is the
    /// next rung it is measured against, which moves up after a purchase.
    func testWhatIsSavedNeverExceedsTheNextPrice() {
        XCTAssertEqual(Wallet(balance: 0).saved, 0)
        XCTAssertEqual(Wallet(balance: 140).saved, 140)
        XCTAssertEqual(Wallet(balance: 200).saved, 200)
        XCTAssertEqual(Wallet(balance: 240).saved, 200, "not $240 of $200")
        XCTAssertEqual(Wallet(balance: 9_999).saved, Borough.ladder[0])
        XCTAssertEqual(Wallet(balance: 9_999, bought: [.brooklyn]).saved, Borough.ladder[1], "one rung up")
    }

    // MARK: - How long the first one takes

    /// Not a rule so much as the tuning written down. A perfect round is fifty dollars,
    /// so the first borough is four of them — and since nobody plays perfectly, really
    /// more like six or seven. If either number moves, this is the line that says what
    /// it did to the climb.
    func testTheFirstBoroughIsAboutFourPerfectRoundsAway() {
        let perfect = QuizRound.questionCount * (QuizRound.points.first ?? 0)
        XCTAssertEqual(perfect, 50)
        XCTAssertEqual(Borough.ladder[0] / perfect, 4)
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

    /// Every wallet saved before Brooklyn was drawn has no `playing` in it, and they are
    /// all filed under the same `wallet.v1` key the new ones are. A decoder that refused
    /// the old shape would have the bank read it as nothing saved, and a player would
    /// open the update to an empty balance. So the field is optional on the way in and
    /// means Manhattan when it is missing, which is where everybody was.
    func testAWalletWrittenBeforeBrooklynStillReads() throws {
        let json = """
        {"balance": 140, "earned": 440, "rounds": 11, "bought": []}
        """
        let wallet = try JSONDecoder().decode(Wallet.self, from: Data(json.utf8))

        XCTAssertEqual(wallet.balance, 140)
        XCTAssertEqual(wallet.earned, 440)
        XCTAssertEqual(wallet.rounds, 11)
        XCTAssertTrue(wallet.bought.isEmpty)
        XCTAssertEqual(wallet.playing, .manhattan)
        XCTAssertEqual(wallet.current, .manhattan)
    }

    /// `anywhere` is newer than `playing`, and a wallet written between the two has the
    /// one and not the other. Missing means one borough, which is all there used to be.
    func testAWalletWrittenBeforeAnywhereStillReads() throws {
        let json = """
        {"balance": 340, "earned": 640, "rounds": 15, "bought": ["brooklyn"], "playing": "brooklyn"}
        """
        let wallet = try JSONDecoder().decode(Wallet.self, from: Data(json.utf8))

        XCTAssertFalse(wallet.anywhere)
        XCTAssertEqual(wallet.pick, .borough(.brooklyn))
        XCTAssertEqual(wallet.playable, [.manhattan, .brooklyn], "so anywhere could be asked for")
    }

    func testAskingForTheWholeCitySurvivesTheTripToo() throws {
        var wallet = Wallet(balance: 500)
        wallet.buy(.brooklyn)
        wallet.playAnywhere()

        let data = try JSONEncoder().encode(wallet)
        let read = try JSONDecoder().decode(Wallet.self, from: data)

        XCTAssertEqual(read, wallet)
        XCTAssertEqual(read.pick, .anywhere)
    }

    func testWhereThePlayerIsSurvivesTheTripToo() throws {
        var wallet = Wallet(balance: 500)
        wallet.buy(.brooklyn)
        wallet.play(.brooklyn)

        let data = try JSONEncoder().encode(wallet)
        let read = try JSONDecoder().decode(Wallet.self, from: data)

        XCTAssertEqual(read, wallet)
        XCTAssertEqual(read.current, .brooklyn)
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
