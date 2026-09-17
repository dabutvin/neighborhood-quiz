import XCTest
@testable import NeighborhoodQuiz

/// The rules of the game, checked without a map in sight. `QuizRound` is deliberately
/// free of anything to do with drawing, so everything the game does can be argued about
/// here rather than by squinting at a phone.
final class QuizRoundTests: XCTestCase {

    /// Splitmix64: a generator that shuffles as well as a real one and does it the same
    /// way every time, so a round's ten questions are known before it starts.
    private struct Predictable: RandomNumberGenerator {
        private var state: UInt64 = 0x243F_6A88_85A3_08D3

        mutating func next() -> UInt64 {
            state &+= 0x9E37_79B9_7F4A_7C15
            var z = state
            z = (z ^ (z >> 30)) &* 0xBF58_476D_1CE4_E5B9
            z = (z ^ (z >> 27)) &* 0x94D0_49BB_1331_11EB
            return z ^ (z >> 31)
        }
    }

    private func round(of choices: [Int], count: Int = QuizRound.questionCount) -> QuizRound {
        var generator = Predictable()
        return QuizRound(askingAbout: choices, count: count, using: &generator)
    }

    // MARK: - Making one

    func testARoundAsksForTenOfTheForty() {
        let round = self.round(of: Array(0..<40))
        XCTAssertEqual(round.questions.count, 10)
        XCTAssertEqual(Set(round.questions).count, 10, "The same place is never asked for twice")
        for id in round.questions {
            XCTAssertTrue((0..<40).contains(id))
        }
    }

    func testARoundIsNotAlwaysTheSameTen() {
        var first = SystemRandomNumberGenerator()
        var second = SystemRandomNumberGenerator()
        let a = QuizRound(askingAbout: Array(0..<40), using: &first)
        let b = QuizRound(askingAbout: Array(0..<40), using: &second)
        // Two draws of ten from forty match by chance about one time in 10^13.
        XCTAssertNotEqual(a.questions, b.questions)
    }

    func testARoundCannotAskForMoreThanThereIs() {
        let round = self.round(of: [1, 2, 3])
        XCTAssertEqual(round.questions.count, 3)
        XCTAssertFalse(round.isFinished)
    }

    // MARK: - Playing one

    func testFindingEveryPlaceFirstTimeIsAPerfectRound() {
        var round = self.round(of: Array(0..<40))
        for expected in round.questions {
            XCTAssertEqual(round.current, expected)
            XCTAssertEqual(round.guess(expected), .right)
        }
        XCTAssertTrue(round.isFinished)
        XCTAssertNil(round.current)
        XCTAssertEqual(round.guesses, 10, "Ten places, ten guesses, which is as well as it goes")
        XCTAssertEqual(round.firstTime, 10)
    }

    func testAWrongGuessCostsATapAndRulesThePlaceOut() {
        var round = self.round(of: Array(0..<40))
        let wanted = round.current!
        let wrong = round.questions.last(where: { $0 != wanted }) ?? (wanted + 1)

        XCTAssertEqual(round.guess(wrong), .wrong)
        XCTAssertEqual(round.guesses, 1)
        XCTAssertTrue(round.ruledOut.contains(wrong))
        XCTAssertEqual(round.current, wanted, "A wrong guess does not move the round on")
        XCTAssertEqual(round.firstTime, 0)
    }

    func testGuessingTheSameWrongPlaceTwiceIsFree() {
        var round = self.round(of: Array(0..<40))
        let wrong = round.questions.last(where: { $0 != round.current }) ?? 99

        XCTAssertEqual(round.guess(wrong), .wrong)
        // A thumb landing twice on the same place is a slip, not a second opinion.
        XCTAssertEqual(round.guess(wrong), .ignored)
        XCTAssertEqual(round.guess(wrong), .ignored)
        XCTAssertEqual(round.guesses, 1)
    }

    func testFindingItAfterAMissStillMovesOnButIsNotAFirstTime() {
        var round = self.round(of: Array(0..<40))
        let wanted = round.current!
        let wrong = round.questions.last(where: { $0 != wanted }) ?? (wanted + 1)

        XCTAssertEqual(round.guess(wrong), .wrong)
        XCTAssertEqual(round.guess(wanted), .right)
        XCTAssertEqual(round.guesses, 2)
        XCTAssertEqual(round.firstTime, 0)
        XCTAssertNotEqual(round.current, wanted)
    }

