import StoreKit
import SwiftUI

/// The game. A name at the top, the map below it, and three goes to put your finger on
/// the right place.
///
/// Nothing on the map says where anything is — the borders are drawn but no neighborhood
/// is named until the round has done with it — so the only way through is to know, or to
/// work it out from the streets, which is the same thing a block later.
struct QuizView: View {
    /// A state the screenshot runs need to see: a round played forward to a particular
    /// moment so the gallery shows the same thing every time.
    ///
    /// Only reachable by launch argument. A person playing gets `nil` and a round of
    /// ten drawn at random.
    enum Stage: String, CaseIterable {
        /// The menu a returning player opens on, with a wallet part-way to a first
        /// borough.
        case menu
        /// A fresh question, nothing picked.
        case asking
        /// Somewhere picked, waiting on the button.
        case picked
        /// Two goes gone, two places crossed off, one go left.
        case narrowing
        /// Several found, the map filling in.
        case filling
        /// Three goes were not enough, and the round is showing where it was.
        case missed
        /// The end of it.
        case over
    }

    /// The places the gallery is played through, chosen to be recognisable rather than
    /// representative. A staged round always asks these, in this order. They are
    /// Manhattan's, which is why a staged run is pinned to Manhattan below.
    static let showcase = [
        "Greenwich Village", "SoHo", "Harlem", "Tribeca", "Chelsea",
        "Upper East Side", "East Village", "Times Square", "Chinatown", "Inwood",
    ]

    /// What the gallery's wallet holds before the staged round is paid for: part-way to
    /// a first borough, with a career behind it, so the rows have something to say.
    static let stagedWallet = Wallet(balance: 140, earned: 440, rounds: 11)

    var stage: Stage?

    @Environment(\.colorScheme) private var colorScheme
    /// Apple's rating sheet. Asking is all this can do; whether it appears is Apple's.
    @Environment(\.requestReview) private var requestReview

    /// The money. A staged run gets one that remembers nothing, so the gallery shows the
    /// same numbers every time and a photograph of the game can never spend, add to or
    /// inherit what a real player has earned.
    @State private var bank: Bank
    /// The two screens that come up over the game. One piece of state rather than a
    /// flag each: stacking two `.sheet` modifiers on the same view is a long-standing
    /// way to have one of them quietly never appear.
    enum Overlay: String, Identifiable {
        case boroughs
        case settings
        var id: String { rawValue }
    }

    @State private var overlay: Overlay?

    init(stage: Stage? = nil) {
        self.stage = stage
        _bank = State(initialValue: stage == nil ? Bank() : Bank.staged(QuizView.stagedWallet))
    }

    @State private var round: QuizRound?
    /// The place the round has just settled, held on the map with its name on for a
    /// moment before the next question. Also what stops a fast thumb from answering the
    /// next question before it has read it.
    @State private var showing: Shown?
    /// Picked out and waiting on the button. A tap on the map chooses; it is answering
    /// with it that spends a go, so a thumb landing somewhere careless is free to be
    /// taken back.
    @State private var candidate: Place?
    /// Bumped at the start of a round to send the map back to the whole borough. Not
    /// between questions: where you have got the map to is yours, and pulling it back
    /// out every time was undoing the player's own work.
    @State private var opening = 0
    /// Whether the map has been ready once this launch. The first time is the only
    /// time a round starts itself; a rotation builds the map again and must not.
    @State private var hasLaunched = false

    /// How a question ended, while it is still on screen.
    enum Shown: Equatable {
        case found(Place, worth: Int)
        case missed(Place)

        var place: Place {
            switch self {
            case .found(let place, _), .missed(let place): return place
            }
        }

        var isMiss: Bool {
            if case .missed = self { return true }
            return false
        }
    }

    private var palette: MapPalette { .of(colorScheme) }

    /// Where the map opens, and goes back to between rounds.
    ///
    /// The wallet's borough, checked against what it can actually play — see
    /// `Wallet.current` — and for the anywhere mode simply the borough the player was
    /// last in, since a menu has to be over some map or other. A staged run is pinned to
    /// Manhattan whatever its wallet says: the showcase names are Manhattan's, and a
    /// gallery shot of Brooklyn with "Find SoHo" over it would be a photograph of a
    /// bug. The staged wallet owns nothing anyway, so the pills that could move it never
    /// appear; this is the belt to that pair of braces.
    private var home: Borough {
        guard stage == nil else { return .manhattan }
        switch bank.wallet.pick {
        case .borough(let borough): return borough
        case .anywhere: return bank.wallet.current
        }
    }

