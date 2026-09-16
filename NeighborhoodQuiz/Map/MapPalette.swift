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
        label: Color(hex: 0xE2D6BE),
        labelHalo: Color(hex: 0x2B2A26),
        grain: Color(hex: 0xEFE6D2)
    )

    static func of(_ scheme: ColorScheme) -> MapPalette {
        scheme == .dark ? .night : .day
    }

    func colour(for kind: RoadKind) -> Color {
        switch kind {
        case .avenue, .namedStreet: return avenue
        case .majorCrossStreet: return inkSoft
        case .crossStreet: return street
        }
    }

    /// How heavy the pen is for each kind of road, in points, before zoom. The hairline
    /// the ordinary cross streets get is deliberate: two hundred of them are what give
    /// the island its texture, and any heavier they would fill it in.
    func weight(for kind: RoadKind) -> Double {
        switch kind {
        case .avenue: return 1.6
        case .namedStreet: return 1.6
        case .majorCrossStreet: return 1.15
        case .crossStreet: return 0.55
        }
    }

    /// The size a street name is written at, in points on screen. Names do not grow
    /// with the map — pulling in shows *more* of them rather than bigger ones.
    func labelSize(for kind: RoadKind) -> Double {
        switch kind {
        case .avenue: return 13
        case .namedStreet: return 12
        case .majorCrossStreet: return 11
        case .crossStreet: return 9
        }
    }
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
