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

    /// Somewhere that is not the answer and has not been tried yet.
    private func somewhereElse(in round: QuizRound) -> Int {
        (0..<80).first { $0 != round.current && !round.ruledOut.contains($0) } ?? -1
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

    func testARoundCanBeAskedForExactly() {
        let round = QuizRound(asking: [4, 8, 15])
        XCTAssertEqual(round.questions, [4, 8, 15], "In that order, for the gallery")
        XCTAssertEqual(round.current, 4)
    }

    // MARK: - What a go is worth

    func testFirstGoIsFiveSecondIsThreeThirdIsOne() {
        for used in 0..<QuizRound.tries {
            var round = QuizRound(asking: [99])
            for _ in 0..<used { _ = round.guess(somewhereElse(in: round)) }
            XCTAssertEqual(round.triesUsed, used)
            XCTAssertEqual(round.guess(99), .right)
            XCTAssertEqual(round.score, QuizRound.points[used], "Found on go \(used + 1)")
        }
        XCTAssertEqual(QuizRound.points, [5, 3, 1], "The numbers themselves")
    }

    func testAPerfectRoundIsFifty() {
        var round = self.round(of: Array(0..<40))
        for wanted in round.questions {
            XCTAssertEqual(round.guess(wanted), .right)
        }
        XCTAssertTrue(round.isFinished)
        XCTAssertEqual(round.score, 50)
        XCTAssertEqual(round.score, round.perfectScore, "Which is what perfect means")
        XCTAssertEqual(round.firstTime, 10)
        XCTAssertTrue(round.missed.isEmpty)
    }

    func testMissingEverythingScoresNothing() {
        var round = self.round(of: Array(0..<40))
        while !round.isFinished {
            for _ in 0..<QuizRound.tries { _ = round.guess(somewhereElse(in: round)) }
        }
        XCTAssertEqual(round.score, 0)
        XCTAssertEqual(round.missed.count, 10)
        XCTAssertTrue(round.found.isEmpty)
    }

    // MARK: - Running out of goes

    func testThreeWrongGuessesGiveThePlaceAwayAndMoveOn() {
        var round = QuizRound(asking: [99, 77])

        XCTAssertEqual(round.guess(somewhereElse(in: round)), .wrong)
        XCTAssertEqual(round.triesLeft, 2)
        XCTAssertEqual(round.guess(somewhereElse(in: round)), .wrong)
        XCTAssertEqual(round.triesLeft, 1)
        XCTAssertEqual(round.guess(somewhereElse(in: round)), .missed, "The last go")

        XCTAssertEqual(round.missed, [99], "The place it wanted, for the map to show")
        XCTAssertEqual(round.score, 0)
        XCTAssertEqual(round.current, 77, "And straight on to the next")
        XCTAssertEqual(round.triesLeft, QuizRound.tries, "With a full set of goes")
        XCTAssertTrue(round.ruledOut.isEmpty)
    }

    func testAMissedPlaceIsNotAFoundPlace() {
        var round = QuizRound(asking: [99])
        for _ in 0..<QuizRound.tries { _ = round.guess(somewhereElse(in: round)) }
        XCTAssertEqual(round.missed, [99])
        XCTAssertTrue(round.found.isEmpty, "Being shown where it was is not finding it")
        XCTAssertEqual(round.firstTime, 0)
        XCTAssertTrue(round.isFinished)
    }

    func testThereIsNoFourthGo() {
        var round = QuizRound(asking: [99, 77])
        for _ in 0..<QuizRound.tries { _ = round.guess(somewhereElse(in: round)) }
        // The round has moved on, so 99 is nobody's answer any more.
        XCTAssertEqual(round.guess(99), .wrong)
        XCTAssertEqual(round.score, 0)
        XCTAssertEqual(round.missed, [99], "And it was not missed a second time")
    }

    // MARK: - Playing one

    func testAWrongGuessCostsAGoAndRulesThePlaceOut() {
        var round = self.round(of: Array(0..<40))
        let wanted = round.current!
        let wrong = somewhereElse(in: round)

        XCTAssertEqual(round.guess(wrong), .wrong)
        XCTAssertTrue(round.ruledOut.contains(wrong))
        XCTAssertEqual(round.triesUsed, 1)
        XCTAssertEqual(round.current, wanted, "A wrong guess does not move the round on")
        XCTAssertEqual(round.score, 0)
    }

    func testGuessingTheSameWrongPlaceTwiceIsFree() {
        var round = self.round(of: Array(0..<40))
        let wrong = somewhereElse(in: round)

        XCTAssertEqual(round.guess(wrong), .wrong)
        // A thumb landing twice on the same place is a slip, not a second opinion.
        XCTAssertEqual(round.guess(wrong), .ignored)
        XCTAssertEqual(round.guess(wrong), .ignored)
        XCTAssertEqual(round.triesUsed, 1, "Still only one go gone")
        XCTAssertEqual(round.triesLeft, 2)
    }

    func testWhatWasRuledOutIsForgottenAtTheNextQuestion() {
        var round = self.round(of: Array(0..<40))
        _ = round.guess(somewhereElse(in: round))
        XCTAssertFalse(round.ruledOut.isEmpty)

        _ = round.guess(round.current!)
        XCTAssertTrue(round.ruledOut.isEmpty, "Each question starts with the whole island open")
        XCTAssertEqual(round.triesLeft, QuizRound.tries)
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
        var round = QuizRound(asking: [7])
        XCTAssertEqual(round.guess(7), .right)
        XCTAssertTrue(round.isFinished)

        let finished = round
        XCTAssertEqual(round.guess(7), .ignored)
        XCTAssertEqual(round.guess(3), .ignored)
        XCTAssertEqual(round, finished, "A finished round is finished")
    }

    // MARK: - What stays on the map

    func testNothingIsFoundBeforeAnythingIsFound() {
        let round = self.round(of: Array(0..<40))
        XCTAssertTrue(round.found.isEmpty)
        XCTAssertTrue(round.missed.isEmpty)
        XCTAssertEqual(round.score, 0)
        XCTAssertEqual(round.triesLeft, QuizRound.tries)
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
        let wrong = somewhereElse(in: round)
        _ = round.guess(wrong)
        XCTAssertTrue(round.found.isEmpty, "Guessing at a place is not finding it")
        XCTAssertFalse(round.found.contains(wrong))
    }

    /// Found, missed and crossed off are three different things the map draws three
    /// different ways, and every question must land in exactly one of them.
    func testEveryQuestionEndsUpEitherFoundOrMissedAndNeverBoth() {
        var round = self.round(of: Array(0..<40))
        var asked = 0
        while let wanted = round.current {
            asked += 1
            // Miss every third one, find the rest.
            if asked % 3 == 0 {
                for _ in 0..<QuizRound.tries { _ = round.guess(somewhereElse(in: round)) }
            } else {
                _ = round.guess(wanted)
            }
            for id in round.found {
                XCTAssertFalse(round.missed.contains(id), "\(id) is both found and missed")
                XCTAssertFalse(round.ruledOut.contains(id), "\(id) is both found and ruled out")
            }
        }
        XCTAssertEqual(round.found.count + round.missed.count, round.questions.count)
        XCTAssertEqual(Set(round.found).union(round.missed), Set(round.questions))
    }

    // MARK: - The score

    func testTheScoreIsTheSumOfWhatEachGoWasWorth() {
        var round = self.round(of: Array(0..<40))
        var expected = 0
        var asked = 0
        while let wanted = round.current {
            // Nought, one, then two wrong guesses, round and round.
            let wrongFirst = asked % QuizRound.tries
            for _ in 0..<wrongFirst { _ = round.guess(somewhereElse(in: round)) }
            XCTAssertEqual(round.guess(wanted), .right)
            expected += QuizRound.points[wrongFirst]
            XCTAssertEqual(round.score, expected)
            asked += 1
        }
        // Four found first go, three on the second, three on the third.
        XCTAssertEqual(round.score, 4 * 5 + 3 * 3 + 3 * 1)
        XCTAssertEqual(round.firstTime, 4)
    }

    func testTheScoreCanNeverBeatPerfect() {
        var round = self.round(of: Array(0..<40))
        while let wanted = round.current { _ = round.guess(wanted) }
        XCTAssertLessThanOrEqual(round.score, round.perfectScore)
    }
}
