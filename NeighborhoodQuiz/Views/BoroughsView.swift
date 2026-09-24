import SwiftUI

/// The city: what you have, what the next borough costs, and what is a long way off.
///
/// Every borough is listed, because a game about saving up has to show you what there
/// is to save for. What the list does not carry is a price per row. The next borough
/// costs the same whichever one it is — the price climbs with how many you have bought,
/// not with which — so the price is said once, on the card above the list, with the bar
/// and how far off it is. The rows are then only states: playing, or a way to get
/// there, for the ones that are open; Unlock, or the word "locked", for the drawn ones
/// that are not; and a plain word for one whose map is still being drawn. The whole
/// city is drawn now, so nothing reaches that last state — it stays because it is the
/// honest fallback for the next map that is not, whichever that turns out to be.
///
/// An open row says either that you are there or offers to take you — which is the
/// other thing this screen can do now that there is more than one place to be. A round
/// running over the whole city is "there" nowhere in particular, so every open row
/// offers; the menu is where "Anywhere" lives, and this screen does not repeat it.
struct BoroughsView: View {
    let bank: Bank
    var onClose: () -> Void = {}

    @Environment(\.colorScheme) private var colorScheme
    private var palette: MapPalette { .of(colorScheme) }
    private var wallet: Wallet { bank.wallet }

    var body: some View {
        ZStack {
            palette.water.ignoresSafeArea()
            PaperTexture(palette: palette)

            ScrollView {
                VStack(spacing: 18) {
                    Text("The City")
                        .font(MapFont.chrome(size: 32))
                        .foregroundStyle(palette.ink)

                    purse

                    nextBorough

                    VStack(spacing: 0) {
                        ForEach(Array(Borough.allCases.enumerated()), id: \.element.id) { index, borough in
                            if index > 0 {
                                Rectangle()
                                    .fill(palette.inkSoft.opacity(0.25))
                                    .frame(height: 1)
                            }
                            row(for: borough)
                        }
                    }
                    .background(paper)

                    Button(action: onClose) {
                        Text("Done")
                            .font(MapFont.chrome(size: 20))
                            .foregroundStyle(palette.ink)
                            .padding(.horizontal, 30)
                            .padding(.vertical, 10)
                            .background(
                                Capsule()
                                    .fill(palette.land)
                                    .overlay(Capsule().strokeBorder(palette.inkSoft, lineWidth: 1.8))
                            )
                    }
                    .buttonStyle(.plain)
                    .padding(.top, 2)
                }
                .padding(22)
            }
        }
    }

    /// The card every block on this screen sits on.
    private var paper: some View {
        RoundedRectangle(cornerRadius: 16, style: .continuous)
            .fill(palette.land.opacity(0.97))
            .overlay(
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .strokeBorder(palette.inkSoft, lineWidth: 1.8)
            )
    }

    // MARK: - What is in the purse

    private var purse: some View {
        HStack(spacing: 0) {
            figure(Money.text(wallet.balance), "to spend", big: true)
            divider
            figure(Money.text(wallet.earned), "earned in all")
            divider
            figure("\(wallet.rounds)", wallet.rounds == 1 ? "round" : "rounds")
        }
        .padding(.vertical, 14)
        .background(paper)
    }

    private var divider: some View {
        Rectangle()
            .fill(palette.inkSoft.opacity(0.25))
            .frame(width: 1, height: 34)
    }

    private func figure(_ value: String, _ label: String, big: Bool = false) -> some View {
        VStack(spacing: 1) {
            Text(value)
                .font(MapFont.chrome(size: big ? 28 : 22))
                .foregroundStyle(big ? palette.highlightInk : palette.ink)
                .monospacedDigit()
                .minimumScaleFactor(0.5)
                .lineLimit(1)
            Text(label.uppercased())
                .font(.system(size: 8, weight: .semibold))
                .kerning(1.1)
                .foregroundStyle(palette.inkSoft)
        }
        .frame(maxWidth: .infinity)
        .padding(.horizontal, 6)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(value) \(label)")
    }

    // MARK: - The next borough

    /// Whether there is anything on the list the Unlock button could be pressed for.
    /// The money being there is not enough: an unowned borough could be one whose map
    /// is not drawn — none is today — and the line under the bar has to say which it is.
    private var somethingToUnlock: Bool {
        Borough.buyable.contains { wallet.canBuy($0) }
    }

    /// The price, the bar, and one line about the gap between them.
    ///
    /// A card of its own rather than a line on a row, because the price is the next
    /// rung of the ladder and belongs to no borough in particular — it is what the
    /// next one costs, whichever the player picks from the list below. Once the whole
    /// city is bought there is no bar and nothing to save for, and the card says so.
    private var nextBorough: some View {
        VStack(spacing: 10) {
            HStack(spacing: 10) {
                Text("Next borough")
                    .font(MapFont.chrome(size: 22))
                    .foregroundStyle(palette.ink)
                Spacer(minLength: 8)
                if let price = wallet.nextPrice {
                    Text(Money.text(price))
                        .font(MapFont.chrome(size: 22))
                        .foregroundStyle(palette.ink)
                        .monospacedDigit()
                }
            }

            if let price = wallet.nextPrice {
                GeometryReader { geometry in
                    ZStack(alignment: .leading) {
                        Capsule()
                            .fill(palette.inkSoft.opacity(0.22))
                        Capsule()
                            .fill(palette.highlight)
                            .frame(width: max(geometry.size.width * wallet.progress, wallet.progress > 0 ? 6 : 0))
                    }
                }
                .frame(height: 9)

                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    Text("\(Money.text(wallet.saved)) of \(Money.text(price))")
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(palette.inkSoft)
                        .monospacedDigit()
                    Spacer(minLength: 6)
                    gap(to: price)
                        .multilineTextAlignment(.trailing)
                        .fixedSize(horizontal: false, vertical: true)
                }
            } else {
                Text("The whole city is yours")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(palette.highlightInk)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 14)
        .background(paper)
        .accessibilityElement(children: .combine)
        .accessibilityLabel(spokenNext)
    }

