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
            case .boroughs(let wallet):
                StagedBoroughs(wallet)
            case .settings(let wallet):
                StagedSettings(wallet)
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
    case boroughs(Wallet)
    case settings(Wallet)

    init(arguments: [String]) {
        if arguments.contains("-settings") {
            // A wallet with a career behind it, so the row has something to describe
            // rather than offering to delete nothing.
            self = .settings(Wallet(balance: 140, earned: 440, rounds: 11))
        } else if arguments.contains("-boroughs") {
            // Saved up for Brooklyn and a career behind it: the rung that has something
            // to say, and the one state where the game has to explain itself.
            self = .boroughs(Wallet(balance: 240, earned: 940, rounds: 24))
        } else if let stage = QuizView.Stage.allCases.first(where: { arguments.contains("-quiz-\($0.rawValue)") }) {
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


/// The ladder on its own, for the gallery.
///
/// Holds its own throwaway bank so the screen can be photographed without a round being
/// played into a real wallet first.
private struct StagedBoroughs: View {
    @State private var bank: Bank

    init(_ wallet: Wallet) {
        _bank = State(initialValue: .staged(wallet))
    }

    var body: some View {
        BoroughsView(bank: bank)
    }
}

/// Settings on its own, for the gallery, with a throwaway bank behind it — so a
/// photograph of the delete button can never be pointed at real money.
private struct StagedSettings: View {
    @State private var bank: Bank

    init(_ wallet: Wallet) {
        _bank = State(initialValue: .staged(wallet))
    }

    var body: some View {
        SettingsView(bank: bank)
    }
}