    /// The borough on the map right now.
    ///
    /// Derived rather than chosen, because in the anywhere mode the map follows the
    /// question: whatever is being shown, then whatever is being asked, then — once the
    /// round is over and the summary is up — wherever the last question was, so the map
    /// under the card is the one the round ended on. With no round at all, home.
    private var shownBorough: Borough {
        if let showing { return showing.place.borough }
        if let round {
            if let current = round.current { return current.borough }
            if let last = round.questions.last { return last.borough }
        }
        return home
    }

    /// Whether the round runs over every borough rather than one.
    private var anywhere: Bool { bank.wallet.pick == .anywhere }

    var body: some View {
        ZStack {
            palette.water.ignoresSafeArea()

            // Stacked rather than layered, so the map is drawn into what is left over
            // after the question has had its share. Over the top, the card hid the
            // northern end of the island — which was fine until the question was Inwood
            // and the answer was underneath it.
            VStack(spacing: 0) {
                if let round, !round.isFinished || showing != nil {
                    prompt(for: round)
                }

                ZStack {
                    MapBoard(
                        palette: palette,
                        borough: shownBorough,
                        selected: id(of: showing?.place),
                        ruledOut: ids(of: round?.ruledOut ?? []),
                        settled: ids(of: round?.found ?? []),
                        givenAway: ids(of: round?.missed ?? []),
                        candidate: id(of: candidate),
                        resetToken: opening,
                        onTap: pick,
                        onReady: { _ in start() }
                    )
                    PaperTexture(palette: palette)

                    if let round, !round.isFinished {
                        quitButton
                    }
                }
            }

            if round == nil {
                menu
            } else if let round, round.isFinished, showing == nil {
                summary(of: round)
            } else if candidate != nil, showing == nil {
                answerButton
            }
        }
        .background(palette.water)
        .sheet(item: $overlay) { which in
            switch which {
            case .boroughs: BoroughsView(bank: bank) { overlay = nil }
            case .settings: SettingsView(bank: bank) { overlay = nil }
            }
        }
        // Changing what the next round is about is only offered from the menu and from
        // the ladder, and the ladder can be opened over the end of a round. A finished
        // round has been paid and its summary is all that is left of it — but it was
        // the old pick's round, and the player has just asked for something else. So
        // the summary goes, and the player lands on the menu of what they asked for.
        //
        // The *borough* on the map is not what this watches, and must not be: in the
        // anywhere mode it changes mid-round on purpose, every time the question moves
        // from one borough to the other.
        .onChange(of: bank.wallet.pick) { _, _ in
            if round != nil { leave() }
        }
        // Holding the settled place on screen, then moving along. `task(id:)` rather
        // than a Task started by hand: it is cancelled for us if the view goes away or
        // if `showing` changes underneath it, which is the whole of what could go wrong.
        .task(id: showing) {
            // A staged screen is a photograph and must not move while it is being taken.
            guard showing != nil, stage == nil else { return }
            // Longer for a miss: being told where it was is something to read, not just
            // something to confirm.
            try? await Task.sleep(for: showing?.isMiss == true ? .seconds(2) : .seconds(1.2))
            guard !Task.isCancelled else { return }
            withAnimation(.easeInOut(duration: 0.3)) { showing = nil }
        }
    }

    // MARK: - What the map is handed

    /// The places on the borough being shown, by the id the map draws them under.
    ///
    /// A round's lists are places from all over the city and the map draws one borough
    /// at a time, so it is handed the ids on that borough and none of the others — an
    /// id from Brooklyn's list is some other neighbourhood on Manhattan's, and would be
    /// washed in terracotta for no reason anybody could see.
    private func ids(of places: some Collection<Place>) -> Set<Int> {
        Set(places.filter { $0.borough == shownBorough }.map(\.id))
    }

    /// One place's id, if it is on the borough being shown.
    private func id(of place: Place?) -> Int? {
        guard let place, place.borough == shownBorough else { return nil }
        return place.id
    }

    // MARK: - The question

