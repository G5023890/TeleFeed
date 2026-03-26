import Foundation

@MainActor
final class RSSFeedsViewModel: ObservableObject {
    @Published var feeds: [RSSFeedSource]
    @Published var selectedFeedID: String?
    @Published var feedInput = ""
    @Published var errorMessage: String?

    init(feeds: [RSSFeedSource], selectedFeedID: String? = nil) {
        self.feeds = feeds.sorted { $0.title.localizedCaseInsensitiveCompare($1.title) == .orderedAscending }
        self.selectedFeedID = selectedFeedID ?? self.feeds.first?.id
    }

    func feed(for id: String?) -> RSSFeedSource? {
        guard let id else {
            return nil
        }
        return feeds.first(where: { $0.id == id })
    }

    func contains(urlString: String) -> Bool {
        let normalized = urlString.trimmingCharacters(in: .whitespacesAndNewlines)
        return feeds.contains(where: { $0.normalizedURLString == normalized })
    }

    func add(_ feed: RSSFeedSource) throws {
        guard contains(urlString: feed.urlString) == false else {
            throw RSSServiceError.duplicateFeed
        }
        feeds.append(feed)
        feeds.sort { $0.title.localizedCaseInsensitiveCompare($1.title) == .orderedAscending }
        selectedFeedID = feed.id
    }

    func update(_ feed: RSSFeedSource) {
        guard let index = feeds.firstIndex(where: { $0.id == feed.id }) else {
            return
        }
        feeds[index] = feed
        feeds.sort { $0.title.localizedCaseInsensitiveCompare($1.title) == .orderedAscending }
    }

    func removeSelectedFeed() -> RSSFeedSource? {
        guard let selectedFeedID else {
            return nil
        }

        guard let index = feeds.firstIndex(where: { $0.id == selectedFeedID }) else {
            self.selectedFeedID = feeds.first?.id
            return nil
        }

        let removed = feeds.remove(at: index)
        self.selectedFeedID = feeds.first?.id
        return removed
    }
}
