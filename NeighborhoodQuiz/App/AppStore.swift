import Foundation

/// Where the app lives on the App Store, and what it says about itself when it is passed
/// on or asked to be rated.
///
/// Pure functions, on purpose. The share sheet and the review prompt are Apple's and
/// cannot be tested; the text that goes into them can be, and so can the two links —
/// which is worth doing, because a link with a typo in it is the kind of thing that
/// ships and is found by a stranger.
enum AppStore {
    /// The listing's name, in full. The home screen shows the shorter
    /// `CFBundleDisplayName` because it truncates; nothing else does.
    static let name = "NYC Neighborhoods: Map Quiz"

    /// The numeric id App Store Connect gives the app — the digits after `id` in its
    /// store link. Nothing until the app record exists, and to be filled in once it
    /// does: until then there is no page to link to, so the share text goes out without
    /// a link and the rating row falls back to the in-app sheet.
    static let id: String? = nil

    /// The listing, or nothing while there is no id to point at.
    static var url: URL? {
        id.flatMap { storeURL(id: $0) }
    }

    /// The listing, opened straight onto the review form.
    static var reviewURL: URL? {
        id.flatMap { storeURL(id: $0, review: true) }
    }

    /// The store link for an id. Split out so the shape of the link can be checked
    /// against a made-up id while the real one is still blank.
    static func storeURL(id: String, review: Bool = false) -> URL? {
        URL(string: "https://apps.apple.com/app/id\(id)" + (review ? "?action=write-review" : ""))
    }

    /// The line the end of a round shares: the score, and where it was scored.
    ///
    /// `borough` is where the round was played, and it reads as one of two things — a
    /// borough's name, or "across the city" for a round that ran over all of them —
    /// which is why the place comes after a dash rather than after "in".
    static func shareText(
        score: Int,
        of perfect: Int,
        borough: String,
        url: URL? = AppStore.url
    ) -> String {
        let line = "\(Money.text(score)) of \(Money.text(perfect)) on \(name) — \(borough)."
        return withLink(line, url: url)
    }

    /// The plain "try this app" message, from the settings screen.
    static var shareText: String { invitation(url: url) }

    /// The same, with the link passed in, so the wording can be checked with and
    /// without one while `id` is still blank. Its own name rather than a third
    /// `shareText`, so that `AppStore.shareText` on its own can only ever mean the
    /// property.
    static func invitation(url: URL?) -> String {
        withLink("\(name): find the neighborhoods of New York on a map drawn by hand.", url: url)
    }

    /// The link on a line of its own, so the message apps that turn links into cards
    /// find it — and no line at all while there is no link to put there.
    private static func withLink(_ text: String, url: URL?) -> String {
        guard let url else { return text }
        return text + "\n" + url.absoluteString
    }
}