    private func prompt(for round: QuizRound) -> some View {
        let lead: String
        let name: String
        let ink: Color
        let said = whereItIs(round)

        switch showing {
        case .found(let place, _):
            lead = "FOUND"
            name = place.name
            ink = palette.highlightInk
        case .missed(let place):
            lead = "IT WAS"
            name = place.name
            ink = palette.ruledOutInk
        case nil:
            // In the anywhere mode the map hops between boroughs and a name on its own
            // does not say which one you are looking at, so the card does.
            lead = said.map { "FIND · \($0.uppercased())" } ?? "FIND"
            name = round.current?.name ?? ""
            ink = palette.ink
        }

        return VStack(spacing: 3) {
            HStack {
                Text(lead)
                    .font(.system(size: 10, weight: .semibold))
                    .kerning(2.2)
                Spacer()
                Text(standing(of: round))
                    .font(.system(size: 10, weight: .semibold))
                    .kerning(1.2)
                    .monospacedDigit()
            }
            .foregroundStyle(palette.inkSoft)

            HStack(alignment: .firstTextBaseline, spacing: 10) {
                Text(name)
                    .font(MapFont.chrome(size: 30))
                    .foregroundStyle(ink)
                    .minimumScaleFactor(0.6)
                    .lineLimit(1)
                Spacer(minLength: 0)
                verdict(for: round)
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .background(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(palette.land.opacity(0.95))
                .overlay(
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .strokeBorder(palette.inkSoft.opacity(0.6), lineWidth: 1.4)
                )
        )
        .padding(.horizontal, 12)
        .padding(.top, 4)
        .padding(.bottom, 6)
        .allowsHitTesting(false)
        .accessibilityElement(children: .combine)
        .accessibilityLabel(spoken(name: name, in: said, round: round))
    }

    /// Which borough the question is on, when that is worth saying — which is only in
    /// the anywhere mode. A round of one borough has its name on the menu already, and
    /// repeating it over ten questions would be noise.
    private func whereItIs(_ round: QuizRound) -> String? {
        anywhere ? round.current?.borough.name : nil
    }

    /// What the goes look like: three tally strokes that fade as they are spent, and in
    /// their place, once a question has ended, what it was worth.
    ///
    /// Tally marks rather than dots. Three little circles in a row are, on a phone, a
    /// "more" button, and a player who taps the question card expecting a menu has been
    /// told the wrong thing by the drawing. Strokes read as goes — a count kept by hand
    /// — and they suit a map drawn by one. A spent stroke goes faint rather than going
    /// altogether, so the count of three is still there to be read against.
    @ViewBuilder
    private func verdict(for round: QuizRound) -> some View {
        switch showing {
        case .found(_, let worth):
            Text("+" + Money.text(worth))
                .font(MapFont.chrome(size: 22))
                .foregroundStyle(palette.highlightInk)
        case .missed:
            Text(Money.text(0))
                .font(MapFont.chrome(size: 22))
                .foregroundStyle(palette.ruledOutInk)
        case nil:
            HStack(spacing: 5) {
                ForEach(0..<QuizRound.tries, id: \.self) { index in
                    Capsule()
                        .fill(index < round.triesLeft ? palette.ink : palette.inkSoft.opacity(0.35))
                        .frame(width: 2.5, height: 13)
                        // Each leans a little differently, as strokes made by hand do.
                        .rotationEffect(.degrees([8.0, 6, 9][index % 3]))
                }
            }
        }
    }

    /// How far through, and what it is worth so far. The score only appears once there
    /// is one, so a round opens without a nought staring at you.
    private func standing(of round: QuizRound) -> String {
        let progress = "\(asked(of: round)) of \(round.questions.count)"
        guard round.score > 0 else { return progress }
        return "\(progress)   \(Money.text(round.score))"
    }

    /// Which question the card is talking about.
    ///
    /// Not simply where the round has got to. A question that ends moves the round on
    /// straight away, but its answer stays on screen for a moment afterwards — and while
    /// "IT WAS Harlem" is being read, saying "4 of 10" over the top of it is counting
    /// the question nobody has been asked yet.
    private func asked(of round: QuizRound) -> Int {
        showing == nil
            ? min(round.index + 1, round.questions.count)
            : max(round.index, 1)
    }

    private func spoken(name: String, in borough: String?, round: QuizRound) -> String {
        switch showing {
        case .found(_, let worth): return "Found \(name), worth \(Money.text(worth))."
        case .missed: return "Out of goes. It was \(name)."
        case nil:
            let there = borough.map { " in \($0)" } ?? ""
            return "Find \(name)\(there). "
                + "Question \(asked(of: round)) of \(round.questions.count), "
                + "\(round.triesLeft) \(round.triesLeft == 1 ? "go" : "goes") left."
        }
    }

    /// The only way to answer. It appears when something is picked and goes when it is
    /// answered with, so there is never a button on screen with nothing behind it — and
    /// it says "Answer" rather than the name of the place, because the name is the
    /// question.
    private var answerButton: some View {
        Button(action: answer) {
            Text("Answer")
                .font(MapFont.chrome(size: 22))
                .foregroundStyle(palette.labelHalo)
                .padding(.horizontal, 34)
                .padding(.vertical, 12)
                .background(
                    Capsule()
                        .fill(palette.ink)
                        .overlay(Capsule().strokeBorder(palette.labelHalo.opacity(0.5), lineWidth: 1.5))
                        .shadow(color: .black.opacity(0.18), radius: 6, y: 2)
                )
        }
        .buttonStyle(.plain)
        .padding(.bottom, 22)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottom)
        .transition(.opacity.combined(with: .move(edge: .bottom)))
        .accessibilityLabel("Answer with the neighborhood you have picked")
    }

    // MARK: - The end of it

    private func summary(of round: QuizRound) -> some View {
        VStack(spacing: 14) {
            Text("Round over")
                .font(MapFont.chrome(size: 30))
                .foregroundStyle(palette.ink)

            VStack(spacing: 2) {
                Text(Money.text(round.score))
                    .font(MapFont.chrome(size: 56))
                    .foregroundStyle(palette.highlightInk)
                Text(round.score == round.perfectScore
                     ? "out of \(Money.text(round.perfectScore)) — a perfect round"
                     : "out of \(Money.text(round.perfectScore))")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(palette.inkSoft)
            }

            breakdown(of: round)

            takings

            VStack(spacing: 10) {
                HStack(spacing: 10) {
                    pill("Play again", action: startRound)
                    share(round)
                }
                HStack(spacing: 10) {
                    pill("Boroughs") { overlay = .boroughs }
                    pill("Menu", action: leave)
                }
            }
        }
        .padding(.horizontal, 30)
        .padding(.vertical, 28)
        .background(card)
        .padding(28)
    }

    /// The score, handed to whatever the phone can send it with. Dressed as a pill so
    /// it sits beside "Play again" as one of the things you can do next rather than as
    /// a system button that wandered onto the card.
    private func share(_ round: QuizRound) -> some View {
        let line = AppStore.shareText(score: round.score, of: round.perfectScore, borough: playedWhere)
        return ShareLink(item: line) {
            pillLabel("Share")
        }
        .buttonStyle(.plain)
    }

    /// Where the round was, for the line that gets shared: the borough's name, or
    /// "across the city" for a round that ran over all of them.
    private var playedWhere: String {
        switch bank.wallet.pick {
        case .borough(let borough): return borough.name
        case .anywhere: return "across the city"
        }
    }

    /// The paper a card is on. The menu and the end of a round are the same kind of
    /// moment — the map behind, the money on it, one thing to press — so they wear the
    /// same thing.
    private var card: some View {
        RoundedRectangle(cornerRadius: 20, style: .continuous)
            .fill(palette.land.opacity(0.97))
            .overlay(
                RoundedRectangle(cornerRadius: 20, style: .continuous)
                    .strokeBorder(palette.inkSoft, lineWidth: 2)
            )
    }

    // MARK: - The menu

    /// Where a returning player opens, and where quitting a round puts you back.
    private var menu: some View {
        VStack(spacing: 16) {
            VStack(spacing: 8) {
                // The full name, which wraps after the colon on a phone. Two lines of
                // hand lettering read as a title; one line squeezed to fit reads as a
                // label that ran out of room.
                Text(AppStore.name)
                    .font(MapFont.chrome(size: 26))
                    .foregroundStyle(palette.ink)
                    .multilineTextAlignment(.center)
                    .lineLimit(2)
                    .minimumScaleFactor(0.8)
                whereabouts
            }

            VStack(spacing: 1) {
                Text(Money.text(bank.wallet.balance))
                    .font(MapFont.chrome(size: 46))
                    .foregroundStyle(palette.highlightInk)
                    .monospacedDigit()
                Text("TO SPEND")
                    .font(.system(size: 9, weight: .semibold))
                    .kerning(1.3)
                    .foregroundStyle(palette.inkSoft)
            }

            savingBar

            VStack(spacing: 10) {
                pill("Start", action: startRound)
                HStack(spacing: 10) {
                    pill("Boroughs") { overlay = .boroughs }
                    pill("Settings") { overlay = .settings }
                }
            }
            .padding(.top, 2)

            Text(career)
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(palette.inkSoft.opacity(0.9))
                .monospacedDigit()
        }
        .padding(.horizontal, 34)
        .padding(.vertical, 28)
        .background(card)
        .padding(28)
    }

    /// What the next round will be about.
    ///
    /// One quiet line while there is only Manhattan to play — a choice of one is not a
    /// choice, and a single pill would look like a button that does nothing. Once a
    /// second borough is open it becomes a row of pills, one per borough in the order
    /// they were bought and then "Anywhere", which draws the ten from all of them; the
    /// one being played is filled in. Only on the menu: mid-round the map is the
    /// round's, and a staged run never sees the row because its wallet owns nothing.
    @ViewBuilder
    private var whereabouts: some View {
        let wallet = bank.wallet

        if wallet.playable.count > 1 {
            HStack(spacing: 8) {
                ForEach(wallet.playable) { borough in
                    choice(borough.name, chosen: wallet.pick == .borough(borough)) {
                        bank.play(borough)
                    }
                }
                choice("Anywhere", chosen: wallet.pick == .anywhere) {
                    bank.playAnywhere()
                }
            }
        } else {
            Text(home.name.uppercased())
                .font(.system(size: 9, weight: .semibold))
                .kerning(1.3)
                .foregroundStyle(palette.inkSoft)
        }
    }

    /// One thing on the row. The one being played is ink with the paper showing through
    /// the name, the way the answer button is; the others are outlined like every other
    /// pill, and pressing one makes it the pick.
    private func choice(_ title: String, chosen: Bool, action: @escaping () -> Void) -> some View {
        Button {
            // Pressing the one you are on is not a change, and should not write anything.
            guard !chosen else { return }
            action()
        } label: {
            Text(title)
                .font(MapFont.chrome(size: 15))
                .foregroundStyle(chosen ? palette.labelHalo : palette.ink)
                .padding(.horizontal, 12)
                .padding(.vertical, 5)
                .background(
                    Capsule()
                        .fill(chosen ? palette.ink : palette.land)
                        .overlay(Capsule().strokeBorder(chosen ? palette.ink : palette.inkSoft, lineWidth: 1.5))
                )
        }
        .buttonStyle(.plain)
        .accessibilityLabel(chosen ? "Playing \(title)" : "Play \(title)")
    }

    /// What the wallet has to say about itself when there is no round to talk about.
    private var career: String {
        let wallet = bank.wallet
        guard wallet.rounds > 0 else { return "no rounds played yet" }
        let rounds = wallet.rounds == 1 ? "1 round" : "\(wallet.rounds) rounds"
        return "\(rounds) · \(Money.text(wallet.earned)) earned in all"
    }

    /// Leaving a round part-way.
    ///
    /// In the same hand as the zoom buttons and tucked into the opposite corner, so it
    /// reads as part of the map's furniture rather than as part of the question.
    private var quitButton: some View {
        Button(action: leave) {
            Text("\u{00D7}")
                .font(MapFont.chrome(size: 22))
                .foregroundStyle(palette.ink)
                .frame(width: 40, height: 40)
                .background(
                    Circle()
                        .fill(palette.land.opacity(0.92))
                        .overlay(Circle().strokeBorder(palette.inkSoft, lineWidth: 1.8))
                )
        }
        .buttonStyle(.plain)
        .padding(.leading, 14)
        .padding(.top, 12)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .accessibilityLabel("Leave this round")
    }

    /// What the round did to the wallet.
    ///
    /// The money has already moved by the time this is on screen — it was paid the
    /// moment the last question was answered — so this is not a receipt to approve, it
    /// is the bar going up, which is the whole reason to play another one.
    @ViewBuilder
    private var takings: some View {
        let wallet = bank.wallet

        VStack(spacing: 7) {
            Rectangle()
                .fill(palette.inkSoft.opacity(0.28))
                .frame(height: 1)
                .padding(.bottom, 1)

            HStack(spacing: 8) {
                Text("WALLET")
                    .font(.system(size: 9, weight: .semibold))
                    .kerning(1.4)
                    .foregroundStyle(palette.inkSoft)
                Spacer(minLength: 8)
                Text(Money.text(wallet.balance))
                    .font(MapFont.chrome(size: 24))
                    .foregroundStyle(palette.ink)
                    .monospacedDigit()
            }

            savingBar
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel(
            "Wallet, \(Money.text(wallet.balance))."
                + (wallet.nextPrice == nil ? "" : " \(savedLine)")
        )
    }

    /// How far along to the next borough, and what it costs. On the menu and again at
    /// the end of a round, which are the two moments anybody looks at it. Nothing at
    /// all once the whole city is bought: a full bar with nothing left to fill it for
    /// would be a bar for its own sake.
    @ViewBuilder
    private var savingBar: some View {
        let wallet = bank.wallet

        if let price = wallet.nextPrice {
            VStack(spacing: 7) {
                GeometryReader { geometry in
                    ZStack(alignment: .leading) {
                        Capsule()
                            .fill(palette.inkSoft.opacity(0.22))
                        Capsule()
                            .fill(palette.highlight)
                            .frame(width: max(geometry.size.width * wallet.progress,
                                              wallet.progress > 0 ? 6 : 0))
                    }
                }
                .frame(height: 8)

                Text(savedLine)
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(wallet.balance >= price ? palette.highlightInk : palette.inkSoft)
            }
        }
    }

    /// The one line under the bar. Three things it can say, and the third is the honest
    /// one: the money is there and no map is. With the whole city drawn nobody sits
    /// there today, but it is kept for the next map that is not drawn yet, whichever
    /// that turns out to be. No borough is named, because the price is not any
    /// borough's — it is the next rung, and which borough goes on it is picked on the
    /// Boroughs screen, not here.
    private var savedLine: String {
        let wallet = bank.wallet
        guard let price = wallet.nextPrice else { return "" }
        guard wallet.balance >= price else { return "Next borough at \(Money.text(price))" }
        return Borough.buyable.contains(where: { wallet.canBuy($0) })
            ? "\(Money.text(price)) saved — pick a borough"
            : "\(Money.text(price)) saved — the next maps are still being drawn"
    }

    private func pill(_ title: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            pillLabel(title)
        }
        .buttonStyle(.plain)
    }

    /// The pill itself, apart from the button, so the share link can wear one too.
    private func pillLabel(_ title: String) -> some View {
        Text(title)
            .font(MapFont.chrome(size: 20))
            .foregroundStyle(palette.ink)
            .padding(.horizontal, 20)
            .padding(.vertical, 10)
            .background(
                Capsule()
                    .fill(palette.land)
                    .overlay(Capsule().strokeBorder(palette.inkSoft, lineWidth: 1.8))
            )
    }

    /// Where the score came from, a line per go.
    ///
    /// Every question asked is on exactly one of these lines, so the counts add up to
    /// ten and the points add up to the number above them — which is the whole point of
    /// showing it: a score with no working is a number somebody has to take on trust.
    ///
    /// A go nobody managed is still listed, greyed rather than left out. "Never found:
    /// none" is worth reading, and a list whose rows come and go depending on how the
    /// round went is a list you have to re-read every time.
    private func breakdown(of round: QuizRound) -> some View {
        VStack(spacing: 5) {
            ForEach(0..<QuizRound.tries, id: \.self) { go in
                tally(
                    QuizRound.goName(go),
                    count: round.foundOn[go],
                    points: round.foundOn[go] * QuizRound.points[min(go, QuizRound.points.count - 1)],
                    ink: palette.highlightInk.opacity(1 - Double(go) * 0.2)
                )
            }
            tally(
                "Never found",
                count: round.missed.count,
                points: 0,
                ink: palette.ruledOutInk
            )
        }
        .padding(.top, 2)
    }

    private func tally(_ label: String, count: Int, points: Int, ink: Color) -> some View {
        let spent = count > 0
        return HStack(spacing: 10) {
            Text(label)
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(spent ? palette.ink : palette.inkSoft.opacity(0.55))
            Spacer(minLength: 14)
            Text("\(count)")
                .font(MapFont.chrome(size: 20))
                .foregroundStyle(spent ? ink : palette.inkSoft.opacity(0.45))
                .monospacedDigit()
                .frame(minWidth: 16, alignment: .trailing)
            Text(points > 0 ? Money.text(points) : "—")
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(palette.inkSoft.opacity(spent ? 0.9 : 0.45))
                .monospacedDigit()
                .frame(minWidth: 42, alignment: .trailing)
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel(
            "\(label): \(count) \(count == 1 ? "place" : "places")"
                + (points > 0 ? ", \(Money.text(points))" : "")
        )
    }

    // MARK: - Playing

    /// The map is ready — the first time, and again whenever a borough is drawn that
    /// was not before. Nothing is taken from the drawing any more: a round's places
    /// come from the data, and their names with them. What matters here is the moment.
    ///
    /// On the first one, a fresh wallet goes straight into a round. A new player has
    /// nothing to read on the menu — no money, no ladder worth looking at — and the map
    /// with a question over it is the whole pitch, so that is what they get. A returning
    /// player has a balance and a ladder to look at, and opens on the menu as before.
    /// The gallery's `-quiz-menu` run has money, so its shot is unchanged.
    private func start() {
        guard round == nil else { return }

        if let stage {
            // Nothing is a round until Start is pressed, and the gallery's shot of the
            // menu is a shot of exactly that.
            guard stage != .menu else { return }
            var staged = QuizRound(asking: QuizView.showcase.compactMap(QuizView.place(named:)))
            play(&staged, to: stage)
            // A staged round that reached the end is paid like any other, so the wallet
            // on the card agrees with the breakdown above it. The bank is a throwaway,
            // so this goes nowhere near a real player's money.
            if staged.isFinished { bank.earn(staged.score) }
            round = staged
            return
        }

        guard !hasLaunched else { return }
        hasLaunched = true
        if bank.wallet.isEmpty { startRound() }
    }

    /// A tap on the map. It picks a place out and costs nothing — a go is only spent
    /// when you answer with it.
    ///
    /// Water, the parks, and anywhere the round has already settled all put the pick
    /// down again. There is nothing to be gained by choosing a place that is done with,
    /// and leaving it selectable would only invite somebody to answer with it and wonder
    /// why nothing happened.
    private func pick(_ id: Int?) {
        guard showing == nil, let round, !round.isFinished else { return }

        // The map reports an id on the borough it is drawing; the round wants to know
        // which borough that was.
        let place = id.map { Place(shownBorough, $0) }
        guard let place, !round.ruledOut.contains(place),
              !round.found.contains(place), !round.missed.contains(place)
        else {
            withAnimation(.easeOut(duration: 0.15)) { candidate = nil }
            return
        }
        withAnimation(.easeOut(duration: 0.15)) {
            candidate = (place == candidate) ? nil : place
        }
    }

    /// Answering with what is picked. This is the only thing that spends a go.
    private func answer() {
        guard showing == nil, let picked = candidate,
              var playing = round, !playing.isFinished
        else { return }

        // Unwrapped and put back rather than mutated through the optional, so that what
        // the round did and what the screen does next are two plain steps.
        let worth = QuizRound.points[min(playing.triesUsed, QuizRound.points.count - 1)]
        let outcome = playing.guess(picked)

        // What the card will say about the question that just ended, decided before any
        // of it reaches the screen.
        let settled: Shown?
        switch outcome {
        case .right: settled = .found(picked, worth: worth)
        case .missed: settled = playing.missed.last.map(Shown.missed)
        case .wrong, .ignored: settled = nil
        }

        // Paid here rather than where the summary is drawn. This runs once, when the
        // last question is answered; a view body runs whenever SwiftUI feels like it,
        // and paying from one would pay again on every redraw.
        if playing.isFinished {
            bank.earn(playing.score)
            askForARating()
        }

        // One change, not three.
        //
        // `guess` has already moved the round on to the next question, and `showing` is
        // what holds the last one on screen while its answer is read. Set apart, there
        // is a frame in between where the round has moved and nothing is explaining why,
        // and the screen drew it: mid-round the card read out the *next* place before
        // you had been told you found the last one, and on the tenth answer the card
        // went altogether and the end-of-round summary flashed up underneath it.
        //
        // Both were the same frame. Neither can happen while these land together.
        withAnimation(.easeOut(duration: 0.2)) {
            round = playing
            candidate = nil
            showing = settled
        }
    }

    /// Whether to ask for a rating, and when.
    ///
    /// After the third round and after the tenth: the third is the first moment
    /// somebody has played enough to have an opinion, and the tenth is somebody who
    /// stayed. Apple throttles the sheet itself — a few asks a year at most, and none if
    /// the phone has been told not to — so this is a suggestion to the system rather
    /// than a nag to the player, and most of the time it shows nothing. A second and a
    /// half later, so the summary card is on the screen before anything is put over it.
    /// Never on a staged run: a photograph of the game must not have a system sheet in
    /// it, and the staged wallet's round count is whatever the gallery needed anyway.
    private func askForARating() {
        guard stage == nil, bank.wallet.rounds == 3 || bank.wallet.rounds == 10 else { return }
        Task {
            try? await Task.sleep(for: .seconds(1.5))
            requestReview()
        }
    }

    /// A round from what the wallet asked for: one borough's places, or every open
    /// borough's places put together. Read at the moment of starting, so a pick made
    /// on the menu is what the next round is about.
    private func startRound() {
        let pool: [Place]
        switch bank.wallet.pick {
        case .borough(let borough): pool = Place.all(in: borough)
        case .anywhere: pool = bank.wallet.playable.flatMap(Place.all(in:))
        }
        showing = nil
        candidate = nil
        round = QuizRound(askingAbout: pool)
        // A fresh round starts on the whole borough. Mid-round it never does.
        opening += 1
    }

    /// Back to the menu, from the end of a round or from the middle of one.
    ///
    /// A round part-way through is simply dropped, and nothing it had earned is banked.
    /// A round pays when it is played out — paying for an abandoned one would make
    /// answering the three you knew and walking away a better rate than finishing,
    /// which is the opposite of what the money is for.
    private func leave() {
        withAnimation(.easeOut(duration: 0.25)) {
            round = nil
            showing = nil
            candidate = nil
        }
        opening += 1
    }

    // MARK: - Staging, for the gallery

    /// A Manhattan place by name, for the staging. Looked up in the data rather than on
    /// a drawing, so the round can be built before the map is.
    private static func place(named name: String) -> Place? {
        BoroughMap.of(.manhattan).neighborhoods
            .firstIndex { $0.name == name }
            .map { Place(.manhattan, $0) }
    }

    /// Plays a round forward to the moment a screenshot wants. Everything here goes
    /// through `guess` like anybody else's round would, so a staged screen is a real
    /// state of the game rather than a picture of one.
    private func play(_ round: inout QuizRound, to stage: Stage) {
        // The same places a player would be allowed to pick: not the answer, not already
        // tried this question, and not one the round has settled. Anything else would put
        // a neighborhood into two of the map's lists at once and draw it twice.
        func elsewhere(_ count: Int) {
            var made = 0
            for place in Place.all(in: .manhattan) {
                guard made < count else { return }
                guard place != round.current, !round.ruledOut.contains(place),
                      !round.found.contains(place), !round.missed.contains(place)
                else { continue }
                _ = round.guess(place)
                made += 1
            }
        }

        switch stage {
        case .menu, .asking:
            break
        case .picked:
            candidate = QuizView.place(named: "SoHo")
        case .narrowing:
            elsewhere(2)
            candidate = QuizView.place(named: "West Village")
        case .filling:
            for _ in 0..<4 { if let wanted = round.current { _ = round.guess(wanted) } }
        case .missed:
            for _ in 0..<2 { if let wanted = round.current { _ = round.guess(wanted) } }
            elsewhere(QuizRound.tries)
            if let given = round.missed.last { showing = .missed(given) }
        case .over:
            var asked = 0
            while let wanted = round.current {
                if asked == 4 || asked == 7 {
                    elsewhere(QuizRound.tries)
                } else {
                    if asked % 3 == 1 { elsewhere(1) }
                    _ = round.guess(wanted)
                }
                asked += 1
            }
        }
    }
}

#Preview {
    QuizView()
}
