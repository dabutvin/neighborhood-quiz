import SwiftUI

/// The game. A name at the top, the island below it, and three goes to put your finger
/// on the right place.
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
        /// A fresh question, nothing picked.
        case asking
        /// Somewhere picked, waiting on the button.
        case picked
        /// Two goes gone, two places crossed off, one go left.
        case narrowing
        /// Several found, the island filling in.
        case filling
        /// Three goes were not enough, and the round is showing where it was.
        case missed
        /// The end of it.
        case over
    }

    /// The places the gallery is played through, chosen to be recognisable rather than
    /// representative. A staged round always asks these, in this order.
    static let showcase = [
        "Greenwich Village", "SoHo", "Harlem", "Tribeca", "Chelsea",
        "Upper East Side", "East Village", "Times Square", "Chinatown", "Inwood",
    ]

    var stage: Stage?

    @Environment(\.colorScheme) private var colorScheme

    @State private var round: QuizRound?
    @State private var names: [Int: String] = [:]
    /// The place the round has just settled, held on the map with its name on for a
    /// moment before the next question. Also what stops a fast thumb from answering the
    /// next question before it has read it.
    @State private var showing: Shown?
    /// Picked out and waiting on the button. A tap on the map chooses; it is answering
    /// with it that spends a go, so a thumb landing somewhere careless is free to be
    /// taken back.
    @State private var candidate: Int?
    /// Bumped at the start of a round to send the map back to the whole island. Not
    /// between questions: where you have got the map to is yours, and pulling it back
    /// out every time was undoing the player's own work.
    @State private var opening = 0

    /// How a question ended, while it is still on screen.
    enum Shown: Equatable {
        case found(Int, worth: Int)
        case missed(Int)

        var id: Int {
            switch self {
            case .found(let id, _), .missed(let id): return id
            }
        }

        var isMiss: Bool {
            if case .missed = self { return true }
            return false
        }
    }

    private var palette: MapPalette { .of(colorScheme) }

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
                        selected: showing?.id,
                        ruledOut: round?.ruledOut ?? [],
                        settled: Set(round?.found ?? []),
                        givenAway: Set(round?.missed ?? []),
                        candidate: candidate,
                        resetToken: opening,
                        onTap: pick,
                        onReady: start
                    )
                    PaperTexture(palette: palette)
                }
            }

            if let round, round.isFinished, showing == nil {
                summary(of: round)
            } else if candidate != nil, showing == nil {
                answerButton
            }
        }
        .background(palette.water)
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

    // MARK: - The question

    private func prompt(for round: QuizRound) -> some View {
        let lead: String
        let name: String
        let ink: Color

        switch showing {
        case .found(let id, _):
            lead = "FOUND"
            name = names[id] ?? ""
            ink = palette.highlightInk
        case .missed(let id):
            lead = "IT WAS"
            name = names[id] ?? ""
            ink = palette.ruledOut
        case nil:
            lead = "FIND"
            name = round.current.flatMap { names[$0] } ?? ""
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
        .accessibilityLabel(spoken(lead: lead, name: name, round: round))
    }

    /// What the goes look like: three dots that go out as they are spent, and in their
    /// place, once a question has ended, what it was worth.
    @ViewBuilder
    private func verdict(for round: QuizRound) -> some View {
        switch showing {
        case .found(_, let worth):
            Text("+\(worth)")
                .font(MapFont.chrome(size: 22))
                .foregroundStyle(palette.highlightInk)
        case .missed:
            Text("0")
                .font(MapFont.chrome(size: 22))
                .foregroundStyle(palette.ruledOut)
        case nil:
            HStack(spacing: 5) {
                ForEach(0..<QuizRound.tries, id: \.self) { index in
                    Circle()
                        .fill(index < round.triesLeft ? palette.ink : .clear)
                        .overlay(Circle().strokeBorder(palette.inkSoft.opacity(0.7), lineWidth: 1.2))
                        .frame(width: 9, height: 9)
                }
            }
        }
    }

    /// How far through, and what it is worth so far. The score only appears once there
    /// is one, so a round opens without a nought staring at you.
    private func standing(of round: QuizRound) -> String {
        let asked = min(round.index + 1, round.questions.count)
        let progress = "\(asked) of \(round.questions.count)"
        guard round.score > 0 else { return progress }
        return "\(progress)   \(round.score) PTS"
    }

    private func spoken(lead: String, name: String, round: QuizRound) -> String {
        switch showing {
        case .found(_, let worth): return "Found \(name), worth \(worth) points."
        case .missed: return "Out of goes. It was \(name)."
        case nil:
            return "Find \(name). Question \(round.index + 1) of \(round.questions.count), "
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
                Text("\(round.score)")
                    .font(MapFont.chrome(size: 56))
                    .foregroundStyle(palette.highlightInk)
                Text(round.score == round.perfectScore
                     ? "out of \(round.perfectScore) — a perfect round"
                     : "out of \(round.perfectScore)")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(palette.inkSoft)
            }

            Text(breakdown(of: round))
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(palette.inkSoft)
                .multilineTextAlignment(.center)

            Button(action: playAgain) {
                Text("Play again")
                    .font(MapFont.chrome(size: 20))
                    .foregroundStyle(palette.ink)
                    .padding(.horizontal, 26)
                    .padding(.vertical, 10)
                    .background(
                        Capsule()
                            .fill(palette.land)
                            .overlay(Capsule().strokeBorder(palette.inkSoft, lineWidth: 1.8))
                    )
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 30)
        .padding(.vertical, 28)
        .background(
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .fill(palette.land.opacity(0.97))
                .overlay(
                    RoundedRectangle(cornerRadius: 20, style: .continuous)
                        .strokeBorder(palette.inkSoft, lineWidth: 2)
                )
        )
        .padding(28)
    }

    private func breakdown(of round: QuizRound) -> String {
        var parts = ["\(round.firstTime) of \(round.questions.count) first go"]
        if !round.missed.isEmpty {
            parts.append("\(round.missed.count) never found")
        }
        return parts.joined(separator: " · ")
    }

    // MARK: - Playing

    private func start(_ map: DrawnMap) {
        names = Dictionary(uniqueKeysWithValues: map.neighborhoods.map { ($0.id, $0.name) })
        guard round == nil else { return }

        guard let stage else {
            round = QuizRound(askingAbout: map.neighborhoods.map(\.id))
            return
        }
        var staged = QuizRound(asking: QuizView.showcase.compactMap { map.neighborhood(named: $0)?.id })
        play(&staged, to: stage, on: map)
        round = staged
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

        guard let id, !round.ruledOut.contains(id),
              !round.found.contains(id), !round.missed.contains(id)
        else {
            withAnimation(.easeOut(duration: 0.15)) { candidate = nil }
            return
        }
        withAnimation(.easeOut(duration: 0.15)) {
            candidate = (id == candidate) ? nil : id
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
        round = playing
        withAnimation(.easeOut(duration: 0.2)) { candidate = nil }

        // Setting this shows the place with its name on and starts the pause above.
        switch outcome {
        case .right:
            withAnimation(.easeOut(duration: 0.2)) { showing = .found(picked, worth: worth) }
        case .missed:
            guard let given = playing.missed.last else { return }
            withAnimation(.easeOut(duration: 0.2)) { showing = .missed(given) }
        case .wrong, .ignored:
            break
        }
    }

    private func playAgain() {
        guard !names.isEmpty else { return }
        showing = nil
        candidate = nil
        round = QuizRound(askingAbout: Array(names.keys))
        // A fresh round starts on the whole island. Mid-round it never does.
        opening += 1
    }

    // MARK: - Staging, for the gallery

    /// Plays a round forward to the moment a screenshot wants. Everything here goes
    /// through `guess` like anybody else's round would, so a staged screen is a real
    /// state of the game rather than a picture of one.
    private func play(_ round: inout QuizRound, to stage: Stage, on map: DrawnMap) {
        // The same places a player would be allowed to pick: not the answer, not already
        // tried this question, and not one the round has settled. Anything else would put
        // a neighborhood into two of the map's lists at once and draw it twice.
        func elsewhere(_ count: Int) {
            var made = 0
            for id in map.neighborhoods.map(\.id) {
                guard made < count else { return }
                guard id != round.current, !round.ruledOut.contains(id),
                      !round.found.contains(id), !round.missed.contains(id)
                else { continue }
                _ = round.guess(id)
                made += 1
            }
        }

        switch stage {
        case .asking:
            break
        case .picked:
            candidate = map.neighborhood(named: "SoHo")?.id
        case .narrowing:
            elsewhere(2)
            candidate = map.neighborhood(named: "West Village")?.id
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
