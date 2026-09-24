import StoreKit
import SwiftUI

/// What build this is, two ways to send the app on, and the one destructive thing it
/// can do to itself.
///
/// Four rows and nothing else. A settings screen that offers to throw away everything
/// somebody has earned should have very little else on it to mis-tap around, and the
/// two rows between the version and the delete both open something of the phone's — a
/// store page, a share sheet — rather than doing anything to the wallet.
struct SettingsView: View {
    let bank: Bank
    var onClose: () -> Void = {}

    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.openURL) private var openURL
    @Environment(\.requestReview) private var requestReview
    @State private var askingToDelete = false

    private var palette: MapPalette { .of(colorScheme) }

    var body: some View {
        ZStack {
            palette.water.ignoresSafeArea()
            PaperTexture(palette: palette)

            ScrollView {
                VStack(spacing: 18) {
                    Text("Settings")
                        .font(MapFont.chrome(size: 32))
                        .foregroundStyle(palette.ink)

                    version
                    rate
                    share
                    savedData

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
        // The one system-looking thing in an app that is otherwise all paper, and
        // deliberately so: this cannot be undone, and a dialog that is unmistakably the
        // phone asking rather than the drawing asking is the right amount of alarming.
        .confirmationDialog(
            "Delete all saved data?",
            isPresented: $askingToDelete,
            titleVisibility: .visible
        ) {
            Button("Delete all saved data", role: .destructive) {
                bank.erase()
            }
            Button("Keep it", role: .cancel) {}
        } message: {
            Text("Your wallet, everything you have earned and every borough you have bought. This cannot be undone.")
        }
    }

    // MARK: - Rows

    private var version: some View {
        row {
            HStack {
                Text("Version")
                    .font(MapFont.chrome(size: 20))
                    .foregroundStyle(palette.ink)
                Spacer(minLength: 12)
                Text(AppVersion.text)
                    .font(.system(size: 14, weight: .medium))
                    .foregroundStyle(palette.inkSoft)
                    .monospacedDigit()
            }
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Version \(AppVersion.text)")
    }

    /// Straight to the review form on the store page when there is a store page, and
    /// otherwise Apple's in-app sheet — which is the best that can be done before the
    /// app record exists, and which Apple may decline to show at all. Somebody who came
    /// to Settings to rate the app has asked; the store page always answers.
    private var rate: some View {
        Button {
            if let url = AppStore.reviewURL {
                openURL(url)
            } else {
                requestReview()
            }
        } label: {
            row { leading("Rate the app") }
        }
        .buttonStyle(.plain)
    }

    /// The plain "try this" message, handed to whatever the phone can send it with.
    private var share: some View {
        ShareLink(item: AppStore.shareText) {
            row { leading("Share the app") }
        }
        .buttonStyle(.plain)
    }

    /// A row that goes somewhere: the title, and a mark at the far end saying so.
    private func leading(_ title: String) -> some View {
        HStack {
            Text(title)
                .font(MapFont.chrome(size: 20))
                .foregroundStyle(palette.ink)
            Spacer(minLength: 12)
            Text("\u{203A}")
                .font(MapFont.chrome(size: 22))
                .foregroundStyle(palette.inkSoft)
                // Decoration. Read out, it is "single right-pointing angle quotation
                // mark", which is no help to anybody.
                .accessibilityHidden(true)
        }
    }

    private var savedData: some View {
        let empty = bank.wallet.isEmpty

        return row {
            VStack(alignment: .leading, spacing: 10) {
                Text("Saved data")
                    .font(MapFont.chrome(size: 20))
                    .foregroundStyle(palette.ink)

                Text(empty ? nothingSaved : whatIsSaved)
                    .font(.system(size: 13))
                    .foregroundStyle(palette.inkSoft)
                    .fixedSize(horizontal: false, vertical: true)

                Button {
                    askingToDelete = true
                } label: {
                    Text("Delete all saved data")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(empty ? palette.inkSoft.opacity(0.6) : palette.labelHalo)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 11)
                        .background(
                            Capsule()
                                .fill(empty ? palette.inkSoft.opacity(0.15) : palette.ruledOutInk)
                        )
                }
                .buttonStyle(.plain)
                .disabled(empty)
                .padding(.top, 2)
            }
        }
    }

    /// Said plainly, and including the part people actually want to know: it is on this
    /// phone and nowhere else, so this is the only copy and deleting it is the end of it.
    private var whatIsSaved: String {
        let wallet = bank.wallet
        let rounds = wallet.rounds == 1 ? "1 round" : "\(wallet.rounds) rounds"
        return "\(Money.text(wallet.balance)) to spend, \(Money.text(wallet.earned)) earned "
            + "across \(rounds), and any boroughs bought. Kept on this phone and nowhere "
            + "else, so there is no other copy."
    }

    private var nothingSaved: String {
        "Nothing saved yet. Play a round and what you earn will be kept here."
    }

    private func row<Content: View>(@ViewBuilder _ content: () -> Content) -> some View {
        content()
            .padding(.horizontal, 16)
            .padding(.vertical, 14)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .fill(palette.land.opacity(0.97))
                    .overlay(
                        RoundedRectangle(cornerRadius: 16, style: .continuous)
                            .strokeBorder(palette.inkSoft, lineWidth: 1.8)
                    )
            )
            // The row is the button on the two rows that are one, so the whole of the
            // paper has to take the tap and not just the lettering on it.
            .contentShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
    }
}
