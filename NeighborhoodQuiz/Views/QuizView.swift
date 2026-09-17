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
    /// The place just found, held on screen for a moment with its name on it before the
    /// round moves along. Also what stops a fast thumb from answering the next question
    /// before it has read it.
    @State private var found: Int?
    /// Bumped between questions to send the map back to the whole island.
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
                        selected: found,
                        ruledOut: round?.ruledOut ?? [],
                        resetToken: opening,
                        onTap: guess,
                        onReady: start
                    )
                    PaperTexture(palette: palette)
                }
            }

            if let round, round.isFinished {
                summary(of: round)
            }
        }
        .background(palette.water)
        // Holding the found place on screen, then moving along. `task(id:)` rather than
        // a Task started by hand: it is cancelled for us if the view goes away or if
        // `found` changes underneath it, which is the whole of what could go wrong here.
        .task(id: found) {
            guard found != nil else { return }
            try? await Task.sleep(for: .seconds(1.2))
            guard !Task.isCancelled else { return }
            withAnimation(.easeInOut(duration: 0.3)) { found = nil }
            opening += 1
        }
    }

    // MARK: - The question

    @ViewBuilder
    private func prompt(for round: QuizRound) -> some View {
        let wanted = round.current.flatMap { names[$0] } ?? ""

        VStack(spacing: 2) {
            HStack {
                Text("FIND")
                    .font(.system(size: 10, weight: .semibold))
                    .kerning(2.2)
                Spacer()
                Text("\(round.index + 1) of \(round.questions.count)")
                    .font(.system(size: 10, weight: .semibold))
                    .kerning(1.2)
            }
            .foregroundStyle(palette.inkSoft)

            Text(wanted)
                .font(MapFont.chrome(size: 30))
                .foregroundStyle(found == nil ? palette.ink : palette.highlightInk)
                .frame(maxWidth: .infinity, alignment: .leading)
                .minimumScaleFactor(0.6)
                .lineLimit(1)

            HStack {
                // A space rather than nothing, so the card does not change height on
                // the first tap of a round.
                Text(round.taps == 0 ? " " : tally(round.taps, of: "tap"))
                Spacer()
                if !round.ruledOut.isEmpty {
                    Text("\(round.ruledOut.count) crossed off")
                }
            }
            .font(.system(size: 10, weight: .medium))
            .foregroundStyle(palette.inkSoft.opacity(0.85))
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

    private func tally(_ count: Int, of thing: String) -> String {
        "\(count) \(thing)\(count == 1 ? "" : "s")"
    }

    // MARK: - The end of it

    private func summary(of round: QuizRound) -> some View {
        VStack(spacing: 14) {
            Text("Round over")
                .font(MapFont.chrome(size: 30))
                .foregroundStyle(palette.ink)

            VStack(spacing: 4) {
                Text("\(round.taps)")
                    .font(MapFont.chrome(size: 54))
                    .foregroundStyle(palette.highlightInk)
                Text(round.taps == round.questions.count
                     ? "taps — a perfect round"
                     : "taps, and \(round.questions.count) is perfect")
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

    private func guess(_ id: Int?) {
        // While the found place is on screen the round has effectively moved on, and a
        // tap landing in that moment belongs to nobody.
        guard found == nil, let id, var playing = round, !playing.isFinished else { return }

        // Unwrapped and put back rather than mutated through the optional, so that what
        // the round did and what the screen does next are two plain steps.
        let answer = playing.guess(id)
        round = playing

        // Setting this both shows the place with its name on and starts the pause above.
        guard answer == .right else { return }
        withAnimation(.easeOut(duration: 0.2)) { found = id }
    }

    private func playAgain() {
        guard !names.isEmpty else { return }
        found = nil
        round = QuizRound(askingAbout: Array(names.keys))
        opening += 1
    }
}

#Preview {
    QuizView()
}
