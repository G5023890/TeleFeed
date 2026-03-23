import Foundation

@MainActor
final class FeedViewModel: ObservableObject {
    @Published var posts: [UnreadPost] = []
    @Published var readPostIDs: Set<UnreadPostIdentity> = []
    @Published var isLoading = false
    @Published var errorMessage: String?

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

    func reset() {
        posts = []
        readPostIDs = []
        errorMessage = nil
        isLoading = false
    }

    private func sortedPosts(_ posts: [UnreadPost]) -> [UnreadPost] {
        posts.sorted { lhs, rhs in
            if lhs.date == rhs.date {
                if lhs.chatID == rhs.chatID {
                    return lhs.messageID > rhs.messageID
                }
                return lhs.chatID > rhs.chatID
            }
            return lhs.date > rhs.date
        }
    }
}
