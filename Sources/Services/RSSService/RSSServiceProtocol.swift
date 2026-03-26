import Foundation

enum RSSServiceError: LocalizedError {
    case invalidURL
    case invalidFeed
    case duplicateFeed

    var errorDescription: String? {
        switch self {
        case .invalidURL:
            return "Invalid RSS feed URL."
        case .invalidFeed:
            return "Unable to parse RSS feed."
        case .duplicateFeed:
            return "This RSS feed is already added."
        }
    }
}

struct RSSFeedRefreshResult {
    let source: RSSFeedSource
    let posts: [UnreadPost]
}

protocol RSSServiceProtocol: AnyObject, Sendable {
    func resolveFeed(from input: String) async throws -> RSSFeedSource
    func refreshFeed(_ source: RSSFeedSource, limit: Int) async throws -> RSSFeedRefreshResult
}
