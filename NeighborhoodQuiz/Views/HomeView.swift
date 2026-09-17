import SwiftUI

/// The map on its own, with no game attached: tap anywhere on land and it tells you what
/// that is.
///
/// The app opens on `QuizView` now, so nothing a player does reaches this. It is kept
/// because it is what the screenshot runs shoot — the map is most of what this app is,
/// and a regression in the drawing is far easier to see on a screen with nothing else
/// happening on it than it is behind a prompt and a highlight.
struct HomeView: View {
    var opening: MapBoard.Opening = .island
    /// Picked out from the start, for the shot that shows what a highlight looks like.
    var showing: String?

    @Environment(\.colorScheme) private var colorScheme

    @State private var selected: Int?

    private var palette: MapPalette { .of(colorScheme) }

    var body: some View {
        ZStack {
            palette.water.ignoresSafeArea()

            MapBoard(
                palette: palette,
                opening: opening,
                selected: selected,
                onTap: { selected = ($0 == selected) ? nil : $0 },
                onReady: { map in
                    if let showing, selected == nil {
                        selected = map.neighborhood(named: showing)?.id
                    }
                }
            )
            .accessibilityElement()
            .accessibilityLabel("Map of Manhattan")
            .accessibilityHint("Drag to move the map, pinch to zoom in, tap a neighborhood to name it")
            .sensoryFeedback(.selection, trigger: selected)

            PaperTexture(palette: palette)

            header
            credit
        }
        .background(palette.water)
    }

    private var header: some View {
        VStack(alignment: .trailing, spacing: 1) {
            Text("NYC Neighborhoods")
                .font(MapFont.chrome(size: 24))
                .foregroundStyle(palette.ink)
            Text("MANHATTAN")
                .font(.system(size: 10, weight: .semibold))
                .kerning(2.2)
                .foregroundStyle(palette.inkSoft)
        }
        .padding(.trailing, 18)
        .padding(.top, 10)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topTrailing)
        .allowsHitTesting(false)
    }

    /// Whose map this is. Every street on it was surveyed by the City of New York and
    /// published for anybody to use; the least the drawing can do is say so.
    private var credit: some View {
        Text("Map data: NYC Open Data")
            .font(.system(size: 9, weight: .medium))
            .kerning(0.4)
            .foregroundStyle(palette.inkSoft.opacity(0.75))
            .padding(.leading, 16)
            .padding(.bottom, 10)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottomLeading)
            .allowsHitTesting(false)
    }
}

#Preview {
    HomeView()
}
