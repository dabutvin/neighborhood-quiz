import XCTest
@testable import NeighborhoodQuiz

/// The four tips: which one is up when, what they say, and who gets them.
@MainActor
final class TutorialTests: XCTestCase {
    private let suite = "TutorialTests.\(UUID().uuidString)"
    private var defaults: UserDefaults!

    override func setUpWithError() throws {
        defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
    }

    override func tearDown() {
        defaults.removePersistentDomain(forName: suite)
        defaults = nil
        super.tearDown()
    }

    private func coached(_ events: Tutorial.Event...) -> Tutorial {
        var tutorial = Tutorial(coaching: true)
        for event in events { tutorial.handle(event) }
        return tutorial
    }

    // MARK: - The order

    func testNothingIsUpUntilTheRoundStarts() {
        XCTAssertNil(Tutorial(coaching: true).step)
        XCTAssertEqual(coached(.roundStarted).step, .pick)
    }

    /// The whole of it, the way a first-time player who misses once goes through it.
    func testTheTipsFollowTheRound() {
        var tutorial = coached(.roundStarted)
        XCTAssertEqual(tutorial.step, .pick)

        tutorial.handle(.picked)
        XCTAssertEqual(tutorial.step, .answer, "something picked: the Answer button is next")

        tutorial.handle(.answered(.wrong))
        XCTAssertEqual(tutorial.step, .goes(found: false))

        tutorial.handle(.picked)
        XCTAssertNil(tutorial.step, "read and acted on: nothing more until the round is over")

        tutorial.handle(.answered(.right))
        XCTAssertNil(tutorial.step, "later answers bring nothing back")

        tutorial.handle(.roundFinished)
        XCTAssertEqual(tutorial.step, .money)
        XCTAssertTrue(tutorial.isCoaching, "still up until the card is left")

        tutorial.handle(.summaryLeft)
        XCTAssertNil(tutorial.step)
        XCTAssertFalse(tutorial.isCoaching, "the last tip read is the end of it")
    }

    func testAFirstGoFindIsToldItWasAFind() {
        XCTAssertEqual(coached(.roundStarted, .picked, .answered(.right)).step, .goes(found: true))
    }

    /// The Answer tip is about a button, and a pick put down takes the button with it.
    func testPuttingThePickDownGoesBackToTheFirstTip() {
        XCTAssertEqual(coached(.roundStarted, .picked, .unpicked).step, .pick)
        XCTAssertEqual(coached(.roundStarted, .picked, .unpicked, .picked).step, .answer)
    }

    func testTheGoesTipStaysUntilTheNextPick() {
        var tutorial = coached(.roundStarted, .picked, .answered(.wrong))

        tutorial.handle(.unpicked)
        XCTAssertEqual(tutorial.step, .goes(found: false), "a tap on water is not reading it")
    }

    /// Got it puts the tip about tries away and leaves the last tip to come.
    func testGotItPutsTheTriesTipAwayAndKeepsCoaching() {
        var tutorial = coached(.roundStarted, .picked, .answered(.right), .dismissed)
        XCTAssertNil(tutorial.step)
        XCTAssertTrue(tutorial.isCoaching)

        tutorial.handle(.roundFinished)
        XCTAssertEqual(tutorial.step, .money, "the last tip still comes")
    }

    /// Only the tip about tries has a Got it; the others have a Skip, which ends them all.
    func testOnlyTheTriesTipCanBePutAway() {
        XCTAssertTrue(Tutorial.Step.goes(found: true).isDismissible)
        XCTAssertTrue(Tutorial.Step.goes(found: false).isDismissible)
        XCTAssertFalse(Tutorial.Step.pick.isDismissible)
        XCTAssertFalse(Tutorial.Step.answer.isDismissible)
        XCTAssertFalse(Tutorial.Step.money.isDismissible)

        XCTAssertEqual(coached(.roundStarted, .dismissed).step, .pick, "Got it is not a Skip")
    }

    func testAGuessThatCountsForNothingMovesNothing() {
        XCTAssertEqual(coached(.roundStarted, .picked, .answered(.ignored)).step, .answer)
    }

    /// Walking out of the first round is not the end of the tips: they have not all been
    /// shown. The next round starts them over.
    func testLeavingPartWayStartsThemOverNextRound() {
        var tutorial = coached(.roundStarted, .picked, .answered(.wrong), .roundLeft)
        XCTAssertNil(tutorial.step)
        XCTAssertTrue(tutorial.isCoaching)

        tutorial.handle(.roundStarted)
        XCTAssertEqual(tutorial.step, .pick)
    }

    func testSkippingEndsItFromAnyTip() {
        for tutorial in [
            coached(.roundStarted, .skipped),
            coached(.roundStarted, .picked, .skipped),
            coached(.roundStarted, .picked, .answered(.right), .skipped),
            coached(.roundStarted, .roundFinished, .skipped)
        ] {
            XCTAssertNil(tutorial.step)
            XCTAssertFalse(tutorial.isCoaching)
        }
    }

    func testAPlayerWhoIsNotBeingCoachedIsToldNothing() {
        var tutorial = Tutorial(coaching: false)
        for event: Tutorial.Event in [.roundStarted, .picked, .answered(.right), .roundFinished] {
            tutorial.handle(event)
            XCTAssertNil(tutorial.step)
        }
    }

