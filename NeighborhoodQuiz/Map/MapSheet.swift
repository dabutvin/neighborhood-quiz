import Foundation

/// What one drawing covers: a single borough, or several of them laid out together.
///
/// A round of one borough is drawn the way it always was — that borough alone, fitted to
/// the screen and turned to its own grid. A round that runs over the whole city used to
/// be drawn the same way, one borough at a time, and the map jumped from Manhattan to
/// Queens between questions. Now it is one sheet with every open borough on it, laid out
/// as they actually sit, north-up, and getting from SoHo to Astoria is a matter of
/// pushing the map across the river.
///
/// North-up because there is no other honest choice for more than one borough: turning
/// the city by Manhattan's twenty-nine degrees would stand Manhattan's avenues up and lay
/// every other grid in the city on a slant, which is the reason the other four are
/// drawn north-up on their own too.
enum MapSheet: Hashable, Sendable {
    case borough(Borough)
    case city(Set<Borough>)

    /// Every borough on the sheet, in the city's own order.
    var boroughs: [Borough] {
        switch self {
        case .borough(let borough): return [borough]
        case .city(let open): return Borough.allCases.filter(open.contains)
        }
    }

    /// What the sheet is called, where the map says so out loud.
    var name: String {
        switch self {
        case .borough(let borough): return borough.name
        case .city: return "New York City"
        }
    }

    /// How far the drawing is turned, in degrees clockwise.
    var rotation: Double {
        switch self {
        case .borough(let borough): return -borough.gridBearingDegrees
        case .city: return 0
        }
    }

    /// How far apart one borough's neighbourhood numbers sit from the next's on a city
    /// sheet. The biggest borough has seventy-odd; a thousand is room to spare and
    /// leaves the number readable in a debugger — 1_012 is Brooklyn's twelfth.
    static let stride = 1_000

    /// The number a place is drawn under on this sheet, or nothing if it is not on it.
    ///
    /// On one borough's sheet it is the place's own index, exactly as it always was. On
    /// a city sheet the borough is folded in, because Manhattan's twelfth and Brooklyn's
    /// twelfth are both on the page and a tap has to be able to tell them apart.
    func id(of place: Place) -> Int? {
        switch self {
        case .borough(let borough):
            return place.borough == borough ? place.id : nil
        case .city(let open):
            guard open.contains(place.borough),
                  let slot = Borough.allCases.firstIndex(of: place.borough)
            else { return nil }
            return slot * MapSheet.stride + place.id
        }
    }

    /// The place a number on this sheet stands for — the other half of `id(of:)`.
    func place(for id: Int) -> Place? {
        guard id >= 0 else { return nil }
        switch self {
        case .borough(let borough):
            return Place(borough, id)
        case .city(let open):
            let slot = id / MapSheet.stride
            guard Borough.allCases.indices.contains(slot) else { return nil }
            let borough = Borough.allCases[slot]
            guard open.contains(borough) else { return nil }
            return Place(borough, id % MapSheet.stride)
        }
    }
}
