import Foundation
import XCTest
@testable import NeighborhoodQuiz

/// What the game counts, the switch that stops it, and what goes on the wire.
@MainActor
final class AnalyticsTests: XCTestCase {
    private let suite = "AnalyticsTests.\(UUID().uuidString)"
    private var defaults: UserDefaults!

    override func setUpWithError() throws {
        defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
    }

    override func tearDown() {
        defaults.removePersistentDomain(forName: suite)
        defaults = nil
        super.tearDown()
    }

    private func newAnalytics(
        isOn: Bool = true,
        install: String? = "install"
    ) -> (analytics: Analytics, sink: RecordedAnalytics, store: RememberedAnalytics) {
        let sink = RecordedAnalytics()
        let store = RememberedAnalytics(isOn: isOn, install: install)
        return (Analytics(store: store, sink: sink), sink, store)
    }

    // MARK: - The switch

    func testCountingIsOnForAPlayerWhoHasNeverOpenedSettings() {
        XCTAssertTrue(StoredAnalytics(defaults: defaults).loadIsOn())
    }

    func testTurningItOffIsRememberedAcrossTheAppBeingClosed() {
        StoredAnalytics(defaults: defaults).save(isOn: false)

        XCTAssertFalse(StoredAnalytics(defaults: defaults).loadIsOn(), "Off should stay off")
    }

    func testWithTheSwitchOffNothingIsEvenHeld() {
        let (analytics, sink, _) = newAnalytics(isOn: false)

        for _ in 0..<(Analytics.batchSize * 2) {
            analytics.record(.settingsOpened)
        }
        analytics.flush()

        XCTAssertTrue(analytics.pending.isEmpty, "Nothing should be queued while it is off")
        XCTAssertTrue(sink.batches.isEmpty, "Nothing should reach the sink while it is off")
    }

    func testTurningItOffSaysSoOnTheWayOutAndThenGoesQuiet() {
        let (analytics, sink, store) = newAnalytics()
        analytics.record(.settingsOpened)

        analytics.isOn = false

        XCTAssertFalse(store.loadIsOn(), "The switch should be written down at once")
        XCTAssertEqual(
            sink.sent.map(\.name),
            ["Settings.opened", "Settings.analyticsSwitched"],
            "The last batch should go, and say why it is the last"
        )
        XCTAssertEqual(sink.sent.last?.parameters["on"], "false")

        analytics.record(.settingsOpened)
        XCTAssertEqual(sink.batches.count, 1, "Nothing more should go once the gate is shut")
    }

    func testTurningItBackOnIsCounted() {
        let (analytics, sink, _) = newAnalytics(isOn: false)

        analytics.isOn = true
        analytics.flush()

        XCTAssertEqual(sink.sent.map(\.name), ["Settings.analyticsSwitched"])
        XCTAssertEqual(sink.sent.first?.parameters["on"], "true")
    }

    func testSettingTheSwitchToWhatItAlreadySaysCountsNothing() {
        let (analytics, sink, _) = newAnalytics(isOn: true)

        analytics.isOn = true
        analytics.flush()

        XCTAssertTrue(sink.batches.isEmpty)
    }

    // MARK: - Batching

    func testSignalsGatherUntilTheBatchFills() {
        let (analytics, sink, _) = newAnalytics()

        for _ in 0..<(Analytics.batchSize - 1) {
            analytics.record(.settingsOpened)
        }
        XCTAssertTrue(sink.batches.isEmpty, "A part-full batch should still be in hand")

        analytics.record(.settingsOpened)
        XCTAssertEqual(sink.batches.count, 1, "A full batch should go on its own")
        XCTAssertEqual(sink.batches[0].count, Analytics.batchSize)
        XCTAssertTrue(analytics.pending.isEmpty, "A batch that went should not still be held")
    }

    func testFlushingSendsWhateverIsInHand() {
        let (analytics, sink, _) = newAnalytics()
        analytics.record(.settingsOpened)
        analytics.record(.ratingPageOpened)

        analytics.flush()

        XCTAssertEqual(sink.sent.map(\.name), ["Settings.opened", "Rating.pageOpened"])
    }

