import SwiftUI
import UIKit

/// The tooth of the paper the map is drawn on.
///
/// It is a small square of specks generated once and then tiled, rather than noise
/// drawn over the whole screen every frame: the grain has no business re-rolling
/// itself while somebody is dragging the island about, and a tile costs nothing to
/// repeat. The specks are laid down with the same seeded pen the map uses, so the
/// paper is the same paper on every launch.
@MainActor
enum PaperGrain {
    static let side = 96.0
    static let speckCount = 2_200

    /// A template image — all alpha, no colour — so the view tints it to whatever the
    /// paper happens to be, light or dark.
    static let tile: UIImage = {
        let format = UIGraphicsImageRendererFormat.default()
        format.opaque = false
        format.scale = 1
        let size = CGSize(width: side, height: side)

        let image = UIGraphicsImageRenderer(size: size, format: format).image { context in
            var random = SeededRandom(seed: 4_831)
            context.cgContext.setFillColor(UIColor.black.cgColor)
            for _ in 0..<speckCount {
                let diameter = 0.4 + random.next() * 1.0
                context.cgContext.fillEllipse(in: CGRect(
                    x: random.next() * side,
                    y: random.next() * side,
                    width: diameter,
                    height: diameter
                ))
            }
        }
        return image.withRenderingMode(.alwaysTemplate)
    }()
}

/// The grain, plus the vignette that makes the sheet look like it has an edge and a
/// middle rather than being a flat fill.
struct PaperTexture: View {
    let palette: MapPalette

    var body: some View {
        ZStack {
            Image(uiImage: PaperGrain.tile)
                .resizable(resizingMode: .tile)
                .renderingMode(.template)
                .foregroundStyle(palette.grain)
                .opacity(0.07)

            RadialGradient(
                colors: [.clear, palette.waterInk.opacity(0.22)],
                center: .center,
                startRadius: 40,
                endRadius: 620
            )
        }
        .allowsHitTesting(false)
        .ignoresSafeArea()
    }
}