    func testOnceItIsOverItStaysOver() {
        var tutorial = coached(.roundStarted, .roundFinished, .summaryLeft)

        tutorial.handle(.roundStarted)

        XCTAssertNil(tutorial.step, "the second round is not coached")
    }

    // MARK: - What they say

    func testTheTipsAreNumberedOneToFour() {
        let steps: [Tutorial.Step] = [.pick, .answer, .goes(found: true), .money]
        XCTAssertEqual(steps.map(\.number), [1, 2, 3, 4])
        XCTAssertEqual(Tutorial.Step.goes(found: false).number, 3, "one tip, whichever way it went")
        XCTAssertEqual(Set(steps.map(\.name)).count, steps.count)
    }

    /// The points are said in words on two of the tips, and must be the points the round
    /// actually pays.
    func testTheGoesTipSaysWhatTheGoesArePaid() {
        for found in [true, false] {
            let body = Tutorial.Step.goes(found: found).tip(for: Wallet()).body
            for points in QuizRound.points {
                XCTAssertTrue(body.contains(Money.text(points)), "\(body) should say \(points)")
            }
        }
        XCTAssertTrue(
            Tutorial.Step.goes(found: false).tip(for: Wallet()).body
                .contains("\(QuizRound.tries - 1) tries left")
        )
    }

    func testTheMoneyTipSaysWhatTheNextBoroughCosts() {
        let first = Borough.ladder[0]
        let saving = Tutorial.Step.money.tip(for: Wallet(balance: 38, rounds: 1)).body
        XCTAssertTrue(saving.contains(Money.text(first)), saving)

        let enough = Tutorial.Step.money.tip(for: Wallet(balance: first, rounds: 9)).body
        XCTAssertFalse(enough.contains("At \(Money.text(first))"), "it is not a target any more")
        XCTAssertTrue(enough.contains("enough"), enough)
    }

    func testEveryTipHasSomethingToSay() {
        for step: Tutorial.Step in [.pick, .answer, .goes(found: true), .goes(found: false), .money] {
            let tip = step.tip(for: Wallet())
            XCTAssertFalse(tip.title.isEmpty)
            XCTAssertFalse(tip.body.isEmpty)
        }
    }

    // MARK: - Who gets them

    func testANewPlayerIsCoached() {
        XCTAssertTrue(TutorialRecord(defaults: defaults).shouldCoach(Wallet()))
    }

    /// Somebody who played before there were tips learned without them, and an update
    /// should not start coaching them.
    func testAPlayerWithRoundsBehindThemIsNot() {
        XCTAssertFalse(TutorialRecord(defaults: defaults).shouldCoach(Wallet(balance: 30, rounds: 3)))
    }

    func testFinishingIsRememberedAcrossLaunches() {
        TutorialRecord(defaults: defaults).finish()

        XCTAssertFalse(TutorialRecord(defaults: defaults).shouldCoach(Wallet()))
    }

    func testHowToPlayCoachesAnybodyAgain() {
        let record = TutorialRecord(defaults: defaults)
        record.finish()

        record.replay()

        XCTAssertTrue(record.shouldCoach(Wallet(balance: 900, rounds: 40)))
    }

    func testAStagedRecordCoachesNobodyAndKeepsNothing() {
        let staged = TutorialRecord(defaults: nil)
        staged.replay()

        XCTAssertFalse(staged.shouldCoach(Wallet()))
        XCTAssertNil(defaults.object(forKey: TutorialRecord.key))
    }

    /// "Delete all saved data" is a fresh install: the wallet goes, the record goes, and
    /// a fresh install is shown the tips — whether they were read, skipped or never seen.
    func testDeletingEverythingCoachesTheNextRoundAgain() {
        let decisions: [(TutorialRecord) -> Void] = [{ $0.finish() }, { $0.replay() }, { _ in }]
        for decided in decisions {
            let bank = Bank(defaults: defaults)
            bank.earn(30)
            let record = TutorialRecord(defaults: defaults)
            decided(record)

            record.erase()
            bank.erase()

            XCTAssertNil(defaults.object(forKey: TutorialRecord.key), "nothing left behind")
            XCTAssertTrue(TutorialRecord(defaults: defaults).shouldCoach(bank.wallet))
        }
    }

    func testErasingAStagedRecordTouchesNothing() {
        TutorialRecord(defaults: defaults).finish()

        TutorialRecord(defaults: nil).erase()

        XCTAssertEqual(defaults.object(forKey: TutorialRecord.key) as? Bool, true)
    }

    // MARK: - The camera

    func testEveryTutorialShotShowsItsTip() {
        XCTAssertEqual(QuizView.Stage.tutorial.tip, .pick)
        XCTAssertEqual(QuizView.Stage.tutorialPicked.tip, .answer)
        XCTAssertEqual(QuizView.Stage.tutorialOver.tip, .money)
        XCTAssertEqual(QuizView.Stage.tutorialGoes.tip, .goes(found: false))
        XCTAssertNil(QuizView.Stage.asking.tip, "the other shots are of a player past the tips")

        let staged = Tutorial.showing(.answer)
        XCTAssertEqual(staged.step, .answer)
        XCTAssertTrue(staged.isCoaching)
    }
}
