import Foundation

enum TranslationState: Equatable {
    case original
    case loading
    case translated
    case failed(String)
}
