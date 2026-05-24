import Foundation

@MainActor
final class FeedViewModel: ObservableObject {
    enum DisplayMode: String, Codable, Hashable, CaseIterable, Identifiable {
        case all
        case unread

        var id: String { rawValue }
    }

    @Published var posts: [UnreadPost] = []
    @Published var viewedPostID: UnreadPostIdentity?
    @Published var isLoading = false
    @Published var errorMessage: String?

    private let intelligenceService: NewsIntelligenceService

    init(
        displayMode: DisplayMode? = nil,
        intelligenceService: NewsIntelligenceService = NewsIntelligenceService()
    ) {
        self.intelligenceService = intelligenceService
    }

    func setPosts(_ posts: [UnreadPost]) {
        self.posts = sortedPosts(posts)
        intelligenceService.prepareIndex(for: self.posts)
    }

    func prepend(_ post: UnreadPost) {
        guard posts.contains(where: { $0.id == post.id }) == false else {
            return
        }
        posts = sortedPosts(posts + [post])
        posts = Array(posts.suffix(20))
        intelligenceService.prepareIndex(for: posts)
    }

    var visiblePosts: [UnreadPost] {
        posts
    }

    func filteredPosts(matching filter: AppliedNewsFilterState) -> [UnreadPost] {
        intelligenceService.rankedPosts(posts, matching: filter)
    }

    var newerThanViewedCount: Int {
        guard let viewedPostID,
              let viewedIndex = posts.firstIndex(where: { $0.id == viewedPostID })
        else {
            return posts.isEmpty ? 0 : posts.count
        }
        return viewedIndex
    }

    func reset() {
        posts = []
        viewedPostID = nil
        errorMessage = nil
        isLoading = false
    }

    private func sortedPosts(_ posts: [UnreadPost]) -> [UnreadPost] {
        posts.sorted { lhs, rhs in
            if lhs.date == rhs.date {
                if lhs.id.sourceKind == rhs.id.sourceKind, lhs.id.sourceIdentifier == rhs.id.sourceIdentifier {
                    return lhs.messageID > rhs.messageID
                }
                if lhs.id.sourceKind != rhs.id.sourceKind {
                    return lhs.id.sourceKind.rawValue > rhs.id.sourceKind.rawValue
                }
                return lhs.id.sourceIdentifier > rhs.id.sourceIdentifier
            }
            return lhs.date > rhs.date
        }
    }
}