    func testWhatWasRuledOutIsForgottenAtTheNextQuestion() {
        var round = self.round(of: Array(0..<40))
        let wrong = round.questions.last(where: { $0 != round.current }) ?? 99
        _ = round.guess(wrong)
        XCTAssertFalse(round.ruledOut.isEmpty)

        _ = round.guess(round.current!)
        XCTAssertTrue(round.ruledOut.isEmpty, "Each question starts with the whole island open")
    }

    /// The place being asked for can be ruled out on an *earlier* question and must not
    /// stay ruled out when its own turn comes — otherwise a round could become
    /// unwinnable, which is the worst bug this file can catch.
    func testAPlaceGuessedEarlyCanStillBeTheAnswerLater() {
        var round = self.round(of: Array(0..<40))
        let asked = round.questions
        guard asked.count >= 2 else { return XCTFail("Need two questions") }

        let later = asked[1]
        XCTAssertEqual(round.guess(later), .wrong, "Guessed too early")
        XCTAssertEqual(round.guess(asked[0]), .right)

        XCTAssertEqual(round.current, later)
        XCTAssertFalse(round.ruledOut.contains(later))
        XCTAssertEqual(round.guess(later), .right, "The round would be unwinnable otherwise")
    }

    func testGuessingAfterTheRoundIsOverChangesNothing() {
        var round = self.round(of: [7], count: 1)
        XCTAssertEqual(round.guess(7), .right)
        XCTAssertTrue(round.isFinished)

        let finished = round
        XCTAssertEqual(round.guess(7), .ignored)
        XCTAssertEqual(round.guess(3), .ignored)
        XCTAssertEqual(round, finished, "A finished round is finished")
    }

    // MARK: - What stays on the map

    func testNothingIsFoundBeforeAnythingIsFound() {
        XCTAssertTrue(round(of: Array(0..<40)).found.isEmpty)
    }

    func testEveryPlaceFoundStaysFound() {
        var round = self.round(of: Array(0..<40))
        var expected: [Int] = []
        while let wanted = round.current {
            _ = round.guess(wanted)
            expected.append(wanted)
            XCTAssertEqual(round.found, expected, "The map fills in as the round goes on")
        }
        XCTAssertEqual(round.found, round.questions, "A finished round has the whole set")
    }

    func testAWrongGuessFindsNothing() {
        var round = self.round(of: Array(0..<40))
        let wrong = round.questions.last(where: { $0 != round.current }) ?? 99
        _ = round.guess(wrong)
        XCTAssertTrue(round.found.isEmpty, "Guessing at a place is not finding it")
        XCTAssertFalse(round.found.contains(wrong))
    }

    /// The two lists a player sees on the map are different things and must not overlap:
    /// crossed off is where the place is *not*, found is where it is.
    func testWhatIsFoundIsNeverAlsoCrossedOut() {
        var round = self.round(of: Array(0..<40))
        while let wanted = round.current {
            for wrong in Array(0..<40).filter({ $0 != wanted }).prefix(2) {
                _ = round.guess(wrong)
            }
            for id in round.found {
                XCTAssertFalse(round.ruledOut.contains(id), "\(id) is both found and ruled out")
            }
            _ = round.guess(wanted)
        }
    }

    // MARK: - The score

    func testGuessesCountEveryOneAcrossTheWholeRound() {
        var round = self.round(of: Array(0..<40))
        var expected = 0
        while let wanted = round.current {
            // Two wrong guesses, then the right one, every time.
            for wrong in Array(0..<40).filter({ $0 != wanted }).prefix(2) {
                XCTAssertEqual(round.guess(wrong), .wrong)
                expected += 1
            }
            XCTAssertEqual(round.guess(wanted), .right)
            expected += 1
        }
        XCTAssertEqual(round.guesses, expected)
        XCTAssertEqual(round.guesses, 30, "Ten questions at three guesses each")
        XCTAssertEqual(round.firstTime, 0)
    }

    func testTheScoreCanNeverBeatPerfect() {
        var round = self.round(of: Array(0..<40))
        while let wanted = round.current { _ = round.guess(wanted) }
        XCTAssertGreaterThanOrEqual(round.guesses, round.questions.count)
    }
}
