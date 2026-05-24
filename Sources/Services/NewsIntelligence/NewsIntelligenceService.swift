import Foundation
import NaturalLanguage

@MainActor
final class NewsIntelligenceService {
    private struct CacheKey: Hashable {
        let query: String
        let postID: UnreadPostIdentity
    }

    private enum Constants {
        static let semanticMatchThreshold = 0.47
        static let lexicalMatchScore = 1.0
        static let fallbackMatchThreshold = 0.28
    }

    private var sentenceEmbeddings: [NLLanguage: NLEmbedding] = [:]
    private var scoreCache: [CacheKey: Double] = [:]

    func rankedPosts(_ posts: [UnreadPost], matching filter: AppliedNewsFilterState) -> [UnreadPost] {
        let sourceFilteredPosts = posts.filter { post in
            switch filter.source {
            case .all:
                return true
            case .rss:
                return post.sourceKind == .rss
            case .telegram:
                return post.sourceKind == .telegram
            }
        }

        let query = normalized(filter.query)
        guard query.isEmpty == false else {
            return sourceFilteredPosts
        }

        let ranked = sourceFilteredPosts.compactMap { post -> (post: UnreadPost, score: Double)? in
            let score = matchScore(for: post, query: query)
            guard score >= Constants.semanticMatchThreshold else {
                return nil
            }
            return (post, score)
        }

        return ranked
            .sorted { lhs, rhs in
                if lhs.score == rhs.score {
                    return lhs.post.date > rhs.post.date
                }
                return lhs.score > rhs.score
            }
            .map(\.post)
    }

    func prepareIndex(for posts: [UnreadPost]) {
        let retainedIDs = Set(posts.map(\.id))
        scoreCache = scoreCache.filter { retainedIDs.contains($0.key.postID) }
    }

    private func matchScore(for post: UnreadPost, query: String) -> Double {
        let cacheKey = CacheKey(query: query, postID: post.id)
        if let cachedScore = scoreCache[cacheKey] {
            return cachedScore
        }

        let text = normalized(post.intelligenceSearchText)
        let score: Double
        if text.localizedCaseInsensitiveContains(query) {
            score = Constants.lexicalMatchScore
        } else if let semanticScore = semanticSimilarity(between: query, and: text) {
            score = max(semanticScore, fallbackSimilarity(between: query, and: text))
        } else {
            score = fallbackSimilarity(between: query, and: text)
        }

        scoreCache[cacheKey] = score
        return score
    }

    private func semanticSimilarity(between query: String, and text: String) -> Double? {
        let sample = [query, text].joined(separator: " ")
        let language = NLLanguageRecognizer.dominantLanguage(for: sample) ?? .english
        guard let embedding = sentenceEmbedding(for: language) else {
            return nil
        }

        let distance = embedding.distance(between: query, and: text, distanceType: .cosine)
        guard distance.isFinite else {
            return nil
        }

        return max(0, 1 - distance)
    }

    private func sentenceEmbedding(for language: NLLanguage) -> NLEmbedding? {
        if let cachedEmbedding = sentenceEmbeddings[language] {
            return cachedEmbedding
        }

        guard let embedding = NLEmbedding.sentenceEmbedding(for: language) else {
            return nil
        }
        sentenceEmbeddings[language] = embedding
        return embedding
    }

    private func fallbackSimilarity(between query: String, and text: String) -> Double {
        let queryTokens = tokenSet(from: query)
        guard queryTokens.isEmpty == false else {
            return 0
        }

        let textTokens = tokenSet(from: text)
        let overlap = queryTokens.intersection(textTokens)
        let overlapScore = Double(overlap.count) / Double(queryTokens.count)
        guard overlapScore < Constants.fallbackMatchThreshold else {
            return overlapScore
        }

        let fuzzyHits = queryTokens.filter { queryToken in
            textTokens.contains { textToken in
                textToken.hasPrefix(queryToken) || queryToken.hasPrefix(textToken)
            }
        }
        return Double(fuzzyHits.count) / Double(queryTokens.count)
    }

    private func tokenSet(from text: String) -> Set<String> {
        let tokens = text
            .lowercased()
            .components(separatedBy: CharacterSet.alphanumerics.inverted)
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { $0.count >= 2 }
        return Set(tokens)
    }

    private func normalized(_ text: String) -> String {
        text.trimmingCharacters(in: .whitespacesAndNewlines)
    }
}

private extension UnreadPost {
    var intelligenceSearchText: String {
        [
            channelTitle,
            author ?? "",
            titleOrFallback,
            summary,
            articleURL?.absoluteString ?? "",
        ].joined(separator: "\n")
    }
}
