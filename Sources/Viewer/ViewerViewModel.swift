import AVKit
import Combine
import Foundation

@MainActor
final class ViewerViewModel: ObservableObject {
    @Published var presentedPost: UnreadPost?
    @Published var mediaURL: URL?
    @Published var player: AVPlayer?
    @Published var isVideoPlaying = false
    @Published var isLoadingMedia = false
    @Published var errorMessage: String?
    @Published var translationState: TranslationState = .original
    @Published var translatedContent: TelegramPostContent?

    private let translationService: TranslationServiceProtocol
    private var translationTask: Task<Void, Never>?
    private var playerStatusObservation: AnyCancellable?

    init(translationService: TranslationServiceProtocol) {
        self.translationService = translationService
    }

    func present(post: UnreadPost, telegramService: TelegramServiceProtocol) {
        presentedPost = post
        mediaURL = nil
        playerStatusObservation = nil
        player = nil
        isVideoPlaying = false
        errorMessage = nil
        isLoadingMedia = false
        resetTranslation()

        guard let descriptor = post.mediaDescriptor else {
            return
        }

        isLoadingMedia = true
        Task {
            do {
                let url = try await telegramService.downloadMedia(
                    for: descriptor,
                    chatID: post.chatID,
                    messageID: post.messageID
                )
                await MainActor.run {
                    self.mediaURL = url
                    self.isLoadingMedia = false
                    if descriptor.kind == .video {
                        self.player = AVPlayer(url: url)
                        self.observePlayerState()
                    }
                }
            } catch {
                await MainActor.run {
                    self.errorMessage = error.localizedDescription
                    self.isLoadingMedia = false
                }
            }
        }
    }

    func toggleTranslation(for post: UnreadPost) {
        guard translationState != .loading else {
            return
        }

        switch translationState {
        case .translated:
            resetTranslation()
        case .original, .failed:
            translate(post)
        case .loading:
            break
        }
    }

    func displayContent(for post: UnreadPost) -> TelegramPostContent {
        if translationState == .translated, let translatedContent {
            return translatedContent
        }
        return post.content
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

    func dismiss() {
        translationTask?.cancel()
        translationTask = nil
        playerStatusObservation = nil
        player?.pause()
        presentedPost = nil
        mediaURL = nil
        player = nil
        isVideoPlaying = false
        errorMessage = nil
        isLoadingMedia = false
        resetTranslation()
    }

    func playVideo() {
        player?.play()
        isVideoPlaying = true
    }

    func pauseVideo() {
        player?.pause()
        isVideoPlaying = false
    }

    private func observePlayerState() {
        playerStatusObservation = player?.publisher(for: \.timeControlStatus)
            .receive(on: DispatchQueue.main)
            .sink { [weak self] status in
                guard let self else { return }
                self.isVideoPlaying = (status == .playing)
            }
    }

    private func translate(_ post: UnreadPost) {
        translationTask?.cancel()
        translatedContent = nil
        translationState = .loading

        let content = post.content
        translationTask = Task { [translationService] in
            do {
                let translated = try await Self.translate(content, using: translationService)
                guard Task.isCancelled == false else {
                    return
                }

                await MainActor.run {
                    guard self.presentedPost?.id == post.id else {
                        return
                    }
                    self.translatedContent = translated
                    self.translationState = .translated
                    self.translationTask = nil
                }
            } catch {
                guard Task.isCancelled == false else {
                    return
                }

                await MainActor.run {
                    guard self.presentedPost?.id == post.id else {
                        return
                    }
                    self.translationState = .failed(L10n.tr("translation.unavailable"))
                    self.translatedContent = nil
                    self.translationTask = nil
                }
            }
        }
    }

    private static func translate(
        _ content: TelegramPostContent,
        using translationService: TranslationServiceProtocol
    ) async throws -> TelegramPostContent {
        switch content {
        case .text(let body):
            return .text(body: try await translationService.translate(body))

        case .photo(let caption, let media):
            return .photo(caption: try await translationService.translate(caption), media: media)

        case .video(let caption, let media, let duration):
            return .video(
                caption: try await translationService.translate(caption),
                media: media,
                duration: duration
            )

        case .unsupported(let summary):
            return .unsupported(summary: try await translationService.translate(summary))
        }
    }

    private func resetTranslation() {
        translationTask?.cancel()
        translationTask = nil
        translatedContent = nil
        translationState = .original
    }
}
