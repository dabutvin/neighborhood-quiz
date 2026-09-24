import Foundation

/// A neighbourhood anywhere in the city: which borough's map it is on, and which shape
/// on that map it is.
///
/// The round used to hold plain ids, which was fine while a round was one borough — an
/// id was an index into the one map on the screen. A round that runs over the whole
/// city asks about SoHo and then about Park Slope, and the number twelve is a different
/// place on each map, so a question has to carry its borough with it.
///
/// `id` is the neighbourhood's `DrawnNeighborhood.id`, which is its index in
/// `BoroughMap.of(borough).neighborhoods`: `DrawnMap.build` numbers the shapes from the
/// data's own order, and `PlaceTests` holds it to that for every drawn borough. That
/// invariant is what lets a round's pool be drawn from the data before any map has been
/// built, and a name be read back without one either.
struct Place: Hashable, Sendable, Codable {
    let borough: Borough
    let id: Int

    init(_ borough: Borough, _ id: Int) {
        self.borough = borough
        self.id = id
    }

    /// Every place in a borough, in the order the file holds them.
    static func all(in borough: Borough) -> [Place] {
        BoroughMap.of(borough).neighborhoods.indices.map { Place(borough, $0) }
    }

    /// What it is called. Read from the data rather than from a drawing, because the
    /// card can be asked for a name before the map has got round to that borough.
    var name: String {
        BoroughMap.of(borough).neighborhoods[id].name
    }
}
