import AppKit
import Foundation

@MainActor
final class ReaderViewModel: ObservableObject {
    enum Phase: Equatable {
        case idle
        case loading
        case loaded
        case failed(String)
    }

    @Published var phase: Phase = .idle
    @Published var currentPost: UnreadPost?
    @Published var currentArticle: ReaderArticle?
    @Published var translatedArticle: ReaderArticle?
    @Published var translationState: TranslationState = .original
    @Published var safariErrorMessage: String?

    private let readerService: ReaderServiceProtocol
    private let translationService: TranslationServiceProtocol
    private let fallbackPolicy = ReaderFallbackPolicy()
    private var loadTask: Task<Void, Never>?
    private var translationTask: Task<Void, Never>?

    init(readerService: ReaderServiceProtocol, translationService: TranslationServiceProtocol) {
        self.readerService = readerService
        self.translationService = translationService
    }

    func open(post: UnreadPost) {
        loadTask?.cancel()
        translationTask?.cancel()
        safariErrorMessage = nil

        guard let url = post.articleURL else {
            currentPost = post
            currentArticle = nil
            translatedArticle = nil
            phase = .failed(L10n.tr("reader.noURL"))
            translationState = .original
            return
        }

        currentPost = post
        currentArticle = nil
        translatedArticle = nil
        phase = .loading
        translationState = .original
        safariErrorMessage = nil

        loadTask = Task { [readerService] in
            do {
                let article = try await readerService.loadArticle(from: url, fallbackTitle: post.titleOrFallback)
                guard Task.isCancelled == false else {
                    return
                }
                await MainActor.run {
                    self.loadTask = nil
                    self.currentArticle = article
                    self.translatedArticle = nil
                    self.phase = .loaded
                    self.translationState = .original
                    self.safariErrorMessage = nil
                }
            } catch {
                guard Task.isCancelled == false else {
                    return
                }
                await MainActor.run {
                    self.loadTask = nil
                    self.currentArticle = nil
                    self.translatedArticle = nil
                    self.phase = .failed(error.localizedDescription)
                    self.translationState = .original
                    self.safariErrorMessage = nil
                }
            }
        }
    }

    var displayedArticle: ReaderArticle? {
        if translationState == .translated {
            return translatedArticle ?? currentArticle
        }
        return currentArticle
    }

    var canTranslate: Bool {
        phase == .loaded && currentArticle != nil && translationState != .loading
    }

    var translationButtonTitle: String {
        switch translationState {
        case .translated:
            return L10n.tr("translate.original")
        case .loading:
            return L10n.tr("translate.loading")
        case .original, .failed:
            return L10n.tr("translate.button")
        }
    }

    var translationErrorMessage: String? {
        if case .failed(let message) = translationState {
            return message
        }
        return nil
    }

    var safariOpenButtonTitle: String {
        L10n.tr("reader.openSafari")
    }

    var canOpenInSafari: Bool {
        fallbackPolicy.canOpenSafari(for: safariURLToOpen)
    }

    func toggleTranslation() {
        guard canTranslate else {
            return
        }

        switch translationState {
        case .translated:
            translatedArticle = nil
            translationState = .original
        case .original, .failed:
            translateCurrentArticle()
        case .loading:
            break
        }
    }

    func openInSafari() {
        safariErrorMessage = nil

        guard let url = safariURLToOpen else {
            safariErrorMessage = L10n.tr("reader.noURL")
            return
        }

        guard let safariAppURL = Self.safariApplicationURL() else {
            safariErrorMessage = L10n.tr("reader.openSafariFailed")
            return
        }

        let configuration = NSWorkspace.OpenConfiguration()
        NSWorkspace.shared.open([url], withApplicationAt: safariAppURL, configuration: configuration) { _, error in
            if error != nil {
                Task { @MainActor in
                    self.safariErrorMessage = L10n.tr("reader.openSafariFailed")
                }
            }
        }
    }

