import AVKit
import SwiftUI
import UIKit

struct NewsDetailView: View {
    let post: UnreadPost
    let onDownloadMedia: (UnreadPost) async throws -> URL
    let onOpenReader: () -> Void

    @State private var mediaURL: URL?
    @State private var mediaErrorMessage: String?
    @State private var isLoadingMedia = false
    @State private var videoPlayer: AVPlayer?

    var body: some View {
        ZStack {
            IOSGlassBackground()

            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    HStack(spacing: 10) {
                        Text(post.sourceKind == .rss ? "RSS" : "Telegram")
                            .font(.caption.weight(.bold))
                            .padding(.horizontal, 10)
                            .padding(.vertical, 6)
                            .background(.thinMaterial, in: Capsule(style: .continuous))

                        Text(post.date.formatted(date: .abbreviated, time: .shortened))
                            .font(.caption)
                            .foregroundStyle(.secondary)

                        Spacer(minLength: 0)
                    }

                    Text(post.titleOrFallback)
                        .font(.system(size: 18, weight: .bold, design: .rounded))
                        .fixedSize(horizontal: false, vertical: true)

                    VStack(alignment: .leading, spacing: 6) {
                        Label(post.channelTitle, systemImage: "person.crop.circle")
                        if let author = post.author, author.isEmpty == false {
                            Label(author, systemImage: "signature")
                        }
                    }
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.secondary)

                    Divider()

                    detailBody

                    if post.articleURL != nil {
                        Button {
                            onOpenReader()
                        } label: {
                            Label("Открыть статью", systemImage: "doc.text.magnifyingglass")
                                .frame(maxWidth: .infinity)
                        }
                        .buttonStyle(.glassProminent)
                    }
                }
                .padding(20)
            }
            .scrollIndicators(.hidden)
        }
        .navigationTitle("Новость")
        .navigationBarTitleDisplayMode(.inline)
        .task(id: post.id) {
            await loadMediaIfNeeded()
        }
        .onDisappear {
            videoPlayer?.pause()
        }
    }

    @ViewBuilder
    private var detailBody: some View {
        switch post.content {
        case .text(let body):
            Text(body)
                .font(.body)
                .lineSpacing(5)
                .textSelection(.enabled)
        case .photo(let caption, _):
            mediaBlock(caption: caption) {
                if isLoadingMedia {
                    loadingMediaView(title: "Загружаю фото")
                } else if let mediaURL, let image = UIImage(contentsOfFile: mediaURL.path) {
                    Image(uiImage: image)
                        .resizable()
                        .scaledToFit()
                        .frame(maxWidth: .infinity)
                        .clipShape(RoundedRectangle(cornerRadius: 22, style: .continuous))
                        .shadow(color: .black.opacity(0.14), radius: 18, x: 0, y: 10)
                } else {
                    mediaFallback(title: "Фото недоступно", systemImage: "photo")
                }
            }
            if caption.isEmpty == false {
                Text(caption)
                    .font(.body)
                    .lineSpacing(5)
                    .textSelection(.enabled)
            }
        case .video(let caption, _, let duration):
            mediaBlock(caption: caption) {
                if isLoadingMedia {
                    loadingMediaView(title: "Загружаю видео")
                } else if let videoPlayer {
                    VideoPlayer(player: videoPlayer)
                        .frame(minHeight: 260)
                        .clipShape(RoundedRectangle(cornerRadius: 22, style: .continuous))
                        .shadow(color: .black.opacity(0.14), radius: 18, x: 0, y: 10)
                } else {
                    mediaFallback(
                        title: duration > 0 ? "Видео, \(duration) сек." : "Видео недоступно",
                        systemImage: "play.rectangle"
                    )
                }
            }
            if caption.isEmpty == false {
                Text(caption)
                    .font(.body)
                    .lineSpacing(5)
                    .textSelection(.enabled)
            }
        case .unsupported(let summary):
            Text(summary)
                .font(.body)
                .foregroundStyle(.secondary)
                .textSelection(.enabled)
        }
    }

    private func loadMediaIfNeeded() async {
        guard post.mediaDescriptor != nil else {
            mediaURL = nil
            mediaErrorMessage = nil
            isLoadingMedia = false
            videoPlayer = nil
            return
        }

        mediaURL = nil
        mediaErrorMessage = nil
        isLoadingMedia = true
        videoPlayer = nil

        do {
            let url = try await onDownloadMedia(post)
            guard Task.isCancelled == false else {
                return
            }
            mediaURL = url
            if case .video = post.content {
                videoPlayer = AVPlayer(url: url)
            }
        } catch {
            guard Task.isCancelled == false else {
                return
            }
            mediaErrorMessage = error.localizedDescription
        }

        isLoadingMedia = false
    }

    private func mediaBlock<Content: View>(
        caption: String,
        @ViewBuilder content: () -> Content
    ) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            content()
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func loadingMediaView(title: String) -> some View {
        HStack(spacing: 10) {
            ProgressView()
            Text(title)
                .font(.headline)
        }
        .frame(maxWidth: .infinity, minHeight: 220)
        .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 22, style: .continuous))
    }

    private func mediaFallback(title: String, systemImage: String) -> some View {
        ContentUnavailableView(
            title,
            systemImage: systemImage,
            description: Text(mediaErrorMessage ?? "Telegram ещё не отдал файл для этой новости.")
        )
        .frame(maxWidth: .infinity, minHeight: 220)
        .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 22, style: .continuous))
    }
}
