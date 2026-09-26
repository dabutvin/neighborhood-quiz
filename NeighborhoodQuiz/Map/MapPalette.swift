import SwiftUI

extension Color {
    /// A colour written the way CSS writes one, so the palette below can be read
    /// against the Park Slope map's stylesheet line for line.
    init(hex: UInt32) {
        self.init(
            .sRGB,
            red: Double((hex >> 16) & 0xFF) / 255,
            green: Double((hex >> 8) & 0xFF) / 255,
            blue: Double(hex & 0xFF) / 255,
            opacity: 1
        )
    }
}

/// Warm paper, soft ink, sage green: the palette the Park Slope map is drawn in,
/// brought over whole, with a night version added underneath it.
///
/// Manhattan is an island, so the two are used differently from the way the Park Slope
/// map uses them. There, paper is the background and the neighbourhood is a lighter
/// patch on it. Here the background is the water and the paper is the land, which is
/// what makes the shape read from across the room — and Brooklyn, drawn on the same
/// palette, reads the same way, because it too is land with water round three sides.
struct MapPalette {
    var water: Color
    var waterInk: Color
    var land: Color
    var ink: Color
    var inkSoft: Color
    var avenue: Color
    var street: Color
    var park: Color
    var parkInk: Color
    /// The line round every neighbourhood. It is a warm red-brown rather than the
    /// grey-brown the streets are in, on purpose: the first version of this took its
    /// colour from the same family as the roads and, dashes or no dashes, read as one
    /// more road at the widest zoom. A border has to say which layer it belongs to
    /// before it says anything else.
    var border: Color
    /// The wash a picked-out neighbourhood is filled with, and the firm line and
    /// lettering that go with it. Terracotta, because it is the one warm colour that
    /// neither the sage of the parks nor the brown of the streets is already using —
    /// a highlight has to be unmistakably *not* part of the drawing underneath it.
    var highlight: Color
    var highlightInk: Color
    /// A neighborhood guessed at and found to be somewhere else. Cool and flat rather
    /// than red: crossing a place off is a step towards the answer, not a telling-off,
    /// and forty of these on one screen in an angry colour would be a horrible thing to
    /// look at.
    ///
    /// This is the *wash*, and only the wash. Crossing a place off means dimming it, so
    /// by day it is a grey darker than the paper and by night one darker than the land.
    var ruledOut: Color
    /// What a crossed-off or given-away place is *lettered* in, which is not the same
    /// colour as the wash and cannot be. By day the two can be the same grey, because
    /// grey on cream paper reads either way. By night the wash is nearly black, and a
    /// name written in it over a dark island is a name nobody can read — which is the
    /// worst place to lose legibility, since being shown where Harlem was is the whole
    /// of what three failed goes buy you.
    var ruledOutInk: Color
    /// What a street name is written in, and the halo of paper that keeps it legible
    /// where it crosses its own street.
    var label: Color
    var labelHalo: Color
    var grain: Color

    static let day = MapPalette(
        water: Color(hex: 0xC9DCE4),
        waterInk: Color(hex: 0x5C869E),
        land: Color(hex: 0xEFE6D2),
        ink: Color(hex: 0x5B4A3A),
        inkSoft: Color(hex: 0x8A7256),
        avenue: Color(hex: 0x8A7256),
        street: Color(hex: 0xB7A78F),
        park: Color(hex: 0xBCD1A6),
        parkInk: Color(hex: 0x7D976A),
        border: Color(hex: 0xB0765A),
        highlight: Color(hex: 0xD98A5E),
        highlightInk: Color(hex: 0x9A472A),
        ruledOut: Color(hex: 0x6E7076),
        ruledOutInk: Color(hex: 0x6E7076),
        label: Color(hex: 0x5B4A3A),
        labelHalo: Color(hex: 0xF7F0DF),
        grain: Color(hex: 0x5B4A3A)
    )

    /// The same drawing after dark: the paper keeps its warmth and loses its light, the
    /// water goes to deep slate, and the ink turns over into the pale thing on the page.
    static let night = MapPalette(
        water: Color(hex: 0x161C24),
        waterInk: Color(hex: 0x3C5468),
        land: Color(hex: 0x2B2A26),
        ink: Color(hex: 0xE2D6BE),
        inkSoft: Color(hex: 0xA3927A),
        avenue: Color(hex: 0xC2AE91),
        street: Color(hex: 0x7C7160),
        park: Color(hex: 0x36452F),
        parkInk: Color(hex: 0x6C8A5C),
        border: Color(hex: 0xA5705A),
        highlight: Color(hex: 0xD4794C),
        highlightInk: Color(hex: 0xF0A87E),
        ruledOut: Color(hex: 0x14161A),
        ruledOutInk: Color(hex: 0x9AA2AD),
        label: Color(hex: 0xE2D6BE),
        labelHalo: Color(hex: 0x2B2A26),
        grain: Color(hex: 0xEFE6D2)
    )

