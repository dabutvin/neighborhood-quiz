import Foundation

/// What build this is, as the settings screen says it.
///
/// Read from the bundle rather than written down anywhere, so it cannot drift from what
/// was actually shipped: `project.yml` fills both keys from `MARKETING_VERSION` and
/// `CURRENT_PROJECT_VERSION`, and whatever went into the archive is what shows here.
///
/// The build number is worth printing alongside the version. Two TestFlight builds of
/// 0.1.0 are different software, and when somebody says a thing is broken the answer
/// starts with knowing which of them they have.
enum AppVersion {
    /// What is shown when the bundle has nothing to say, which should never happen in a
    /// real build but is not worth crashing over if it does.
    static let unknown = "unknown"

    static var text: String { text(from: Bundle.main.infoDictionary) }

    /// Split out from the bundle so the formatting can be tested. A test bundle's
    /// `Bundle.main` is the test runner, not the app, so asking the real one what
    /// version it is would be asking the wrong question.
    static func text(from info: [String: Any]?) -> String {
        let version = (info?["CFBundleShortVersionString"] as? String)?
            .trimmingCharacters(in: .whitespaces)
        let build = (info?["CFBundleVersion"] as? String)?
            .trimmingCharacters(in: .whitespaces)

        switch (version?.isEmpty == false ? version : nil, build?.isEmpty == false ? build : nil) {
        case let (shown?, built?): return "\(shown) (\(built))"
        case let (shown?, nil): return shown
        default: return unknown
        }
    }
}
