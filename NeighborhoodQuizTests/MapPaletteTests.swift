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

    // MARK: - How big a street name is

    /// Pulled back, nothing changes: the widest views are where names are most crowded,
    /// and the sizes there were tuned to fit.
    func testStreetNamesKeepTheirSizeUntilTheMapIsPulledIn() {
        let palette = MapPalette.day
        for kind in RoadKind.allCases {
            for zoom in [1.0, 2.0, MapPalette.growFrom] {
                XCTAssertEqual(palette.labelSize(for: kind, at: zoom), palette.labelSize(for: kind))
            }
        }
    }

    /// All the way in, every name is at its close-in size — and a side street's is big
    /// enough to read, which it was not at nine points.
    func testAllTheWayInEveryNameIsAtItsCloseSize() {
        let palette = MapPalette.day
        let full = MapCamera.range.upperBound
        for kind in RoadKind.allCases {
            XCTAssertEqual(palette.labelSize(for: kind, at: full), palette.closeLabelSize(for: kind))
            XCTAssertGreaterThan(palette.closeLabelSize(for: kind), palette.labelSize(for: kind) * 1.3)
        }
        XCTAssertGreaterThanOrEqual(palette.closeLabelSize(for: .side), 14)
    }

    /// Pinching in never shrinks a name, and never puts a side street above an avenue.
    func testNamesOnlyGrowAndKeepTheirOrder() {
        let palette = MapPalette.day
        var last: [RoadKind: Double] = [:]
        for step in 0...52 {
            let zoom = 1 + Double(step) * 0.25
            let avenue = palette.labelSize(for: .avenue, at: zoom)
            let major = palette.labelSize(for: .major, at: zoom)
            let side = palette.labelSize(for: .side, at: zoom)
            XCTAssertGreaterThanOrEqual(avenue, major, "at \(zoom)")
            XCTAssertGreaterThanOrEqual(major, side, "at \(zoom)")
            for kind in RoadKind.allCases {
                let size = palette.labelSize(for: kind, at: zoom)
                XCTAssertGreaterThanOrEqual(size, last[kind] ?? 0, "\(kind) shrank at \(zoom)")
                XCTAssertEqual(size * 2, (size * 2).rounded(), "sizes come in half points")
                last[kind] = size
            }
        }
    }

    /// A picked-out neighbourhood's name is still the loudest thing on the map, however
    /// far in the street names have grown.
    func testANeighborhoodsNameStillOutranksTheLargestStreetName() {
        for palette in [MapPalette.day, MapPalette.night] {
            for kind in RoadKind.allCases {
                XCTAssertGreaterThan(palette.neighborhoodLabelSize, palette.closeLabelSize(for: kind) * 1.3)
            }
        }
    }
}