    func testFlushingAnEmptyHandSendsNothingAtAll() {
        let (analytics, sink, _) = newAnalytics()

        analytics.flush()

        XCTAssertTrue(sink.batches.isEmpty, "An empty batch is not worth a request")
    }

    func testEverySignalInASittingCarriesTheSameIdentity() {
        let (analytics, sink, _) = newAnalytics()

        analytics.record(.settingsOpened)
        analytics.flush()
        analytics.record(.ratingPageOpened)
        analytics.flush()

        XCTAssertEqual(sink.identities.count, 2)
        XCTAssertEqual(sink.identities[0], sink.identities[1])
        XCTAssertFalse(sink.identities[0].session.isEmpty)
    }

    // MARK: - Who it says it is from

    func testTheInstallIsHashedRatherThanSentAsItIsKept() {
        let (analytics, sink, _) = newAnalytics(install: "the-raw-number")
        analytics.record(.settingsOpened)

        analytics.flush()

        let sentAs = sink.identities[0].install
        XCTAssertNotEqual(sentAs, "the-raw-number", "The kept number must not go on the wire")
        XCTAssertEqual(sentAs, Analytics.hashed("the-raw-number"))
        XCTAssertEqual(sentAs.count, 64, "A SHA256 digest, written out")
    }

    func testAPhoneWithNoNumberYetMintsOneAndKeepsIt() {
        let (analytics, sink, store) = newAnalytics(install: nil)

        analytics.record(.settingsOpened)
        analytics.flush()

        let minted = store.loadInstall()
        XCTAssertNotNil(minted, "The number should be written down as it is minted")
        XCTAssertEqual(sink.identities[0].install, Analytics.hashed(minted ?? ""))
    }

    func testTwoInstallsAreTwoDifferentNumbers() {
        let (first, firstSink, _) = newAnalytics(install: nil)
        let (second, secondSink, _) = newAnalytics(install: nil)

        first.record(.settingsOpened)
        first.flush()
        second.record(.settingsOpened)
        second.flush()

        XCTAssertNotEqual(firstSink.identities[0].install, secondSink.identities[0].install)
    }

    func testAPhoneThatHasCountedBeforeIsNotAFirstRun() {
        let (fresh, _, _) = newAnalytics(install: nil)
        let (returning, _, _) = newAnalytics(install: "already-here")

        XCTAssertTrue(fresh.isFirstRun)
        XCTAssertFalse(returning.isFirstRun)
    }

    // MARK: - Deleting everything

    func testDeletingSavedDataMakesTheInstallSomebodyNew() {
        let (analytics, sink, store) = newAnalytics(install: "the-old-number")
        analytics.record(.settingsOpened)
        analytics.flush()
        let before = sink.identities[0].install

        analytics.eraseEverything()
        analytics.record(.settingsOpened)
        analytics.flush()

        XCTAssertNotEqual(store.loadInstall(), "the-old-number", "The old number should be gone")
        XCTAssertNotEqual(sink.identities[1].install, before)
        XCTAssertTrue(analytics.isFirstRun, "A cleared install has not been counted before")
    }

    func testDeletingSavedDataNeverTurnsCountingBackOn() {
        let (analytics, _, store) = newAnalytics(isOn: false)

        analytics.eraseEverything()

        XCTAssertFalse(analytics.isOn, "A player who opted out has not asked to be counted")
        XCTAssertFalse(store.loadIsOn())
    }

    func testDeletingSavedDataDropsAnythingStillInHand() {
        let (analytics, sink, _) = newAnalytics()
        analytics.record(.settingsOpened)

        analytics.eraseEverything()
        analytics.flush()

        XCTAssertTrue(sink.batches.isEmpty, "Held signals belong to a number that no longer exists")
    }

    /// The whole of what the counting writes to the phone: a switch and a number. After a
    /// delete, the number is gone and the switch is not — and the wallet's key is the only
    /// other thing anywhere near them.
    func testTheCountingKeepsTwoThingsAndADeleteLeavesOne() {
        let store = StoredAnalytics(defaults: defaults)
        let analytics = Analytics(store: store, sink: SilentAnalytics())
        analytics.isOn = false
        analytics.isOn = true

        // Only the app's own keys: a suite's dictionary also carries the system's.
        func ours() -> Set<String> {
            Set(defaults.dictionaryRepresentation().keys.filter { $0.hasPrefix("analytics") })
        }
        XCTAssertEqual(ours(), [StoredAnalytics.key, StoredAnalytics.installKey])

        analytics.eraseEverything()

        XCTAssertEqual(ours(), [StoredAnalytics.key], "the switch stays; the number goes")
    }

