import SwiftUI

@main
struct NeighborhoodQuizApp: App {
    private let launch = ProcessInfo.processInfo.arguments
    private let screen = Screen(arguments: ProcessInfo.processInfo.arguments)

    /// Whether the game has been put down — the cue to send whatever has been counted so
    /// far, since a player who backgrounds the app may never bring it up again.
    @Environment(\.scenePhase) private var scenePhase

    var body: some Scene {
        WindowGroup {
            Group {
                switch screen {
                case .quiz(let stage):
                    QuizView(stage: stage)
                case .map(let borough, let opening, let showing):
                    HomeView(borough: borough, opening: opening, showing: showing)
                case .boroughs(let wallet):
                    StagedBoroughs(wallet)
                case .settings(let wallet):
                    StagedSettings(wallet)
                }
            }
            .onAppear {
                // A camera is not a player. The sink already hands back nothing on a
                // screenshot run; this keeps one from so much as minting an install
                // number into the simulator's defaults.
                guard !Screen.isPhotographing(launch) else { return }
                Analytics.record(.sessionStarted(isFirstRun: Analytics.shared.isFirstRun))
            }
        }
        .onChange(of: scenePhase) { _, phase in
            // Anything counted since the last batch goes the moment the game is put down.
            // A phone in a pocket is where most sittings end, and a batch still in hand
            // when the system reclaims the app is a batch nobody ever sees.
            guard phase != .active else { return }
            Analytics.flush()
        }
    }
}

/// What the app opens on.
///
/// A launch with no arguments — which is every launch a person makes — opens on the
/// game: straight into a round of ten for a wallet that has never earned anything, and
/// on the menu for one that has. Everything else here is for the screenshot runs.
///
/// The `-quiz-*` arguments play a fixed round forward to a particular moment: something
/// picked and waiting on the button, two goes gone, the map half filled in, a place the
/// round gave away, the end of it. They go through `QuizRound.guess` exactly as a
/// player's taps would, so each one is a real state of the game rather than a mock-up of
/// one — which is the only reason a screenshot of it is worth looking at.
///
/// The `-map*` arguments are the map on its own: `-map` whole, `-map-zoomed` in on
/// Midtown, `-map-closest` on Times Square pulled all the way in, `-map-neighborhood` with Greenwich Village picked out — all Manhattan — and
/// then one per other borough, `-map-brooklyn`, `-map-queens`, `-map-bronx` and
/// `-map-staten-island`, each whole and north-up, so a regression that only one file
/// would show has a shot to show it in. `-boroughs` and `-settings` are the two sheets,
/// each over a throwaway wallet.
enum Screen: Equatable {
    case quiz(stage: QuizView.Stage?)
    case map(borough: Borough, opening: MapBoard.Opening, showing: String?)
    case boroughs(Wallet)
    case settings(Wallet)

    /// Whether a launch was the camera's rather than a person's — which is to say,
    /// whether it opened on anything but the plain game. Derived from the same reading of
    /// the arguments that opens the screens, so an argument cannot be added here without
    /// the counting already knowing to ignore it; there is nowhere to say it twice.
    static func isPhotographing(_ arguments: [String]) -> Bool {
        Screen(arguments: arguments) != .quiz(stage: nil)
    }

    init(arguments: [String]) {
        if arguments.contains("-settings") {
            // A wallet with a career behind it, so the row has something to describe
            // rather than offering to delete nothing.
            self = .settings(Wallet(balance: 140, earned: 440, rounds: 11))
        } else if arguments.contains("-boroughs") {
            // Saved up for a first borough and a career behind it: the card that has
            // something to say. With the whole city drawn, what it says is a live
            // Unlock button on every row but Manhattan's — the one state where the
            // ladder can actually be climbed from.
            self = .boroughs(Wallet(balance: 240, earned: 940, rounds: 24))
        } else if let stage = QuizView.Stage.allCases.first(where: { arguments.contains("-quiz-\($0.rawValue)") }) {
            self = .quiz(stage: stage)
        } else if arguments.contains("-map-neighborhood") {
            // Greenwich Village: small enough to fill a phone, known to anybody who has
            // heard of Manhattan, and a tidy shape to show a highlight on.
            self = .map(
                borough: .manhattan,
                opening: .neighborhood("Greenwich Village"),
                showing: "Greenwich Village"
            )
        } else if arguments.contains("-map-zoomed") {
            self = .map(borough: .manhattan, opening: .midtown, showing: nil)
        } else if arguments.contains("-map-closest") {
            self = .map(borough: .manhattan, opening: .closest, showing: nil)
        } else if arguments.contains("-map-brooklyn") {
            // Each of the other four whole, drawn as it sits: one shot per file.
            self = .map(borough: .brooklyn, opening: .island, showing: nil)
        } else if arguments.contains("-map-queens") {
            self = .map(borough: .queens, opening: .island, showing: nil)
        } else if arguments.contains("-map-bronx") {
            self = .map(borough: .bronx, opening: .island, showing: nil)
        } else if arguments.contains("-map-staten-island") {
            self = .map(borough: .statenIsland, opening: .island, showing: nil)
        } else if arguments.contains("-map") {
            self = .map(borough: .manhattan, opening: .island, showing: nil)
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
/// photograph of the delete button can never be pointed at real money — and a throwaway
/// counter, so the photograph of the privacy switch cannot move a real one.
private struct StagedSettings: View {
    @State private var bank: Bank
    @State private var analytics: Analytics

    init(_ wallet: Wallet) {
        _bank = State(initialValue: .staged(wallet))
        _analytics = State(initialValue: .staged())
    }

    var body: some View {
        // A row that does nothing when pressed, which is fine for a photograph of it.
        SettingsView(
            bank: bank,
            analytics: analytics,
            tutorialRecord: TutorialRecord(defaults: nil),
            onHowToPlay: {}
        )
    }
}