    /// Three things this can say, and they are not interchangeable.
    ///
    /// Short of the money: how much more. Enough money and a drawn borough to spend it
    /// on: go and pick one. Enough money and no map to spend it on: says so plainly.
    /// The last one is the whole reason `canAfford` and `canBuy` are different
    /// questions — taking the money for a borough the game cannot open would be the
    /// worst thing on this screen.
    @ViewBuilder
    private func gap(to price: Int) -> some View {
        if wallet.balance < price {
            Text("\(Money.text(price - wallet.balance)) to go")
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(palette.inkSoft.opacity(0.85))
                .monospacedDigit()
        } else if somethingToUnlock {
            Text("saved up — pick one below")
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(palette.highlightInk)
        } else {
            Text("saved up — the next maps are still being drawn")
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(palette.highlightInk)
        }
    }

    private var spokenNext: String {
        guard let price = wallet.nextPrice else { return "Next borough. The whole city is yours." }
        let count = "\(Money.text(wallet.saved)) of \(Money.text(price))"
        guard wallet.balance >= price else {
            return "Next borough, \(count). \(Money.text(price - wallet.balance)) to go."
        }
        return somethingToUnlock
            ? "Next borough, \(count). Saved up, pick one below."
            : "Next borough, \(count). Saved up, the next maps are still being drawn."
    }

    // MARK: - A row

    private func row(for borough: Borough) -> some View {
        let owned = wallet.has(borough)

        return HStack(spacing: 10) {
            Text(borough.name)
                .font(MapFont.chrome(size: 22))
                .foregroundStyle(owned ? palette.ink : palette.inkSoft.opacity(borough.isDrawn ? 1 : 0.7))
            Spacer(minLength: 8)
            status(for: borough, owned: owned)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 13)
        .accessibilityElement(children: .combine)
        .accessibilityLabel(spoken(for: borough, owned: owned))
    }

    /// What the right-hand end of a row says.
    ///
    /// Owned and drawn: "playing" if the next round is this borough's, otherwise a way
    /// to make it so. Owned and not drawn: "bought", which is a state the game can
    /// reach only by a build that has stopped drawing something — the button never
    /// sells a blank page — but a wallet is a preference on a phone and outlives the
    /// build that wrote it. Not owned and drawn: the Unlock button when the money is
    /// there, and the word "locked" when it is not. Not owned and not drawn: says so,
    /// with or without the money, because there is nothing to press either way.
    ///
    /// No price on any of them. They all cost the next rung, and the card above the
    /// list says what that is.
    @ViewBuilder
    private func status(for borough: Borough, owned: Bool) -> some View {
        if owned, borough.isDrawn {
            if wallet.pick == .borough(borough) {
                Text("playing")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(palette.highlightInk)
            } else {
                play(borough)
            }
        } else if owned {
            Text("bought")
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(palette.highlightInk)
        } else if borough.isDrawn {
            if wallet.canBuy(borough) {
                unlock(borough)
            } else {
                Text("locked")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(palette.inkSoft)
            }
        } else {
            Text("map still being drawn")
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(palette.inkSoft)
        }
    }

    /// Go and play a borough that is open. The same shape as the Unlock button so the
    /// eye reads the two as the same kind of thing, but outlined in ink rather than
    /// filled in terracotta: unlocking spends money and moving spends nothing. The
    /// sheet closes behind it, because the map you asked for is underneath.
    private func play(_ borough: Borough) -> some View {
        Button {
            bank.play(borough)
            onClose()
        } label: {
            Text("Play")
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(palette.ink)
                .padding(.horizontal, 14)
                .padding(.vertical, 6)
                .background(
                    Capsule()
                        .fill(palette.land)
                        .overlay(Capsule().strokeBorder(palette.ink, lineWidth: 1.5))
                )
        }
        .buttonStyle(.plain)
    }

    /// Spend the next rung on this borough. Only ever shown when `canBuy` says so,
    /// which is the money and the map together; the wallet checks again underneath.
    private func unlock(_ borough: Borough) -> some View {
        Button {
            bank.buy(borough)
        } label: {
            Text("Unlock")
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(palette.labelHalo)
                .padding(.horizontal, 14)
                .padding(.vertical, 6)
                .background(Capsule().fill(palette.highlightInk))
        }
        .buttonStyle(.plain)
    }

    private func spoken(for borough: Borough, owned: Bool) -> String {
        guard !owned else {
            guard borough.isDrawn else { return "\(borough.name), bought, map not drawn yet" }
            return wallet.pick == .borough(borough)
                ? "\(borough.name), open, playing"
                : "\(borough.name), open, tap to play"
        }
        guard borough.isDrawn else { return "\(borough.name), map still being drawn" }
        guard wallet.canBuy(borough), let price = wallet.nextPrice else {
            return "\(borough.name), locked"
        }
        return "\(borough.name), ready to unlock for \(Money.text(price))"
    }
}