    func dismiss() {
        loadTask?.cancel()
        loadTask = nil
        translationTask?.cancel()
        translationTask = nil
        currentPost = nil
        currentArticle = nil
        translatedArticle = nil
        phase = .idle
        translationState = .original
        safariErrorMessage = nil
    }

    private func translateCurrentArticle() {
        guard let article = currentArticle else {
            return
        }

        translationTask?.cancel()
        translatedArticle = nil
        translationState = .loading
        let postID = currentPost?.id

        translationTask = Task { [translationService] in
            do {
                let translated = try await Self.translate(article, using: translationService)
                guard Task.isCancelled == false else {
                    return
                }

                await MainActor.run {
                    guard self.currentPost?.id == postID else {
                        return
                    }
                    self.translatedArticle = translated
                    self.translationState = .translated
                    self.translationTask = nil
                }
            } catch {
                guard Task.isCancelled == false else {
                    return
                }

                await MainActor.run {
                    guard self.currentPost?.id == postID else {
                        return
                    }
                    self.translatedArticle = nil
                    self.translationState = .failed(L10n.tr("translation.unavailable"))
                    self.translationTask = nil
                }
            }
        }
    }

    private static func translate(
        _ article: ReaderArticle,
        using translationService: TranslationServiceProtocol
    ) async throws -> ReaderArticle {
        let translatedTitle = try await translationService.translate(article.title)
        let translatedBlocks = try await translateBlocks(article.blocks, using: translationService)
        var translatedExcerpt: String?
        if let excerpt = article.excerpt {
            translatedExcerpt = try await translationService.translate(excerpt)
        }

        return ReaderArticle(
            sourceURL: article.sourceURL,
            canonicalURL: article.canonicalURL,
            title: translatedTitle,
            body: composeBody(from: translatedBlocks),
            blocks: translatedBlocks,
            excerpt: translatedExcerpt,
            imageURL: article.imageURL
        )
    }

    private static func translateBlocks(
        _ blocks: [ReaderArticle.Block],
        using translationService: TranslationServiceProtocol
    ) async throws -> [ReaderArticle.Block] {
        var result: [ReaderArticle.Block] = []
        result.reserveCapacity(blocks.count)

        for block in blocks {
            switch block {
            case .heading(let text, let level):
                result.append(.heading(try await translationService.translate(text), level: level))
            case .paragraph(let text):
                result.append(.paragraph(try await translationService.translate(text)))
            case .quote(let text):
                result.append(.quote(try await translationService.translate(text)))
            case .list(let items, let ordered):
                let translatedItems = try await translationService.translate(items)
                result.append(.list(items: translatedItems, ordered: ordered))
            case .code(let text):
                result.append(.code(text))
            case .separator:
                result.append(.separator)
            }
        }

        return result
    }

    private static func composeBody(from blocks: [ReaderArticle.Block]) -> String {
        var lines: [String] = []
        for block in blocks {
            switch block {
            case .heading(let text, _):
                lines.append(text)
                lines.append("")
            case .paragraph(let text):
                lines.append(text)
                lines.append("")
            case .quote(let text):
                lines.append(text)
                lines.append("")
            case .list(let items, let ordered):
                for (index, item) in items.enumerated() {
                    let prefix = ordered ? "\(index + 1)." : "•"
                    lines.append("\(prefix) \(item)")
                }
                lines.append("")
            case .code(let text):
                lines.append(text)
                lines.append("")
            case .separator:
                lines.append("")
            }
        }
        return lines.joined(separator: "\n").trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private var safariURLToOpen: URL? {
        currentArticle?.canonicalURL
            ?? currentArticle?.sourceURL
            ?? currentPost?.articleURL
    }

    private static func safariApplicationURL() -> URL? {
        if let bundleURL = NSWorkspace.shared.urlForApplication(withBundleIdentifier: "com.apple.Safari") {
            return bundleURL
        }

        let fallbackURL = URL(fileURLWithPath: "/Applications/Safari.app")
        return FileManager.default.fileExists(atPath: fallbackURL.path) ? fallbackURL : nil
    }
}
