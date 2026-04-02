import Foundation
import OSLog

final class TranslationService: TranslationServiceProtocol, @unchecked Sendable {
    private static let logger = Logger(subsystem: "com.codex.TeleFeed", category: "TranslationService")
    private let session: URLSession
    private let targetLanguage = "ru"
    private let userAgent = "Mozilla/5.0 (Macintosh; Intel Mac OS X 15_0) AppleWebKit/605.1.15 (KHTML, like Gecko) TeleFeed/1.0 Safari/605.1.15"

    init(session: URLSession = .shared) {
        self.session = session
    }

    func translate(_ text: String) async throws -> String {
        guard text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false else {
            return text
        }

        guard let url = Self.makeURL(for: text, targetLanguage: targetLanguage) else {
            throw TranslationServiceError.invalidResponse
        }

        var request = URLRequest(url: url)
        request.setValue(userAgent, forHTTPHeaderField: "User-Agent")
        request.setValue("application/json, text/plain, */*;q=0.8", forHTTPHeaderField: "Accept")

        let (data, response) = try await session.data(for: request)
        if let httpResponse = response as? HTTPURLResponse {
            Self.logger.debug("Translation response status=\(httpResponse.statusCode, privacy: .public)")
            guard (200..<300).contains(httpResponse.statusCode) else {
                throw TranslationServiceError.requestFailed
            }
        }

        guard let translated = Self.parseTranslatedText(from: data) else {
            throw TranslationServiceError.invalidResponse
        }

        return translated.isEmpty ? text : translated
    }

    private static func makeURL(for text: String, targetLanguage: String) -> URL? {
        var components = URLComponents(string: "https://translate.googleapis.com/translate_a/single")
        components?.queryItems = [
            URLQueryItem(name: "client", value: "gtx"),
            URLQueryItem(name: "sl", value: "auto"),
            URLQueryItem(name: "tl", value: targetLanguage),
            URLQueryItem(name: "dt", value: "t"),
            URLQueryItem(name: "q", value: text)
        ]
        return components?.url
    }

    private static func parseTranslatedText(from data: Data) -> String? {
        guard
            let json = try? JSONSerialization.jsonObject(with: data),
            let payload = json as? [Any],
            let fragments = payload.first as? [[Any]]
        else {
            return nil
        }

        return fragments.compactMap { fragment in
            fragment.first as? String
        }.joined()
    }
}
