import Foundation

struct RSSFeedSource: Codable, Hashable, Identifiable {
    var urlString: String
    var title: String
    var lastItemIdentifier: String?

    var id: String { urlString }

    var normalizedURLString: String {
        urlString.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    var feedURL: URL? {
        URL(string: normalizedURLString)
    }

    func resettingCursor() -> RSSFeedSource {
        RSSFeedSource(
            urlString: urlString,
            title: title,
            lastItemIdentifier: nil
        )
    }
}
