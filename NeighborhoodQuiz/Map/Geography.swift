import CoreGraphics
import Foundation

/// A point on the globe, written the way GeoJSON writes one: longitude first.
struct Coordinate: Equatable, Hashable {
    var longitude: Double
    var latitude: Double

    init(_ longitude: Double, _ latitude: Double) {
        self.longitude = longitude
        self.latitude = latitude
    }
}

/// A spherical Mercator fitted to a set of coordinates and then turned on the page.
///
/// The turn is what makes the drawing read as a drawing rather than as a satellite
/// photograph. Manhattan's grid runs about twenty-nine degrees east of north, so
/// rotating the projected plane back by that much stands the avenues upright and
/// lays the cross streets flat — which is how every hand-drawn map of the island
/// has ever been drawn, and nothing like how the island actually sits.
struct MapProjection: Equatable {
    /// Metres per degree of latitude, near enough anywhere that matters here.
    static let metresPerDegreeLatitude = 111_320.0

    private let scale: Double
    private let originX: Double
    private let originY: Double
    private let cosAngle: Double
    private let sinAngle: Double

    /// Fit `coordinates` inside `size`, leaving `padding` points clear on every edge,
    /// with the projected plane rotated `rotation` degrees clockwise.
    init(fitting coordinates: [Coordinate], in size: CGSize, padding: Double, rotation: Double) {
        let radians = rotation * .pi / 180
        cosAngle = cos(radians)
        sinAngle = sin(radians)

        let turned = coordinates.map { coordinate -> (Double, Double) in
            let raw = MapProjection.mercator(coordinate)
            return (
                raw.x * cosAngle - raw.y * sinAngle,
                raw.x * sinAngle + raw.y * cosAngle
            )
        }

        let minX = turned.map(\.0).min() ?? 0
        let maxX = turned.map(\.0).max() ?? 1
        let minY = turned.map(\.1).min() ?? 0
        let maxY = turned.map(\.1).max() ?? 1

        let usableWidth = max(Double(size.width) - 2 * padding, 1)
        let usableHeight = max(Double(size.height) - 2 * padding, 1)
        let spanX = max(maxX - minX, .leastNormalMagnitude)
        let spanY = max(maxY - minY, .leastNormalMagnitude)
        scale = min(usableWidth / spanX, usableHeight / spanY)

        // Centre whatever slack the tighter dimension left over.
        originX = (Double(size.width) - spanX * scale) / 2 - minX * scale
        originY = (Double(size.height) - spanY * scale) / 2 - minY * scale
    }

    func point(_ coordinate: Coordinate) -> CGPoint {
        let raw = MapProjection.mercator(coordinate)
        let x = raw.x * cosAngle - raw.y * sinAngle
        let y = raw.x * sinAngle + raw.y * cosAngle
        return CGPoint(x: x * scale + originX, y: y * scale + originY)
    }

    func points(_ coordinates: [Coordinate]) -> [CGPoint] {
        coordinates.map(point)
    }

    /// Longitude east, and a Mercator latitude that grows *downward*, so the result
    /// is already in the direction screen coordinates run.
    private static func mercator(_ coordinate: Coordinate) -> (x: Double, y: Double) {
        let latitude = min(max(coordinate.latitude, -85), 85) * .pi / 180
        return (
            x: coordinate.longitude * .pi / 180,
            y: -log(tan(.pi / 4 + latitude / 2))
        )
    }
}