    static func of(_ scheme: ColorScheme) -> MapPalette {
        scheme == .dark ? .night : .day
    }

    func colour(for kind: RoadKind) -> Color {
        switch kind {
        case .avenue: return avenue
        case .major: return inkSoft
        case .side: return street
        }
    }

    /// How heavy the pen is for each rank of road, in points, before zoom. The hairline
    /// the side streets get is deliberate: there are eleven hundred runs of them and
    /// they are what gives the island its texture. Any heavier and they fill it in,
    /// which is exactly what the first draft of this map did.
    func weight(for kind: RoadKind) -> Double {
        switch kind {
        case .avenue: return 1.6
        case .major: return 1.0
        case .side: return 0.5
        }
    }

    /// The size a street name is written at, in points on screen, with the map pulled
    /// back. Pulling in shows *more* names rather than bigger ones — up to a point.
    func labelSize(for kind: RoadKind) -> Double {
        switch kind {
        case .avenue: return 12
        case .major: return 10.5
        case .side: return 9
        }
    }

    /// The size a street name reaches with the map pulled all the way in.
    ///
    /// Nine points of hand lettering is right for a borough's worth of streets, where a
    /// name has one block's breadth to fit into. Fourteen times in, a block is most of
    /// the screen and a nine-point name is a smudge in the middle of it that nobody can
    /// read. So the names grow as the blocks do, and the side streets most, since they
    /// started smallest: the order between the three ranks holds, but the gap between
    /// them closes, because close in every street is one you might be looking for.
    func closeLabelSize(for kind: RoadKind) -> Double {
        switch kind {
        case .avenue: return 16.5
        case .major: return 15
        case .side: return 14
        }
    }

    /// The size a street name is written at for a given zoom.
    ///
    /// Unchanged until the map is pulled in past `MapPalette.growFrom` — where the
    /// cross streets first get room for their names and the grid is at its most crowded
    /// — then growing towards `closeLabelSize` on a log scale, which is how a pinch
    /// feels: each doubling of the zoom does about as much as the one before. Rounded to
    /// the half point, so a pinch asks for a dozen sizes of the face rather than one
    /// per frame.
    func labelSize(for kind: RoadKind, at zoom: Double) -> Double {
        let far = labelSize(for: kind)
        let close = closeLabelSize(for: kind)
        let size = far + (close - far) * MapPalette.closeness(at: zoom)
        return (size * 2).rounded() / 2
    }

    /// The zoom at which street names start to grow.
    static let growFrom = 4.0

    /// How far between "names at their usual size" and "names at their close-in size"
    /// a zoom is, from 0 to 1.
    static func closeness(at zoom: Double) -> Double {
        let full = MapCamera.range.upperBound
        guard zoom > growFrom else { return 0 }
        return min(log(zoom / growFrom) / log(full / growFrom), 1)
    }

    /// The size a picked-out neighbourhood's name is written at. Nearly twice the
    /// largest street name, and claiming its paper first, because while it is showing
    /// it is the thing the map is saying. Seventeen points of Bradley Hand over a grid
    /// of cross streets was a name you had to go looking for.
    var neighborhoodLabelSize: Double { 23 }

    /// A name that has settled, written smaller than the one just found. Big enough to
    /// read at a glance, small enough that ten of them do not shout over the question.
    var settledLabelSize: Double { 15 }

    /// How far the paper showing through a name reaches, in points on screen. A street
    /// name crosses one street and needs very little; a neighbourhood's name lies
    /// across a whole grid of them and needs a proper clearing.
    var labelHaloReach: Double { 1.4 }
    var neighborhoodHaloReach: Double { 2.6 }
}

/// The hand the map is written in.
///
/// Bradley Hand is the nearest thing iOS ships to the Caveat the Park Slope map is
/// lettered in, and iOS has shipped it since there was an iOS. It comes in one weight
/// only — bold — which is what a small map label wants anyway. Nothing is bundled and
/// nothing is fetched; if a future iOS ever drops the face, `Font.custom` falls back to
/// the system one on its own and the map is merely less charming.
enum MapFont {
    static let name = "BradleyHandITCTT-Bold"

    /// A street name. Fixed size on purpose: the map answers Dynamic Type by being
    /// pinched, and a label that grew with the body text would crowd the drawing off
    /// the page at the sizes where the drawing is the whole point.
    static func label(size: Double) -> Font {
        .custom(name, fixedSize: size)
    }

    /// Chrome — the title in the corner and the zoom buttons — which does follow
    /// Dynamic Type, because it is type rather than drawing.
    static func chrome(size: Double) -> Font {
        .custom(name, size: size)
    }
}
