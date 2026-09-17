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
/// Manhattan is an island, so the two are used differently from the way the Brooklyn
/// map uses them. There, paper is the background and the neighbourhood is a lighter
/// patch on it. Here the background is the water and the paper is the land, which is
/// what makes the shape read from across the room.
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
    var ruledOut: Color
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

    /// The size a street name is written at, in points on screen. Names do not grow
    /// with the map — pulling in shows *more* of them rather than bigger ones.
    func labelSize(for kind: RoadKind) -> Double {
        switch kind {
        case .avenue: return 12
        case .major: return 10.5
        case .side: return 9
        }
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
