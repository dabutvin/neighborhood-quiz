import SwiftUI

/// The ladder: what you have, what you are saving for, and what is a long way off.
///
/// Every borough is listed, including the ones that are nowhere near affordable, because
/// a game about saving up has to show you what you are saving for. A locked row still
/// carries its price.
///
/// One row is different: the one being saved for gets the bar. Only that row can change
/// today, so only that row is worth drawing in detail.
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
                    .background(
                        RoundedRectangle(cornerRadius: 16, style: .continuous)
                            .fill(palette.land.opacity(0.97))
                            .overlay(
                                RoundedRectangle(cornerRadius: 16, style: .continuous)
                                    .strokeBorder(palette.inkSoft, lineWidth: 1.8)
                            )
                    )

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
        .background(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(palette.land.opacity(0.97))
                .overlay(
                    RoundedRectangle(cornerRadius: 16, style: .continuous)
                        .strokeBorder(palette.inkSoft, lineWidth: 1.8)
                )
        )
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

    // MARK: - A rung

    @ViewBuilder
    private func row(for borough: Borough) -> some View {
        let owned = wallet.has(borough)
        let next = wallet.saving == borough

        VStack(spacing: 8) {
            HStack(spacing: 10) {
                Text(borough.name)
                    .font(MapFont.chrome(size: 22))
                    .foregroundStyle(owned ? palette.ink : palette.inkSoft.opacity(next ? 1 : 0.7))
                Spacer(minLength: 8)
                status(for: borough, owned: owned, next: next)
            }

            if next {
                saving(for: borough)
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 13)
        .accessibilityElement(children: .combine)
        .accessibilityLabel(spoken(for: borough, owned: owned, next: next))
    }

    @ViewBuilder
    private func status(for borough: Borough, owned: Bool, next: Bool) -> some View {
        if owned {
            Text(borough.isDrawn ? "open" : "bought")
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(palette.highlightInk)
        } else {
            Text(Money.text(borough.price))
                .font(MapFont.chrome(size: 20))
                .foregroundStyle(next ? palette.ink : palette.inkSoft.opacity(0.65))
                .monospacedDigit()
        }
    }

    /// The bar, the count, and whatever can be done about it.
    private func saving(for borough: Borough) -> some View {
        VStack(spacing: 7) {
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

            HStack(spacing: 8) {
                Text("\(Money.text(wallet.balance)) of \(Money.text(borough.price))")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(palette.inkSoft)
                    .monospacedDigit()
                Spacer(minLength: 6)
                buy(borough)
            }
        }
    }

    /// Three things this can say, and they are not interchangeable.
    ///
    /// Short of the money: how much more. Enough money and a map behind it: a button.
    /// Enough money and no map yet: says so plainly, and stays disabled. The last one is
    /// the whole reason `canAfford` and `canBuy` are different questions — taking two
    /// hundred dollars for a borough the game cannot open would be the worst thing on
    /// this screen.
    @ViewBuilder
    private func buy(_ borough: Borough) -> some View {
        if wallet.canBuy(borough) {
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
        } else if wallet.canAfford(borough) {
            Text("saved up — map still being drawn")
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(palette.highlightInk)
        } else {
            Text("\(Money.text(borough.price - wallet.balance)) to go")
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(palette.inkSoft.opacity(0.85))
                .monospacedDigit()
        }
    }

    private func spoken(for borough: Borough, owned: Bool, next: Bool) -> String {
        guard !owned else {
            return borough.isDrawn ? "\(borough.name), open" : "\(borough.name), bought, map not drawn yet"
        }
        guard next else { return "\(borough.name), locked, \(Money.text(borough.price))" }
        guard wallet.canAfford(borough) else {
            return "\(borough.name), \(Money.text(borough.price)). "
                + "\(Money.text(borough.price - wallet.balance)) to go."
        }
        return borough.isDrawn
            ? "\(borough.name), \(Money.text(borough.price)), ready to unlock"
            : "\(borough.name), saved up, map still being drawn"
    }
}
