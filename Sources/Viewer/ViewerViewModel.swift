import AVKit
import Foundation

@MainActor
final class ViewerViewModel: ObservableObject {
    @Published var presentedPost: UnreadPost?
    @Published var mediaURL: URL?
    @Published var player: AVPlayer?
    @Published var isLoadingMedia = false
    @Published var errorMessage: String?

    func present(post: UnreadPost, telegramService: TelegramServiceProtocol) {
        presentedPost = post
        mediaURL = nil
        player = nil
        errorMessage = nil
        isLoadingMedia = false

        guard let descriptor = post.mediaDescriptor else {
            return
        }

        isLoadingMedia = true
        Task {
            do {
                let url = try await telegramService.downloadMedia(for: descriptor)
                await MainActor.run {
                    self.mediaURL = url
                    self.isLoadingMedia = false
                    if descriptor.kind == .video {
                        self.player = AVPlayer(url: url)
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

    func dismiss() {
        player?.pause()
        presentedPost = nil
        mediaURL = nil
        player = nil
        errorMessage = nil
        isLoadingMedia = false
    }

    func playVideo() {
        player?.play()
    }
}
