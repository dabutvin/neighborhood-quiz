import Foundation

/// The Commissioners' grid of 1811, as arithmetic.
///
/// Above Houston Street the island is a ruled sheet: numbered streets every twentieth
/// of a mile, avenues at fixed distances either side of Fifth, and the whole thing
/// turned about twenty-nine degrees east of north. That is enough to place any corner
/// in Midtown or above without a line of survey data in the repository — and it places
/// them well: Times Square, Columbus Circle and the north-east corner of Central Park
/// all come out within a block of where they are, which `ManhattanGridTests` pins down.
///
/// Below Fourteenth Street the grid stops being true and the streets have names, so
/// those are traced by hand in `ManhattanMapData` instead.
enum ManhattanGrid {
    /// How far east of north the avenues run.
    static let bearingDegrees = 29.0

    /// Fifth Avenue at Forty-Second Street, on the library's front steps. Everything
    /// else on the grid is measured from here.
    static let anchor = Coordinate(-73.98145, 40.75368)
    static let anchorStreet = 42.0

    /// Twenty blocks to the mile, which is what the numbered streets were laid out at.
    static let feetPerBlock = 5280.0 / 20

    static let metresPerFoot = 0.3048

    /// The corner of a numbered street and a line `feet` west of Fifth Avenue.
    ///
    /// `street` and `feet` are both allowed to be fractional and to run past the ends
    /// of the real grid: a caller draws a generous line and lets the shoreline clip it.
    static func coordinate(street: Double, westOfFifth feet: Double) -> Coordinate {
        let bearing = bearingDegrees * .pi / 180
        let along = (street - anchorStreet) * feetPerBlock

        // North and east components of walking `along` feet up an avenue and `feet`
        // west along a cross street. The cross street runs ninety degrees off the
        // avenue, which is where the swapped sine and cosine come from.
        let northFeet = along * cos(bearing) + feet * sin(bearing)
        let eastFeet = along * sin(bearing) - feet * cos(bearing)

        let northMetres = northFeet * metresPerFoot
        let eastMetres = eastFeet * metresPerFoot

        // A local tangent plane on the anchor's latitude. Over thirteen miles of island
        // the error in the longitude scale is about a fifth of a percent — a few tens of
        // metres at the far end of a map drawn with a wobbling pen.
        let metresPerDegreeLongitude =
            MapProjection.metresPerDegreeLatitude * cos(anchor.latitude * .pi / 180)

        return Coordinate(
            anchor.longitude + eastMetres / metresPerDegreeLongitude,
            anchor.latitude + northMetres / MapProjection.metresPerDegreeLatitude
        )
    }
}
