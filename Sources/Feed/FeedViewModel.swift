import Foundation

@MainActor
final class FeedViewModel: ObservableObject {
    enum DisplayMode: String, Codable, Hashable, CaseIterable, Identifiable {
        case all
        case unread

        var id: String { rawValue }
    }

    @Published var posts: [UnreadPost] = []
    @Published var readPostIDs: Set<UnreadPostIdentity> = []
    @Published var displayMode: DisplayMode
    @Published var isLoading = false
    @Published var errorMessage: String?

    init(displayMode: DisplayMode = .all) {
        self.displayMode = displayMode
    }

    func setPosts(_ posts: [UnreadPost]) {
        self.posts = sortedPosts(posts)
    }

    func prepend(_ post: UnreadPost) {
        guard posts.contains(where: { $0.id == post.id }) == false else {
            return
        }
        posts = sortedPosts(posts + [post])
        posts = Array(posts.suffix(20))
    }

    func markRead(identity: UnreadPostIdentity) {
        readPostIDs.insert(identity)
    }

    func markUnread(identity: UnreadPostIdentity) {
        readPostIDs.remove(identity)
    }

    func isUnread(_ post: UnreadPost) -> Bool {
        readPostIDs.contains(post.id) == false
    }

    var visiblePosts: [UnreadPost] {
        switch displayMode {
        case .all:
            return posts
        case .unread:
            return posts.filter { isUnread($0) }
        }
    }

    var unreadCount: Int {
        posts.reduce(0) { partialResult, post in
            partialResult + (isUnread(post) ? 1 : 0)
        }
    }

    func reset() {
        posts = []
        readPostIDs = []
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