    // MARK: - What the signals say

    private func place(_ id: Int, in borough: Borough = .manhattan) -> Place {
        Place(borough, id)
    }

    /// A round of three, played three ways: straight away, on the second go, never.
    private func playedRound() -> QuizRound {
        var round = QuizRound(asking: [place(0), place(1), place(2)])
        _ = round.guess(place(0))
        _ = round.guess(place(9))
        _ = round.guess(place(1))
        _ = round.guess(place(7))
        _ = round.guess(place(8))
        _ = round.guess(place(9))
        XCTAssertTrue(round.isFinished)
        return round
    }

    func testAFinishedRoundSaysHowTheScoreWasMade() {
        let signal = AnalyticsSignal.roundFinished(playedRound(), pick: .borough(.brooklyn), rounds: 12)

        XCTAssertEqual(signal.name, "Round.finished")
        XCTAssertEqual(signal.value, 8, "The score is the number worth charting")
        XCTAssertEqual(signal.parameters["where"], "brooklyn")
        XCTAssertEqual(signal.parameters["score"], "8")
        XCTAssertEqual(signal.parameters["perfect"], "15")
        XCTAssertEqual(signal.parameters["firstGo"], "1")
        XCTAssertEqual(signal.parameters["secondGo"], "1")
        XCTAssertEqual(signal.parameters["thirdGo"], "0")
        XCTAssertEqual(signal.parameters["missed"], "1")
        XCTAssertEqual(signal.parameters["rounds"], "12")
    }

    func testARoundAcrossTheCityIsCountedAsAnywhere() {
        XCTAssertEqual(AnalyticsSignal.roundStarted(.anywhere, open: 3).parameters["where"], "anywhere")
        XCTAssertEqual(AnalyticsSignal.roundStarted(.anywhere, open: 3).value, 3)
        XCTAssertEqual(
            AnalyticsSignal.roundStarted(.borough(.statenIsland), open: 5).parameters["where"],
            "statenIsland",
            "The raw name, which is the one that never changes"
        )
    }

    func testARoundLeftPartWaySaysHowFarItGot() {
        var round = QuizRound(asking: [place(0), place(1), place(2)])
        _ = round.guess(place(0))

        let signal = AnalyticsSignal.roundLeft(round, pick: .borough(.manhattan))

        XCTAssertEqual(signal.name, "Round.left")
        XCTAssertEqual(signal.parameters["asked"], "1")
        XCTAssertEqual(signal.parameters["of"], "3")
        XCTAssertEqual(signal.parameters["score"], "5")
        XCTAssertEqual(signal.value, 1)
    }

    func testASettledPlaceSaysWhichGoItTookOrThatNoneDid() {
        let found = AnalyticsSignal.placeSettled(place(0), go: 1, worth: 3)
        XCTAssertEqual(found.name, "Place.settled")
        XCTAssertEqual(found.parameters["go"], "2", "Goes are counted from one on a chart")
        XCTAssertEqual(found.parameters["worth"], "3")
        XCTAssertEqual(found.parameters["borough"], "manhattan")
        XCTAssertEqual(found.parameters["place"], place(0).name)
        XCTAssertEqual(found.value, 3)

        let missed = AnalyticsSignal.placeSettled(place(3, in: .queens), go: nil, worth: 0)
        XCTAssertEqual(missed.parameters["go"], "missed")
        XCTAssertEqual(missed.parameters["borough"], "queens")
        XCTAssertEqual(missed.value, 0)
    }

    func testABoughtBoroughSaysWhichRungAndWhatItCost() {
        let signal = AnalyticsSignal.boroughBought(.bronx, rung: 2, price: 600, rounds: 31)

        XCTAssertEqual(signal.name, "Borough.bought")
        XCTAssertEqual(signal.parameters["borough"], "bronx")
        XCTAssertEqual(signal.parameters["rung"], "2")
        XCTAssertEqual(signal.parameters["price"], "600")
        XCTAssertEqual(signal.parameters["rounds"], "31")
        XCTAssertEqual(signal.value, 600)
    }

