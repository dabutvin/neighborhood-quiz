import SwiftUI

/// One tutorial tip, on paper.
///
/// Dressed like the question card — a small lettered line over a name in the hand — so
/// it reads as part of the game rather than as the phone interrupting it, with a
/// terracotta edge and "TIP" where the question card says "FIND", so the two are never
/// mistaken for each other.
struct TipCard: View {
    let step: Tutorial.Step
    let wallet: Wallet
    let palette: MapPalette
    /// Ends the tips. Nothing on the last one, which goes when the round's card does.
    var onSkip: (() -> Void)?

    var body: some View {
        let tip = step.tip(for: wallet)

        VStack(alignment: .leading, spacing: 4) {
            HStack(alignment: .firstTextBaseline) {
                Text("TIP \(step.number) OF \(Tutorial.tipCount)")
                    .font(.system(size: 10, weight: .semibold))
                    .kerning(2.2)
                    .foregroundStyle(palette.highlightInk)
                Spacer(minLength: 8)
                if let onSkip {
                    Button("Skip", action: onSkip)
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(palette.inkSoft)
                        .buttonStyle(.plain)
                        .accessibilityLabel("Skip the tips")
                }
            }

            Text(tip.title)
                .font(MapFont.chrome(size: 21))
                .foregroundStyle(palette.ink)

            Text(tip.body)
                .font(.system(size: 13))
                .foregroundStyle(palette.ink.opacity(0.82))
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .frame(maxWidth: 440, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(palette.land.opacity(0.97))
                .overlay(
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .strokeBorder(palette.highlightInk, lineWidth: 1.6)
                )
                .shadow(color: .black.opacity(0.12), radius: 6, y: 2)
        )
    }
}
