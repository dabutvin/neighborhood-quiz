import XCTest
@testable import NeighborhoodQuiz

/// The words that go into the share sheet and the links that go into the store. The
/// sheets themselves are Apple's; this is everything of ours that goes in them.
final class AppStoreTests: XCTestCase {
    private let listing = URL(string: "https://apps.apple.com/app/id123456789")!

    // MARK: - The score line

    func testTheScoreLineSaysTheScoreAndWhereItWasScored() {
        let text = AppStore.shareText(score: 38, of: 50, borough: "Brooklyn", url: nil)

        XCTAssertTrue(text.contains(Money.text(38)), text)
        XCTAssertTrue(text.contains(Money.text(50)), text)
        XCTAssertTrue(text.contains("Brooklyn"), text)
        XCTAssertTrue(text.contains(AppStore.name), text)
        XCTAssertFalse(text.contains("\n"), "one line while there is no link to add")
        XCTAssertFalse(text.contains("http"), text)
    }

    /// The other thing the round can be: not one borough but all of them, and the line
    /// has to read either way.
    func testTheScoreLineReadsAcrossTheCityToo() {
        let text = AppStore.shareText(score: 41, of: 50, borough: "across the city", url: nil)
        XCTAssertTrue(text.contains("across the city"), text)
        XCTAssertFalse(text.contains("in across"), "not glued to a preposition")
    }

    /// On a line of its own, and last, which is what the messaging apps look for when
    /// they turn a link into a card.
    func testTheLinkGoesOnItsOwnLastLine() {
        let text = AppStore.shareText(score: 38, of: 50, borough: "Manhattan", url: listing)
        XCTAssertTrue(text.hasSuffix("\n" + listing.absoluteString), text)
        XCTAssertEqual(text.components(separatedBy: "\n").count, 2)
    }

    // MARK: - The plain invitation

    func testTheInvitationNamesTheAppWithAndWithoutALink() {
        let bare = AppStore.invitation(url: nil)
        XCTAssertTrue(bare.contains(AppStore.name), bare)
        XCTAssertFalse(bare.contains("\n"), bare)

        let linked = AppStore.invitation(url: listing)
        XCTAssertTrue(linked.hasPrefix(bare), "the same words, then the link")
        XCTAssertTrue(linked.hasSuffix("\n" + listing.absoluteString), linked)
    }

    // MARK: - The links

    func testTheStoreLinksAreBuiltFromTheId() {
        XCTAssertEqual(
            AppStore.storeURL(id: "123456789")?.absoluteString,
            "https://apps.apple.com/app/id123456789"
        )
        XCTAssertEqual(
            AppStore.storeURL(id: "123456789", review: true)?.absoluteString,
            "https://apps.apple.com/app/id123456789?action=write-review"
        )
    }

    /// Written to stay true on both sides of the id being filled in. While it is blank
    /// there must be no link anywhere — a share message with a dead link in it would be
    /// worse than one with none — and once it is there, both links must follow from it.
    func testThereAreNoLinksUntilThereIsAnAppRecordAndBothOnceThereIs() {
        if let id = AppStore.id {
            XCTAssertEqual(AppStore.url, AppStore.storeURL(id: id))
            XCTAssertEqual(AppStore.reviewURL, AppStore.storeURL(id: id, review: true))
            XCTAssertTrue(AppStore.shareText.contains("apps.apple.com"))
        } else {
            XCTAssertNil(AppStore.url)
            XCTAssertNil(AppStore.reviewURL)
            XCTAssertFalse(AppStore.shareText.contains("http"))
            let line = AppStore.shareText(score: 1, of: 50, borough: "Manhattan")
            XCTAssertFalse(line.contains("http"))
        }
    }

    /// The title in the app is the listing's, in full. `CFBundleDisplayName` is the
    /// short one and is not this string — see `project.yml` for why.
    func testTheNameIsTheListingsName() {
        XCTAssertEqual(AppStore.name, "NYC Neighborhoods: Map Quiz")
    }
}