    func testAPickSaysWhereItWasMade() {
        let menu = AnalyticsSignal.boroughPicked(.anywhere, from: "menu")
        let ladder = AnalyticsSignal.boroughPicked(.borough(.brooklyn), from: "ladder")

        XCTAssertEqual(menu.name, "Borough.picked")
        XCTAssertEqual(menu.parameters["where"], "anywhere")
        XCTAssertEqual(menu.parameters["from"], "menu")
        XCTAssertEqual(ladder.parameters["where"], "brooklyn")
        XCTAssertEqual(ladder.parameters["from"], "ladder")
    }

    func testNoSignalCarriesAnythingAboutAPerson() {
        let signals: [AnalyticsSignal] = [
            .sessionStarted(isFirstRun: true),
            .roundStarted(.anywhere, open: 2),
            .roundFinished(playedRound(), pick: .borough(.manhattan), rounds: 1),
            .roundLeft(QuizRound(asking: [place(0)]), pick: .anywhere),
            .placeSettled(place(0), go: 0, worth: 5),
            .placeSettled(place(1), go: nil, worth: 0),
            .boroughBought(.queens, rung: 1, price: 200, rounds: 4),
            .boroughPicked(.borough(.queens), from: "menu"),
            .boroughsOpened(from: "summary"),
            .settingsOpened,
            .dataCleared,
            .analyticsSwitched(on: false),
            .ratingAsked(afterRounds: 3),
            .ratingPageOpened
        ]

        for signal in signals {
            XCTAssertFalse(signal.name.isEmpty)
            // Every value is a number, a flag, a borough or a neighbourhood's name — the
            // whole vocabulary. Anything a player typed or a phone knows about its owner
            // would have to be a longer string than any of those, and there is nowhere in
            // the shape of a signal to put one.
            for (key, value) in signal.parameters {
                XCTAssertFalse(key.isEmpty)
                XCTAssertLessThanOrEqual(
                    value.count, 40,
                    "\(signal.name).\(key) is long enough to be hiding something"
                )
            }
        }
    }

    /// The one string a signal carries that is not a number or a word of the app's own
    /// is a neighbourhood's name, and those come from the data. The test above holds
    /// every value under forty characters; this holds every name the data could put
    /// there to the same line, for all five boroughs.
    func testEveryNeighbourhoodNameFitsOnASignal() {
        for borough in Borough.drawn {
            for place in Place.all(in: borough) {
                XCTAssertLessThanOrEqual(place.name.count, 40, "\(borough.name): \(place.name)")
            }
        }
    }

    // MARK: - The wire

    /// Every argument the screenshot workflow launches with. A run that opens on one of
    /// these is the camera, not a player, and counts nothing.
    private let cameraArguments = [
        "-quiz-menu", "-quiz-asking", "-quiz-picked", "-quiz-narrowing",
        "-quiz-filling", "-quiz-missed", "-quiz-over",
        "-map", "-map-zoomed", "-map-neighborhood",
        "-map-brooklyn", "-map-queens", "-map-bronx", "-map-staten-island",
        "-boroughs", "-settings"
    ]

    func testTheCameraIsNotCountedAsAPlayer() {
        for argument in cameraArguments {
            XCTAssertTrue(
                Screen.isPhotographing(["NeighborhoodQuiz", argument]),
                "\(argument) would put a screenshot run on the charts as a player"
            )
            XCTAssertNil(
                TelemetryDeckSink.configured(launch: ["NeighborhoodQuiz", argument]),
                "\(argument) opens straight onto a screen and is nobody"
            )
        }
    }

    /// The other half of the same bargain: every stage the quiz can be staged to has an
    /// argument, and every one of those is a camera.
    func testEveryStageTheCameraCanOpenIsTreatedAsACamera() {
        for stage in QuizView.Stage.allCases {
            XCTAssertTrue(
                Screen.isPhotographing(["NeighborhoodQuiz", "-quiz-\(stage.rawValue)"]),
                "-quiz-\(stage.rawValue) would photograph itself onto the charts"
            )
        }
    }

