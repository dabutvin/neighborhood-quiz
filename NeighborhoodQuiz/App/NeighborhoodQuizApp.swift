import SwiftUI

@main
struct NeighborhoodQuizApp: App {
    /// CI launches the app with one of the arguments `HomeView.Opening` understands, so
    /// the pull request screenshots can show the map pulled in on Midtown as well as the
    /// whole island. A launch with no arguments — which is every launch a person makes —
    /// opens on the island.
    private let opening = HomeView.Opening(arguments: ProcessInfo.processInfo.arguments)

    var body: some Scene {
        WindowGroup {
            HomeView(opening: opening)
        }
    }
}
