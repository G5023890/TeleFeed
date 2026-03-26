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

    private let readerService: ReaderServiceProtocol
    private var loadTask: Task<Void, Never>?

    init(readerService: ReaderServiceProtocol) {
        self.readerService = readerService
    }

    func open(post: UnreadPost) {
        guard let url = post.articleURL else {
            currentPost = post
            currentArticle = nil
            phase = .failed(L10n.tr("reader.noURL"))
            return
        }

        loadTask?.cancel()
        currentPost = post
        currentArticle = nil
        phase = .loading

        loadTask = Task { [readerService] in
            do {
                let article = try await readerService.loadArticle(from: url, fallbackTitle: post.titleOrFallback)
                guard Task.isCancelled == false else {
                    return
                }
                await MainActor.run {
                    self.loadTask = nil
                    self.currentArticle = article
                    self.phase = .loaded
                }
            } catch {
                guard Task.isCancelled == false else {
                    return
                }
                await MainActor.run {
                    self.loadTask = nil
                    self.currentArticle = nil
                    self.phase = .failed(error.localizedDescription)
                }
            }
        }
    }

    func dismiss() {
        loadTask?.cancel()
        loadTask = nil
        currentPost = nil
        currentArticle = nil
        phase = .idle
    }
}
