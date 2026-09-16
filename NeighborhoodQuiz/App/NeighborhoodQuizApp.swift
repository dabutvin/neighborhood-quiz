import SwiftUI

@main
struct NeighborhoodQuizApp: App {
    /// CI launches the app with one of the arguments `HomeView.Opening` understands, so
    /// the pull request screenshots can show the map pulled in on Midtown, and a
    /// neighborhood picked out the way a tap picks one out, as well as the whole island.
    /// A launch with no arguments — which is every launch a person makes — opens on the
    /// island with nothing chosen.
    private let opening = HomeView.Opening(arguments: ProcessInfo.processInfo.arguments)

    var body: some Scene {
        WindowGroup {
            HomeView(opening: opening)
        }
    }
}
