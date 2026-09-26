import CoreGraphics
import XCTest
@testable import NeighborhoodQuiz

/// Where the borough pills break onto a new line. Pills are never squeezed, so which
/// line each one goes on is the whole of the layout's decision.
@MainActor
final class FlowRowTests: XCTestCase {
    func testPillsThatFitStayOnOneLine() {
        XCTAssertEqual(FlowRow.lines(for: [80, 80, 80], in: 300, spacing: 8), [[0, 1, 2]])
    }

    /// Three pills a hair too wide for the card: the third goes to a line of its own
    /// rather than all three being squeezed — the "Manhatta / n" bug.
    func testThePillThatDoesNotFitStartsTheNextLine() {
        XCTAssertEqual(FlowRow.lines(for: [99, 85, 90], in: 266, spacing: 8), [[0, 1], [2]])
    }

    /// The whole city: five boroughs and Anywhere, on a card a phone's width across.
    func testTheWholeCityWrapsOntoAsManyLinesAsItNeeds() {
        let widths: [CGFloat] = [99, 85, 75, 90, 110, 90]
        let lines = FlowRow.lines(for: widths, in: 266, spacing: 8)

        XCTAssertEqual(lines.flatMap { $0 }, Array(widths.indices), "every pill, once, in order")
        for line in lines {
            let used = line.map { widths[$0] }.reduce(0, +) + 8 * CGFloat(line.count - 1)
            XCTAssertLessThanOrEqual(used, 266, "line \(line) overruns the card")
        }
    }

    /// A pill wider than the whole row is still shown, on a line of its own.
    func testAPillWiderThanTheRowGetsALineToItself() {
        XCTAssertEqual(FlowRow.lines(for: [50, 400, 50], in: 266, spacing: 8), [[0], [1], [2]])
    }

    func testNothingToLayOutIsNoLines() {
        XCTAssertEqual(FlowRow.lines(for: [], in: 266, spacing: 8), [])
    }
}
