import SwiftUI

/// The game. A name at the top, the island below it, and your finger to get from one to
/// the other.
///
/// Nothing on the map says where anything is — the borders are drawn but no neighborhood
/// is named until you have found it — so the only way through is to know, or to work it
/// out from the streets, which is the same thing a block later.
struct QuizView: View {
    @Environment(\.colorScheme) private var colorScheme

    @State private var round: QuizRound?
    @State private var names: [Int: String] = [:]
    /// The place just found, held large and with a coat of paper under it for a moment
    /// before the round moves along and it settles in with the rest. Also what stops a
    /// fast thumb from answering the next question before it has read it.
    @State private var justFound: Int?
    /// Picked out and waiting on the button. A tap on the map chooses; it is answering
    /// with it that goes on the card, so a thumb landing somewhere careless is free to
    /// be taken back.
    @State private var candidate: Int?
    /// Bumped at the start of a round to send the map back to the whole island. Not
    /// between questions: where you have got the map to is yours, and pulling it back
    /// out every time was undoing the player's own work.
    @State private var opening = 0

    private var palette: MapPalette { .of(colorScheme) }

    var body: some View {
        ZStack {
            palette.water.ignoresSafeArea()

            // Stacked rather than layered, so the map is drawn into what is left over
            // after the question has had its share. Over the top, the card hid the
            // northern end of the island — which was fine until the question was Inwood
            // and the answer was underneath it.
            VStack(spacing: 0) {
                if let round, !round.isFinished {
                    prompt(for: round)
                }

                ZStack {
                    MapBoard(
                        palette: palette,
                        selected: justFound,
                        ruledOut: round?.ruledOut ?? [],
                        settled: Set(round?.found ?? []),
                        candidate: candidate,
                        resetToken: opening,
                        onTap: pick,
                        onReady: start
                    )
                    PaperTexture(palette: palette)
                }
            }

            if let round, round.isFinished {
                summary(of: round)
            } else if candidate != nil, justFound == nil {
                answerButton
            }
        }
        .background(palette.water)
        // Holding the found place on screen, then moving along. `task(id:)` rather than
        // a Task started by hand: it is cancelled for us if the view goes away or if
        // `found` changes underneath it, which is the whole of what could go wrong here.
        .task(id: justFound) {
            guard justFound != nil else { return }
            try? await Task.sleep(for: .seconds(1.2))
            guard !Task.isCancelled else { return }
            withAnimation(.easeInOut(duration: 0.3)) { justFound = nil }
        }
    }

    // MARK: - The question

    @ViewBuilder
    private func prompt(for round: QuizRound) -> some View {
        let wanted = round.current.flatMap { names[$0] } ?? ""

        // Two rows rather than three. The island is tall and thin and so is always
        // fitted by its height, which means every point this card takes is a point off
        // the map — and what has been crossed off is already plain on the map itself,
        // greyed where you guessed.
        VStack(spacing: 2) {
            HStack {
                Text("FIND")
                    .font(.system(size: 10, weight: .semibold))
                    .kerning(2.2)
                Spacer()
                Text(standing(of: round))
                    .font(.system(size: 10, weight: .semibold))
                    .kerning(1.2)
                    .monospacedDigit()
            }
            .foregroundStyle(palette.inkSoft)

            Text(wanted)
                .font(MapFont.chrome(size: 30))
                .foregroundStyle(justFound == nil ? palette.ink : palette.highlightInk)
                .frame(maxWidth: .infinity, alignment: .leading)
                .minimumScaleFactor(0.6)
                .lineLimit(1)
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
        .accessibilityLabel("Find \(wanted). Question \(round.index + 1) of \(round.questions.count).")
    }

    /// How far through, and what it has cost so far. The cost only appears once there
    /// is one, so a round opens without a nought staring at you.
    private func standing(of round: QuizRound) -> String {
        let progress = "\(round.index + 1) of \(round.questions.count)"
        guard round.guesses > 0 else { return progress }
        return "\(progress)   \(round.guesses) guess\(round.guesses == 1 ? "" : "es")"
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

            VStack(spacing: 4) {
                Text("\(round.guesses)")
                    .font(MapFont.chrome(size: 54))
                    .foregroundStyle(palette.highlightInk)
                Text(round.guesses == round.questions.count
                     ? "guesses — a perfect round"
                     : "guesses, and \(round.questions.count) is perfect")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(palette.inkSoft)
            }

            Text("\(round.firstTime) of \(round.questions.count) found first time")
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(palette.inkSoft)

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

    // MARK: - Playing

    private func start(_ map: DrawnMap) {
        names = Dictionary(uniqueKeysWithValues: map.neighborhoods.map { ($0.id, $0.name) })
        guard round == nil else { return }
        round = QuizRound(askingAbout: map.neighborhoods.map(\.id))
    }

    /// A tap on the map. It picks a place out and costs nothing — the score only moves
    /// when you answer with it.
    ///
    /// Water, the parks, and anywhere already crossed off or already found all put the
    /// pick down again. There is nothing to be gained by choosing a place the round has
    /// already settled, and leaving it selectable would only invite somebody to answer
    /// with it and wonder why nothing happened.
    private func pick(_ id: Int?) {
        // While the found place is on screen the round has moved on, and a tap landing
        // in that moment belongs to nobody.
        guard justFound == nil, let round, !round.isFinished else { return }

        guard let id, !round.ruledOut.contains(id), !round.found.contains(id) else {
            withAnimation(.easeOut(duration: 0.15)) { candidate = nil }
            return
        }
        withAnimation(.easeOut(duration: 0.15)) {
            candidate = (id == candidate) ? nil : id
        }
    }

    /// Answering with what is picked. This is the only thing that costs anything.
    private func answer() {
        guard justFound == nil, let picked = candidate,
              var playing = round, !playing.isFinished
        else { return }

        // Unwrapped and put back rather than mutated through the optional, so that what
        // the round did and what the screen does next are two plain steps.
        let outcome = playing.guess(picked)
        round = playing
        withAnimation(.easeOut(duration: 0.2)) { candidate = nil }

        // Setting this both shows the place with its name on and starts the pause above.
        guard outcome == .right else { return }
        withAnimation(.easeOut(duration: 0.2)) { justFound = picked }
    }

    private func playAgain() {
        guard !names.isEmpty else { return }
        justFound = nil
        candidate = nil
        round = QuizRound(askingAbout: Array(names.keys))
        // A fresh round starts on the whole island. Mid-round it never does.
        opening += 1
    }
}

#Preview {
    QuizView()
}
