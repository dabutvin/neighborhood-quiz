import Foundation

/// The sink that actually puts signals on the wire, addressed to TelemetryDeck.
///
/// A dozen lines of `URLSession` rather than somebody's SDK, because the ingest API is one
/// POST of one JSON array and an SDK to do that would be the only third-party code in the
/// app. Nothing here is on a background queue of its own, nothing retries, nothing is
/// written to disk: a batch is handed to the system's shared session and forgotten about.
/// A quiz is not owed delivery guarantees.
///
/// It is inert until an app id is put in the Info.plist. A build without one — a fork, a
/// checkout, a screenshot run, CI — sends nothing anywhere, and the game plays exactly the
/// same, which is the point of `configured()` handing back nothing rather than a sink that
/// posts into the dark.
struct TelemetryDeckSink: AnalyticsSink {
    /// The ingest endpoint. `v2` with no namespace on the end of it is the plain one, which
    /// is what an app with a single dashboard wants.
    static let endpoint = URL(string: "https://nom.telemetrydeck.com/v2/")!

    /// Where the app id is read from. Set through the `TELEMETRYDECK_APP_ID` build setting
    /// rather than typed into the plist, so a fork builds and runs without one.
    static let appIDKey = "TelemetryDeckAppID"

    let appID: String
    let endpoint: URL
    /// Marks everything as a test signal, so the debugger and the simulator do not show up
    /// beside the people who actually installed the game. TelemetryDeck keeps these on a
    /// screen of their own.
    let isTestMode: Bool
    /// What travels with every signal: which build, which iOS, which language. Attached
    /// under TelemetryDeck's own names so its built-in breakdowns find them, and worked out
    /// once at launch rather than on every batch.
    let defaultParameters: [String: String]

    /// The sink for this build, or nothing at all when there is no app id to send to — or
    /// when the app was opened by the camera rather than by a player. The screenshot runs
    /// launch straight onto a screen with one of the app's own arguments; counting those
    /// would put a fortnight of CI on the charts as somebody who knows exactly where SoHo
    /// is, ten times a day.
    @MainActor
    static func configured(
        bundle: Bundle = .main,
        launch: [String] = ProcessInfo.processInfo.arguments
    ) -> TelemetryDeckSink? {
        guard !Screen.isPhotographing(launch) else { return nil }
        let appID = (bundle.object(forInfoDictionaryKey: appIDKey) as? String ?? "")
            .trimmingCharacters(in: .whitespaces)
        guard !appID.isEmpty else { return nil }
        return TelemetryDeckSink(appID: appID, defaultParameters: standardParameters(bundle: bundle))
    }

    init(
        appID: String,
        endpoint: URL = TelemetryDeckSink.endpoint,
        isTestMode: Bool = TelemetryDeckSink.isBuiltForTesting,
        defaultParameters: [String: String] = [:]
    ) {
        self.appID = appID
        self.endpoint = endpoint
        self.isTestMode = isTestMode
        self.defaultParameters = defaultParameters
    }

    /// True for anything that is not a real copy on a real phone: the debugger, the
    /// simulator, a test run.
    static var isBuiltForTesting: Bool {
        #if DEBUG
        return true
        #elseif targetEnvironment(simulator)
        return true
        #else
        return false
        #endif
    }

    /// The OS version is read off `ProcessInfo` rather than `UIDevice` so that nothing in
    /// this layer has to import UIKit.
    static func standardParameters(bundle: Bundle = .main) -> [String: String] {
        let info = bundle.infoDictionary
        let version = info?["CFBundleShortVersionString"] as? String ?? "0"
        let build = info?["CFBundleVersion"] as? String ?? "0"
        let system = ProcessInfo.processInfo.operatingSystemVersion
        return [
            "TelemetryDeck.AppInfo.version": version,
            "TelemetryDeck.AppInfo.buildNumber": build,
            "TelemetryDeck.AppInfo.versionAndBuildNumber": "\(version) (build \(build))",
            "TelemetryDeck.Device.platform": "iOS",
            "TelemetryDeck.Device.systemMajorVersion": "\(system.majorVersion)",
            "TelemetryDeck.Device.systemVersion":
                "\(system.majorVersion).\(system.minorVersion).\(system.patchVersion)",
            "TelemetryDeck.RunContext.locale": Locale.current.identifier
        ]
    }

    func send(_ signals: [AnalyticsSignal], from identity: AnalyticsIdentity) {
        guard let body = Self.body(
            for: signals,
            from: identity,
            appID: appID,
            isTestMode: isTestMode,
            defaultParameters: defaultParameters,
            at: Date()
        ) else { return }

        var request = URLRequest(url: endpoint)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = body
        // Ten seconds, and no second go. A batch that cannot get out on a train is a batch
        // the game is better off dropping than holding on to.
        request.timeoutInterval = 10

        Task.detached(priority: .background) {
            _ = try? await URLSession.shared.data(for: request)
        }
    }

    /// The JSON array the ingest API wants: one object per signal, each carrying the whole
    /// identity rather than the batch carrying it once. That is the API's shape, not a
    /// choice — and it is why the identity is two random numbers and nothing more.
    ///
    /// Held apart from `send` so the tests can read what would go on the wire without
    /// anything having to leave the machine.
    static func body(
        for signals: [AnalyticsSignal],
        from identity: AnalyticsIdentity,
        appID: String,
        isTestMode: Bool,
        defaultParameters: [String: String] = [:],
        at now: Date
    ) -> Data? {
        let stamp = timestamp(now)
        let rows: [[String: Any]] = signals.map { signal in
            var row: [String: Any] = [
                "receivedAt": stamp,
                "appID": appID,
                "clientUser": identity.install,
                "sessionID": identity.session,
                "type": signal.name,
                "payload": defaultParameters.merging(signal.parameters) { _, mine in mine },
                "isTestMode": String(isTestMode)
            ]
            if let value = signal.value {
                row["floatValue"] = value
            }
            return row
        }
        return try? JSONSerialization.data(withJSONObject: rows)
    }

    /// The ingest API's date format, to the second, always in UTC.
    static func timestamp(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd'T'HH:mm:ssZ"
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(secondsFromGMT: 0)
        return formatter.string(from: date)
    }
}
