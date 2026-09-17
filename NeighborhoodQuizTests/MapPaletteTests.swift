import SwiftUI
import UIKit
import XCTest
@testable import NeighborhoodQuiz

/// Whether the colours the map writes in can actually be read off the colours it writes
/// on, in both schemes.
///
/// This exists because of a bug it would have caught in a second. `ruledOut` — the grey
/// a crossed-off place is washed with — was doing double duty as the colour a given-away
/// place is *lettered* in. By day that is harmless, because the same grey reads either
/// way on cream paper. By night the wash is nearly black by design, so "IT WAS Harlem"
/// came out as black handwriting on a black island: a contrast ratio of 1.26, which is
/// to say none at all. The one thing a player is owed after three failed goes is being
/// shown where the place was, and at night it was the least legible thing on the screen.
///
/// Nobody spotted it by reading the palette, and it survived a screenshot gallery,
/// because a dark smudge on a dark map still looks like a map. A number catches it.
@MainActor
final class MapPaletteTests: XCTestCase {

    /// Large text and graphical objects want 3:1 under WCAG, and everything the map
    /// letters in is large, hand-drawn and sitting on its own patch of cleared paper.
    /// The palette clears this with room to spare — the closest is 3.66 — so a failure
    /// here means a colour moved a long way, not that it drifted.
    private let readable = 3.0

    func testEveryInkCanBeReadOffThePaperItIsWrittenOn() {
        for (scheme, palette) in [("day", MapPalette.day), ("night", MapPalette.night)] {
            let inks = [
                ("ink", palette.ink),
                ("inkSoft", palette.inkSoft),
                ("label", palette.label),
                ("highlightInk", palette.highlightInk),
                ("ruledOutInk", palette.ruledOutInk),
            ]
            // A name is written over a clearing of `labelHalo`; a tally on the summary
            // card is written straight onto `land`. Both have to work.
            let surfaces = [("labelHalo", palette.labelHalo), ("land", palette.land)]

            for (inkName, ink) in inks {
                for (surfaceName, surface) in surfaces {
                    let ratio = contrast(ink, surface)
                    XCTAssertGreaterThanOrEqual(
                        ratio, readable,
                        "\(scheme): \(inkName) on \(surfaceName) is \(ratio), which is not readable"
                    )
                }
            }
        }
    }

    /// The wash is allowed to be — and at night has to be — far too dark to letter in.
    /// Dimming is how a place gets crossed off. This pins down that the two are separate
    /// colours doing separate jobs, which is the whole of the fix above.
    func testTheCrossedOffWashIsNotTheColourItIsLetteredIn() {
        XCTAssertLessThan(
            contrast(MapPalette.night.ruledOut, MapPalette.night.land), readable,
            "night: the wash is supposed to be a dimming, not an ink"
        )
        XCTAssertGreaterThanOrEqual(
            contrast(MapPalette.night.ruledOutInk, MapPalette.night.land), readable
        )
    }

    // MARK: - WCAG

    private func contrast(_ a: Color, _ b: Color) -> Double {
        let (high, low) = (max(luminance(a), luminance(b)), min(luminance(a), luminance(b)))
        return (high + 0.05) / (low + 0.05)
    }

    private func luminance(_ colour: Color) -> Double {
        var r: CGFloat = 0, g: CGFloat = 0, b: CGFloat = 0, a: CGFloat = 0
        _ = UIColor(colour).getRed(&r, green: &g, blue: &b, alpha: &a)
        let channels = [r, g, b].map { channel -> Double in
            let value = Double(channel)
            return value <= 0.03928 ? value / 12.92 : pow((value + 0.055) / 1.055, 2.4)
        }
        return 0.2126 * channels[0] + 0.7152 * channels[1] + 0.0722 * channels[2]
    }
}
