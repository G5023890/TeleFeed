import Foundation

enum ReaderFallbackAction {
    case retryWithLegacyParser
    case fail
}

struct ReaderFallbackPolicy {
    func action(for error: Error) -> ReaderFallbackAction {
        switch error {
        case is CancellationError:
            return .fail
        case let readerError as ReaderServiceError:
            switch readerError {
            case .invalidURL:
                return .fail
            case .invalidArticle, .emptyArticle, .unsupportedEncoding:
                return .retryWithLegacyParser
            }
        default:
            return .retryWithLegacyParser
        }
    }

    func canOpenSafari(for url: URL?) -> Bool {
        url != nil
    }
}
