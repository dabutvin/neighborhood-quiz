import Foundation

/// A round of the quiz: ten neighborhoods to find, in order, and what it cost to find
/// them.
///
/// The whole of the game's rules live here, and none of the drawing does. A round knows
/// nothing about maps, taps or SwiftUI — it is asked about a neighborhood by its id and
/// answers whether that was the one. That is what lets the rules be tested without a
/// screen, and it is why the scoring below could be argued about in a test rather than
/// by squinting at a phone.
///
/// ## Scoring
///
/// A wrong guess does not end a question — you keep going until you find the place — so
/// everybody finishes every round having found all ten. Which means the count of right
/// answers is always ten and tells you nothing, and the only number that carries any
/// information is **how many guesses it took**. Ten is perfect. Golf, in other words,
/// and the same reason golf counts that way: when the task is always completed, the cost
/// of completing it is the score.
///
/// Guesses, not taps. Touching the map costs nothing and can be taken back; it is
/// answering with a place that goes on the card.
struct QuizRound: Equatable {
    /// How many places a round asks for. Ten is a train ride rather than an evening,
    /// and short enough that a bad start is worth playing out.
    static let questionCount = 10

    /// The neighborhoods to find, by `DrawnNeighborhood.id`, in the order asked.
    let questions: [Int]

    /// Which question is being asked, counted from zero. Equal to `questions.count`
    /// once the round is over.
    private(set) var index = 0

    /// Every guess at a neighborhood, across the whole round. The score.
    private(set) var guesses = 0

    /// How many rounds were found without a single wrong guess. Not the score, but the
    /// number people actually want to hear about themselves.
    private(set) var firstTime = 0

    /// What has been guessed and ruled out on the question being asked now. Kept so the
    /// map can show a player what they have already eliminated, and so that tapping the
    /// same wrong place twice is not charged for twice — that is a slip of the thumb,
    /// not a second opinion.
    private(set) var ruledOut: Set<Int> = []

    /// The neighborhood being asked for, or nothing once the round is over.
    var current: Int? {
        questions.indices.contains(index) ? questions[index] : nil
    }

    var isFinished: Bool { current == nil }

    /// Every place found so far this round, in the order they were asked for.
    ///
    /// No state of its own, because there is none to keep: a question is only ever left
    /// by answering it, so the places found are exactly the questions already asked. The
    /// map fills them in as it goes, which turns a round into something that is visibly
    /// being assembled rather than ten unrelated questions in a row.
    var found: [Int] { Array(questions.prefix(index)) }

    /// Ten of the forty, in an order nobody can predict. Takes the ids to choose from so
    /// that a test can hand it a known set and a known generator.
    init<Generator: RandomNumberGenerator>(
        askingAbout choices: [Int],
        count: Int = QuizRound.questionCount,
        using generator: inout Generator
    ) {
        questions = Array(choices.shuffled(using: &generator).prefix(count))
    }

    init(askingAbout choices: [Int], count: Int = QuizRound.questionCount) {
        var generator = SystemRandomNumberGenerator()
        self.init(askingAbout: choices, count: count, using: &generator)
    }

    /// What a guess turned out to be.
    enum Answer: Equatable {
        /// That was the place. The round has moved on to the next question.
        case right
        /// That was somewhere else, which is now ruled out for this question.
        case wrong
        /// Somewhere already ruled out on this question, or a guess after the round is
        /// over. Costs nothing and changes nothing.
        case ignored
    }

    /// Guess at the neighborhood being asked for.
    mutating func guess(_ id: Int) -> Answer {
        guard let current else { return .ignored }
        guard !ruledOut.contains(id) else { return .ignored }

        guesses += 1
        guard id == current else {
            ruledOut.insert(id)
            return .wrong
        }

        if ruledOut.isEmpty { firstTime += 1 }
        index += 1
        ruledOut = []
        return .right
    }
}
