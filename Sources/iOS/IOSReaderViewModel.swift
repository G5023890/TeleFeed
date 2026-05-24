import Foundation

@MainActor
final class IOSReaderViewModel: ObservableObject {
    enum Phase: Equatable {
        case idle
        case loading
        case loaded(ReaderArticle)
        case failed(String)
    }

    @Published private(set) var phase: Phase = .idle

    private let readerService: ReaderServiceProtocol
    private var loadTask: Task<Void, Never>?

    init(readerService: ReaderServiceProtocol = ReaderService()) {
        self.readerService = readerService
    }

    deinit {
        loadTask?.cancel()
    }

    func open(post: UnreadPost) {
        guard loadTask == nil else {
            return
        }

        guard let url = post.articleURL else {
            phase = .failed(L10n.tr("reader.noURL"))
            return
        }

        phase = .loading
        loadTask = Task { [readerService] in
            do {
                let article = try await readerService.loadArticle(from: url, fallbackTitle: post.titleOrFallback)
                guard Task.isCancelled == false else {
                    return
                }
                await MainActor.run {
                    self.phase = .loaded(article)
                    self.loadTask = nil
                }
            } catch {
                guard Task.isCancelled == false else {
                    return
                }
                await MainActor.run {
                    self.phase = .failed(error.localizedDescription)
                    self.loadTask = nil
                }
            }
        }
    }
}
