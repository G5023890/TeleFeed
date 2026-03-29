import Foundation

enum TranslationServiceError: LocalizedError {
    case invalidResponse
    case requestFailed

    var errorDescription: String? {
        L10n.tr("translation.unavailable")
    }
}

protocol TranslationServiceProtocol: AnyObject, Sendable {
    func translate(_ text: String) async throws -> String
}

extension TranslationServiceProtocol {
    func translate(_ texts: [String]) async throws -> [String] {
        try await withThrowingTaskGroup(of: (Int, String).self) { group in
            for (index, text) in texts.enumerated() {
                group.addTask {
                    let translated = try await self.translate(text)
                    return (index, translated)
                }
            }

            var results = Array(repeating: "", count: texts.count)
            for try await (index, translated) in group {
                results[index] = translated
            }
            return results
        }
    }
}
