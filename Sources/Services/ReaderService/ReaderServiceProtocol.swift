import Foundation

protocol ReaderServiceProtocol: Sendable {
    func loadArticle(from url: URL, fallbackTitle: String) async throws -> ReaderArticle
}
