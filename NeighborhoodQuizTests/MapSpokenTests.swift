import SwiftUI
import XCTest
@testable import NeighborhoodQuiz

/// What the map says to somebody who is not looking at it.
///
/// The drawing is one accessibility element rather than nine hundred street names, so
/// this sentence is the whole of what a VoiceOver player gets from the map. It has two
/// jobs and they pull against each other: say enough that the map is worth having, and
/// not one word more than the map itself shows — because a sentence that named the
/// place you had just tapped would let the quiz be played by listening.
@MainActor
final class MapSpokenTests: XCTestCase {
    func testAMapWithNothingOnItJustSaysWhatItIs() {
        XCTAssertEqual(
            ManhattanMapView.spoken(showing: nil, picked: false, found: 0, missed: 0),
            "Map of Manhattan"
        )
    }

    /// A found neighbourhood is written on the map, so it is said out loud too.
    func testAFoundPlaceIsNamed() {
        XCTAssertEqual(
            ManhattanMapView.spoken(showing: "Harlem", picked: false, found: 3, missed: 0),
            "Map of Manhattan, showing Harlem. 3 found"
        )
    }

    /// The load-bearing one. A picked neighbourhood is deliberately left unnamed on the
    /// map — naming it would hand over the game — and it has to be unnamed here for the
    /// same reason. Somebody tapping their way round the island must not be able to
    /// listen for the answer.
    func testAPickedPlaceIsNeverNamed() {
        let said = ManhattanMapView.spoken(showing: nil, picked: true, found: 0, missed: 0)
        XCTAssertEqual(said, "Map of Manhattan, with a neighborhood picked but not named")
        XCTAssertFalse(said.contains("Harlem"))
    }

    /// Answering settles the place, and a settled place is a shown place — so the name
    /// arrives with the answer and not before it.
    func testAnsweringIsWhatNamesIt() {
        XCTAssertEqual(
            ManhattanMapView.spoken(showing: "Harlem", picked: true, found: 0, missed: 0),
            "Map of Manhattan, showing Harlem"
        )
    }

    func testTheTallyCountsBothWaysARoundGoes() {
        XCTAssertEqual(
            ManhattanMapView.spoken(showing: nil, picked: false, found: 7, missed: 2),
            "Map of Manhattan. 7 found, 2 given away"
        )
        XCTAssertEqual(
            ManhattanMapView.spoken(showing: nil, picked: true, found: 4, missed: 1),
            "Map of Manhattan, with a neighborhood picked but not named. 4 found, 1 given away"
        )
    }

    /// Nothing at zero. A round that has just started should not open with "0 found".
    func testAnEmptyTallyIsNotSaid() {
        for said in [
            ManhattanMapView.spoken(showing: nil, picked: false, found: 0, missed: 0),
            ManhattanMapView.spoken(showing: "SoHo", picked: false, found: 0, missed: 0),
        ] {
            XCTAssertFalse(said.contains("0"), said)
        }
    }
}
