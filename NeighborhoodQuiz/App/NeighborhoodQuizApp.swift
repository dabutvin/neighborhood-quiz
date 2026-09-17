import SwiftUI

@main
struct NeighborhoodQuizApp: App {
    private let screen = Screen(arguments: ProcessInfo.processInfo.arguments)

    var body: some Scene {
        WindowGroup {
            switch screen {
            case .quiz:
                QuizView()
            case .map(let opening, let showing):
                HomeView(opening: opening, showing: showing)
            }
        }
    }
}

/// What the app opens on.
///
/// A launch with no arguments — which is every launch a person makes — starts a round of
/// the quiz. The arguments are for the screenshot runs, which shoot the map on its own:
/// it is most of what this app is, and a regression in the drawing shows up far more
/// plainly on a screen with nothing else happening on it.
enum Screen: Equatable {
    case quiz
    case map(opening: MapBoard.Opening, showing: String?)

    init(arguments: [String]) {
        if arguments.contains("-map-neighborhood") {
            // Greenwich Village: small enough to fill a phone, known to anybody who has
            // heard of Manhattan, and a tidy shape to show a highlight on.
            self = .map(opening: .neighborhood("Greenwich Village"), showing: "Greenwich Village")
        } else if arguments.contains("-map-zoomed") {
            self = .map(opening: .midtown, showing: nil)
        } else if arguments.contains("-map") {
            self = .map(opening: .island, showing: nil)
        } else {
            self = .quiz
        }
    }
}