    func testAPlainLaunchIsAPlayer() {
        XCTAssertFalse(Screen.isPhotographing(["NeighborhoodQuiz"]))
        XCTAssertFalse(
            Screen.isPhotographing(["NeighborhoodQuiz", "-XCTest"]),
            "Only the app's own arguments mean a camera"
        )
    }

    func testABuildWithNoDashboardSendsNowhere() {
        let bundle = Bundle(for: Self.self)

        XCTAssertNil(
            TelemetryDeckSink.configured(bundle: bundle, launch: ["NeighborhoodQuiz"]),
            "No app id in the plist means the game counts nothing"
        )
    }

    func testTheBodyIsOneRowPerSignalWithTheIdentityOnEachOfThem() throws {
        let identity = AnalyticsIdentity(install: "hashed", session: "sitting")
        let data = try XCTUnwrap(
            TelemetryDeckSink.body(
                for: [
                    .ratingAsked(afterRounds: 3),
                    .settingsOpened
                ],
                from: identity,
                appID: "the-app",
                isTestMode: false,
                defaultParameters: ["TelemetryDeck.AppInfo.version": "0.1.0"],
                at: Date(timeIntervalSince1970: 0)
            )
        )
        let rows = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [[String: Any]])

        XCTAssertEqual(rows.count, 2)
        for row in rows {
            XCTAssertEqual(row["appID"] as? String, "the-app")
            XCTAssertEqual(row["clientUser"] as? String, "hashed")
            XCTAssertEqual(row["sessionID"] as? String, "sitting")
            XCTAssertEqual(row["isTestMode"] as? String, "false")
            XCTAssertEqual(row["receivedAt"] as? String, "1970-01-01T00:00:00+0000")
            let payload = try XCTUnwrap(row["payload"] as? [String: String])
            XCTAssertEqual(
                payload["TelemetryDeck.AppInfo.version"], "0.1.0",
                "What build it was travels with every signal"
            )
        }

        XCTAssertEqual(rows[0]["type"] as? String, "Rating.asked")
        XCTAssertEqual(rows[0]["floatValue"] as? Double, 3)
        XCTAssertEqual(rows[1]["type"] as? String, "Settings.opened")
        XCTAssertNil(rows[1]["floatValue"], "A signal about nothing numerical carries no number")
    }

    func testASignalsOwnWordsBeatTheOnesAttachedToEveryBatch() throws {
        let data = try XCTUnwrap(
            TelemetryDeckSink.body(
                for: [AnalyticsSignal("Round.finished", ["where": "brooklyn"])],
                from: AnalyticsIdentity(install: "hashed", session: "sitting"),
                appID: "the-app",
                isTestMode: true,
                defaultParameters: ["where": "should-be-overwritten", "platform": "iOS"],
                at: Date(timeIntervalSince1970: 0)
            )
        )
        let rows = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [[String: Any]])
        let payload = try XCTUnwrap(rows[0]["payload"] as? [String: String])

        XCTAssertEqual(payload["where"], "brooklyn")
        XCTAssertEqual(payload["platform"], "iOS")
        XCTAssertEqual(rows[0]["isTestMode"] as? String, "true")
    }

    func testTheEndpointIsTheOneTheIngestApiListensOn() {
        XCTAssertEqual(TelemetryDeckSink.endpoint.absoluteString, "https://nom.telemetrydeck.com/v2/")
    }

    func testTheStampIsAlwaysUtcHoweverTheMachineIsSet() {
        XCTAssertEqual(
            TelemetryDeckSink.timestamp(Date(timeIntervalSince1970: 1_700_000_000)),
            "2023-11-14T22:13:20+0000"
        )
    }

    func testTheStandardParametersSayWhichBuildAndWhichSystem() {
        let parameters = TelemetryDeckSink.standardParameters(bundle: Bundle(for: Self.self))

        XCTAssertEqual(parameters["TelemetryDeck.Device.platform"], "iOS")
        XCTAssertNotNil(parameters["TelemetryDeck.AppInfo.version"])
        XCTAssertNotNil(parameters["TelemetryDeck.Device.systemVersion"])
    }
}
