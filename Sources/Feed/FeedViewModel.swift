import Foundation

@MainActor
final class FeedViewModel: ObservableObject {
    @Published var unreadPosts: [UnreadPost] = []
    @Published var isLoading = false
    @Published var errorMessage: String?

    func setPosts(_ posts: [UnreadPost]) {
        unreadPosts = sortedPosts(posts)
    }

    func prepend(_ post: UnreadPost) {
        guard unreadPosts.contains(where: { $0.messageID == post.messageID }) == false else {
            return
        }
        unreadPosts = sortedPosts(unreadPosts + [post])
        unreadPosts = Array(unreadPosts.suffix(20))
    }

    func remove(messageID: Int64) {
        unreadPosts.removeAll { $0.messageID == messageID }
    }

    func reset() {
        unreadPosts = []
        errorMessage = nil
        isLoading = false
    }

    private func sortedPosts(_ posts: [UnreadPost]) -> [UnreadPost] {
        posts.sorted { lhs, rhs in
            if lhs.date == rhs.date {
                return lhs.messageID < rhs.messageID
            }
            return lhs.date < rhs.date
        }
    }
}
