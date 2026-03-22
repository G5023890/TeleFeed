import AVKit
import AppKit
import SwiftUI

struct PostViewerView: View {
    let post: UnreadPost
    @ObservedObject var viewModel: ViewerViewModel
    let onClose: () -> Void

    var body: some View {
        ZStack(alignment: .bottomTrailing) {
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    HStack {
                        VStack(alignment: .leading, spacing: 6) {
                            Text(post.channelTitle)
                                .font(.system(size: 24, weight: .semibold, design: .rounded))
                            Text(post.date.formatted(date: .abbreviated, time: .shortened))
                                .font(.callout)
                                .foregroundStyle(.secondary)
                        }
                        Spacer()
                        Button(L10n.tr("viewer.close")) {
                            onClose()
                        }
                        .buttonStyle(.bordered)
                    }

                    content(for: post)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .scrollIndicators(.visible)

            scrollHint
        }
        .padding(28)
        .frame(minWidth: 780, minHeight: 560)
        .background(.ultraThinMaterial)
    }

    @ViewBuilder
    private func content(for post: UnreadPost) -> some View {
        switch post.content {
        case .text(let body):
            Text(body)
                .frame(maxWidth: .infinity, alignment: .leading)
                .font(.system(size: 17, weight: .regular, design: .rounded))
                .textSelection(.enabled)

        case .photo(let caption, _):
            mediaWrapper(caption: caption) {
                if viewModel.isLoadingMedia {
                    ProgressView(L10n.tr("viewer.loadingMedia"))
                } else if let url = viewModel.mediaURL, let image = loadImage(from: url) {
                    Image(nsImage: image)
                        .resizable()
                        .scaledToFit()
                        .frame(maxWidth: .infinity)
                        .frame(maxHeight: 420)
                        .clipShape(RoundedRectangle(cornerRadius: 24, style: .continuous))
                } else {
                    Text(viewModel.errorMessage ?? L10n.tr("viewer.mediaUnavailable"))
                        .foregroundStyle(.secondary)
                }
            }

        case .video(let caption, _, _):
            mediaWrapper(caption: caption) {
                if viewModel.isLoadingMedia {
                    ProgressView(L10n.tr("viewer.loadingMedia"))
                } else if let player = viewModel.player {
                    NativeVideoPlayerView(player: player)
                        .frame(minHeight: 360)
                        .clipShape(RoundedRectangle(cornerRadius: 24, style: .continuous))
                } else {
                    Text(viewModel.errorMessage ?? L10n.tr("viewer.mediaUnavailable"))
                        .foregroundStyle(.secondary)
                }
            }

        case .unsupported(let summary):
            Text(summary)
                .foregroundStyle(.secondary)
        }
    }

    private func mediaWrapper<Content: View>(caption: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 16) {
            content()
            if caption.isEmpty == false {
                Text(caption)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .textSelection(.enabled)
            }
        }
    }

    private func loadImage(from url: URL) -> NSImage? {
        if let image = NSImage(contentsOf: url) {
            return image
        }

        guard let data = try? Data(contentsOf: url) else {
            return nil
        }

        return NSImage(data: data)
    }

    private var scrollHint: some View {
        HStack(spacing: 6) {
            Image(systemName: "chevron.down")
            Text("Scroll for more")
        }
        .font(.caption.weight(.semibold))
        .foregroundStyle(.secondary)
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .background(.thinMaterial, in: Capsule(style: .continuous))
        .overlay(
            Capsule(style: .continuous)
                .strokeBorder(.white.opacity(0.15), lineWidth: 0.5)
        )
        .padding(.trailing, 12)
        .padding(.bottom, 12)
        .allowsHitTesting(false)
    }
}

private struct NativeVideoPlayerView: NSViewRepresentable {
    let player: AVPlayer

    func makeNSView(context: Context) -> AVPlayerView {
        let view = AVPlayerView()
        view.controlsStyle = .floating
        view.showsFullScreenToggleButton = true
        view.videoGravity = .resizeAspect
        view.player = player
        return view
    }

    func updateNSView(_ nsView: AVPlayerView, context: Context) {
        if nsView.player !== player {
            nsView.player = player
        }
    }
}
