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
                VStack(alignment: .leading, spacing: 22) {
                    header

                    content(for: post)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 2)
            }
            .scrollIndicators(.visible)

            scrollHint
        }
        .padding(22)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color.white.opacity(0.28))
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(alignment: .top) {
                Button {
                    onClose()
                } label: {
                    Image(systemName: "chevron.left")
                        .font(.system(size: 15, weight: .semibold))
                        .frame(width: 42, height: 42)
                }
                .buttonStyle(NavBackButtonStyle())
                .help(L10n.tr("viewer.close"))

                Spacer(minLength: 0)
            }

            VStack(alignment: .leading, spacing: 10) {
                Text(post.channelTitle)
                    .font(.system(size: 16, weight: .semibold, design: .rounded))
                    .foregroundStyle(.secondary)
                    .lineLimit(2)

                Text(post.titleOrFallback)
                    .font(.system(size: 26, weight: .bold, design: .rounded))
                    .foregroundStyle(.primary)
                    .lineLimit(4)
                    .fixedSize(horizontal: false, vertical: true)

                HStack(spacing: 8) {
                    Text(post.date.formatted(date: .abbreviated, time: .shortened))
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.secondary)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 6)
                        .background(Color.white.opacity(0.88), in: Capsule(style: .continuous))
                        .overlay(
                            Capsule(style: .continuous)
                                .strokeBorder(Color.black.opacity(0.05), lineWidth: 1)
                        )

                    if let author = post.author, author.isEmpty == false {
                        Text(author)
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(.secondary)
                            .padding(.horizontal, 10)
                            .padding(.vertical, 6)
                            .background(Color.white.opacity(0.88), in: Capsule(style: .continuous))
                            .overlay(
                                Capsule(style: .continuous)
                                    .strokeBorder(Color.black.opacity(0.05), lineWidth: 1)
                            )
                    }
                }
            }

            Divider()
                .overlay(Color.black.opacity(0.08))
        }
    }

    @ViewBuilder
    private func content(for post: UnreadPost) -> some View {
        switch post.content {
        case .text(let body):
            Text(body)
                .frame(maxWidth: 760, alignment: .leading)
                .font(.system(size: 18, weight: .regular, design: .rounded))
                .foregroundStyle(.primary)
                .textSelection(.enabled)
                .lineSpacing(4)

        case .photo(let caption, _):
            mediaWrapper(caption: caption) {
                if viewModel.isLoadingMedia {
                    ProgressView(L10n.tr("viewer.loadingMedia"))
                        .frame(maxWidth: .infinity, minHeight: 360)
                } else if let url = viewModel.mediaURL, let image = loadImage(from: url) {
                    Image(nsImage: image)
                        .resizable()
                        .scaledToFit()
                        .frame(maxWidth: 760)
                        .clipShape(RoundedRectangle(cornerRadius: 24, style: .continuous))
                        .shadow(color: .black.opacity(0.12), radius: 18, x: 0, y: 10)
                } else {
                    Text(viewModel.errorMessage ?? L10n.tr("viewer.mediaUnavailable"))
                        .foregroundStyle(.secondary)
                }
            }

        case .video(let caption, _, _):
            mediaWrapper(caption: caption) {
                if viewModel.isLoadingMedia {
                    ProgressView(L10n.tr("viewer.loadingMedia"))
                        .frame(maxWidth: .infinity, minHeight: 360)
                } else if let player = viewModel.player {
                    NativeVideoPlayerView(player: player)
                        .frame(maxWidth: 760)
                        .frame(minHeight: 360)
                        .clipShape(RoundedRectangle(cornerRadius: 24, style: .continuous))
                        .shadow(color: .black.opacity(0.12), radius: 18, x: 0, y: 10)
                } else {
                    Text(viewModel.errorMessage ?? L10n.tr("viewer.mediaUnavailable"))
                        .foregroundStyle(.secondary)
                }
            }

        case .unsupported(let summary):
            Text(summary)
                .foregroundStyle(.secondary)
                .frame(maxWidth: 760, alignment: .leading)
        }
    }

    private func mediaWrapper<Content: View>(caption: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 16) {
            content()
            if caption.isEmpty == false {
                Text(caption)
                    .frame(maxWidth: 760, alignment: .leading)
                    .textSelection(.enabled)
                    .font(.body)
                    .foregroundStyle(.primary)
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
        .background(Color.white.opacity(0.86), in: Capsule(style: .continuous))
        .overlay(
            Capsule(style: .continuous)
                .strokeBorder(Color.black.opacity(0.05), lineWidth: 1)
        )
        .padding(.trailing, 14)
        .padding(.bottom, 14)
        .allowsHitTesting(false)
    }
}

private struct NavBackButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .foregroundStyle(.secondary)
            .background(
                Circle()
                    .fill(Color.white.opacity(configuration.isPressed ? 0.72 : 0.92))
            )
            .overlay(
                Circle()
                    .strokeBorder(Color.black.opacity(0.05), lineWidth: 1)
            )
            .shadow(color: .black.opacity(configuration.isPressed ? 0.03 : 0.08), radius: 10, x: 0, y: 4)
            .scaleEffect(configuration.isPressed ? 0.97 : 1)
    }
}

private extension UnreadPost {
    var titleOrFallback: String {
        switch content {
        case .text(let body):
            return body.split(separator: "\n").first.map(String.init) ?? summary
        case .photo(let caption, _):
            return caption.isEmpty ? summary : caption
        case .video(let caption, _, _):
            return caption.isEmpty ? summary : caption
        case .unsupported(let summary):
            return summary
        }
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
