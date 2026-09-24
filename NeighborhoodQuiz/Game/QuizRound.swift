import Foundation

/// A round of the quiz: ten neighborhoods to find, three goes at each, and what those
/// goes were worth.
///
/// The whole of the game's rules live here, and none of the drawing does. A round knows
/// nothing about maps, taps or SwiftUI — it is asked whether a `Place` was the one and
/// answers. That is what lets the rules be tested without a screen, and it is why the
/// scoring below could be argued about in a test rather than by squinting at a phone.
///
/// A place rather than a bare id, since the round stopped being about one borough. Ten
/// questions drawn from the whole city are ten neighbourhoods on up to five maps, and
/// an id alone cannot say which map it belongs to. Not generic over the question type,
/// tempting as that looks: the point values and the go names are static stored
/// properties, and a generic type is not allowed those.
///
/// ## Scoring
///
/// Five points for finding it straight away, three on the second go, one on the third,
/// and nothing at all if three goes are not enough — at which point the round shows you
/// where it was and moves on, because somebody who does not know is not going to find
/// out by guessing a fourth time.
///
/// Fifty is a perfect round. Counting up rather than down, which is the change from the
/// version before this one: with the goes capped there is a best possible score to climb
/// towards, and that reads as a score in a way that "the fewest guesses" never quite did.
struct QuizRound: Equatable {
    /// How many places a round asks for. Ten is a train ride rather than an evening,
    /// and short enough that a bad start is worth playing out.
    static let questionCount = 10

    /// Goes at each place before the round gives it to you.
    static let tries = 3

    /// What the first, second and third go are worth. Steep on purpose: knowing is meant
    /// to be worth much more than narrowing down, and the third-go point is there to be
    /// better than nothing rather than to be worth chasing.
    static let points = [5, 3, 1]

    /// The neighborhoods to find, in the order asked.
    let questions: [Place]

    /// Which question is being asked, counted from zero. Equal to `questions.count`
    /// once the round is over.
    private(set) var index = 0

    /// Points so far.
    private(set) var score = 0

    /// The places found, in the order they were found. The map leaves them filled in.
    private(set) var found: [Place] = []

    /// The places three goes were not enough for, which the round showed instead. The
    /// map leaves these too: being shown where Inwood was is the whole consolation for
    /// not knowing.
    private(set) var missed: [Place] = []

    /// How many places were found on the first go, on the second and on the third,
    /// indexed by the go. Together with `missed` it accounts for every question asked,
    /// which is what lets the end of a round be read as a breakdown rather than a single
    /// number with no working shown.
    private(set) var foundOn = [Int](repeating: 0, count: QuizRound.tries)

    /// How many places were found without a single wrong guess. Not the score, but the
    /// number people actually want to hear about themselves.
    var firstTime: Int { foundOn.first ?? 0 }

    /// What has been guessed and ruled out on the question being asked now. Kept so the
    /// map can show a player what they have already eliminated, so that guessing the
    /// same wrong place twice is not charged for twice — that is a slip of the thumb,
    /// not a second opinion — and because its size is how many goes have been used.
    private(set) var ruledOut: Set<Place> = []

    /// The neighborhood being asked for, or nothing once the round is over.
    var current: Place? {
        questions.indices.contains(index) ? questions[index] : nil
    }

    var isFinished: Bool { current == nil }

    /// Goes used on this question, and goes left.
    var triesUsed: Int { ruledOut.count }
    var triesLeft: Int { max(QuizRound.tries - triesUsed, 0) }

    /// What a round of this length is worth if every place is found first go.
    var perfectScore: Int { questions.count * (QuizRound.points.first ?? 0) }

    /// What a go is called, for the end-of-round breakdown.
    static func goName(_ go: Int) -> String {
        ["First go", "Second go", "Third go"][safe: go] ?? "Go \(go + 1)"
    }

    /// Ten of the pool, in an order nobody can predict. Takes the places to choose from
    /// so that a test can hand it a known set and a known generator — and so that the
    /// pool can be one borough or the whole city, which is the caller's business.
    init<Generator: RandomNumberGenerator>(
        askingAbout choices: [Place],
        count: Int = QuizRound.questionCount,
        using generator: inout Generator
    ) {
        questions = Array(choices.shuffled(using: &generator).prefix(count))
    }

    init(askingAbout choices: [Place], count: Int = QuizRound.questionCount) {
        var generator = SystemRandomNumberGenerator()
        self.init(askingAbout: choices, count: count, using: &generator)
    }

    /// A round that asks exactly these, in exactly this order. For the screenshot runs,
    /// which want the same places in the gallery every time, and for tests.
    init(asking questions: [Place]) {
        self.questions = questions
    }

    /// What a guess turned out to be.
    enum Answer: Equatable {
        /// That was the place. The round has moved on.
        case right
        /// Somewhere else, now ruled out, and there are goes left.
        case wrong
        /// Somewhere else on the last go. The place the round wanted is the last of
        /// `missed`, and the round has moved on.
        case missed
        /// Somewhere already ruled out on this question, or a guess after the round is
        /// over. Costs nothing and changes nothing.
        case ignored
    }

    /// Guess at the neighborhood being asked for.
    mutating func guess(_ place: Place) -> Answer {
        guard let current, triesLeft > 0 else { return .ignored }
        guard !ruledOut.contains(place) else { return .ignored }

        guard place != current else {
            let go = min(triesUsed, QuizRound.tries - 1)
            score += QuizRound.points[min(go, QuizRound.points.count - 1)]
            foundOn[go] += 1
            found.append(current)
            moveOn()
            return .right
        }

        ruledOut.insert(place)
        guard triesLeft > 0 else {
            missed.append(current)
            moveOn()
            return .missed
        }
        return .wrong
    }

    private mutating func moveOn() {
        index += 1
        ruledOut = []
    }
}

private extension Array {
    /// The element at an index, or nothing if the index is not one this array has.
    subscript(safe index: Int) -> Element? {
        indices.contains(index) ? self[index] : nil
    }
}
