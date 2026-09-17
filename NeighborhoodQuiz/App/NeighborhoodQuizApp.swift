import SwiftUI

@main
struct NeighborhoodQuizApp: App {
    private let screen = Screen(arguments: ProcessInfo.processInfo.arguments)

    var body: some Scene {
        WindowGroup {
            switch screen {
            case .quiz(let stage):
                QuizView(stage: stage)
            case .map(let opening, let showing):
                HomeView(opening: opening, showing: showing)
            }
        }
    }
}

/// What the app opens on.
///
/// A launch with no arguments — which is every launch a person makes — starts a fresh
/// round of ten places drawn at random. Everything else here is for the screenshot runs.
///
/// The `-quiz-*` arguments play a fixed round forward to a particular moment: something
/// picked and waiting on the button, two goes gone, the island half filled in, a place
/// the round gave away, the end of it. They go through `QuizRound.guess` exactly as a
/// player's taps would, so each one is a real state of the game rather than a mock-up of
/// one — which is the only reason a screenshot of it is worth looking at.
enum Screen: Equatable {
    case quiz(stage: QuizView.Stage?)
    case map(opening: MapBoard.Opening, showing: String?)

    init(arguments: [String]) {
        if let stage = QuizView.Stage.allCases.first(where: { arguments.contains("-quiz-\($0.rawValue)") }) {
            self = .quiz(stage: stage)
        } else if arguments.contains("-map-neighborhood") {
            // Greenwich Village: small enough to fill a phone, known to anybody who has
            // heard of Manhattan, and a tidy shape to show a highlight on.
            self = .map(opening: .neighborhood("Greenwich Village"), showing: "Greenwich Village")
        } else if arguments.contains("-map-zoomed") {
            self = .map(opening: .midtown, showing: nil)
        } else if arguments.contains("-map") {
            self = .map(opening: .island, showing: nil)
        } else {
            self = .quiz(stage: nil)
        }
    }
}
