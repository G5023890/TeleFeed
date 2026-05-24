import Foundation

struct RSSFeedSource: Codable, Hashable, Identifiable {
    var urlString: String
    var title: String
    var lastItemIdentifier: String?

    var id: String { urlString }

    var normalizedURLString: String {
        let trimmed = urlString.trimmingCharacters(in: .whitespacesAndNewlines)
        guard
            var components = URLComponents(string: trimmed),
            components.path.count > 1,
            components.path.hasSuffix("/"),
            components.query == nil,
            components.fragment == nil
        else {
            return trimmed
        }

        components.path = String(components.path.dropLast())
        return components.url?.absoluteString ?? trimmed
    }

    var syncKey: String {
        normalizedURLString.lowercased()
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
