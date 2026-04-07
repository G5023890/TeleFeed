import AVKit
import AppKit
import SwiftUI

struct PostViewerView: View {
    let post: UnreadPost
    @ObservedObject var viewModel: ViewerViewModel
    let settings: AppSettings
    let onClose: () -> Void
    let onOpenReader: (() -> Void)?
    @Environment(\.colorScheme) private var colorScheme
    @State private var contentHeight: CGFloat = 0
    @State private var viewportHeight: CGFloat = 0

    var body: some View {
        ZStack(alignment: .bottomTrailing) {
            ScrollView {
                VStack(alignment: .leading, spacing: 22) {
                    header

                    content(for: viewModel.displayContent(for: post))
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 2)
                .background(
                    GeometryReader { proxy in
                        Color.clear.preference(key: ViewerContentHeightKey.self, value: proxy.size.height)
                    }
                )
            }
            .scrollIndicators(.visible)

            if shouldShowScrollHint {
                scrollHint
            }
        }
        .padding(22)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .verticalStoryMotion(id: post.id)
        .background(
            GeometryReader { proxy in
                Color.clear.preference(key: ViewerViewportHeightKey.self, value: proxy.size.height)
            }
        )
        .onPreferenceChange(ViewerContentHeightKey.self) { contentHeight = $0 }
        .onPreferenceChange(ViewerViewportHeightKey.self) { viewportHeight = $0 }
    }

    private var shouldShowScrollHint: Bool {
        contentHeight > viewportHeight + 1
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(alignment: .top) {
                Button {
                    onClose()
                } label: {
                    Image(systemName: "chevron.left")
                        .font(.system(size: CGFloat(settings.typography.viewerMeta), weight: .semibold))
                        .frame(width: 42, height: 42)
                }
                .buttonStyle(NavBackButtonStyle(colorScheme: colorScheme))
                .help(L10n.tr("viewer.close"))

                Spacer(minLength: 0)
            }

            VStack(alignment: .leading, spacing: 10) {
                Text(post.channelTitle)
                    .font(.system(size: CGFloat(settings.typography.viewerChannelTitle), weight: .semibold, design: .rounded))
                    .foregroundStyle(.secondary)
                    .lineLimit(2)

                if let onOpenReader, post.articleURL != nil {
                    Button {
                        onOpenReader()
                    } label: {
                        Text(post.titleOrFallback)
                            .font(.system(size: CGFloat(settings.typography.viewerTitle), weight: .bold, design: .rounded))
                            .foregroundStyle(.primary)
                            .lineLimit(4)
                            .fixedSize(horizontal: false, vertical: true)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .help(L10n.tr("reader.open"))
                } else {
                    Text(post.titleOrFallback)
                        .font(.system(size: CGFloat(settings.typography.viewerTitle), weight: .bold, design: .rounded))
                        .foregroundStyle(.primary)
                        .lineLimit(4)
                        .fixedSize(horizontal: false, vertical: true)
                }

                HStack(alignment: .center, spacing: 8) {
                    dateChip(post.date.formatted(date: .abbreviated, time: .shortened))

                    if let author = post.author, author.isEmpty == false {
                        dateChip(author)
                    }

                    Spacer(minLength: 0)

                    translateButton
                }

                if let translationError = viewModel.translationErrorMessage {
                    Text(translationError)
                        .font(.system(size: CGFloat(settings.typography.viewerMeta), weight: .semibold, design: .rounded))
                        .foregroundStyle(.red)
                }
            }

            Divider()
                .overlay(AppTheme.separatorColor(for: colorScheme))
        }
    }

    @ViewBuilder
    private func dateChip(_ text: String) -> some View {
        Text(text)
            .font(.system(size: CGFloat(settings.typography.viewerMeta), weight: .semibold, design: .rounded))
            .foregroundStyle(.secondary)
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background(AppTheme.readerChipFill(for: colorScheme), in: Capsule(style: .continuous))
            .overlay(
                Capsule(style: .continuous)
                    .strokeBorder(AppTheme.readerChipStroke(for: colorScheme), lineWidth: 1)
            )
    }

    private var translateButton: some View {
        Button {
            viewModel.toggleTranslation(for: post)
        } label: {
            if viewModel.translationState == .loading {
                HStack(spacing: 6) {
                    ProgressView()
                        .controlSize(.small)
                    Text(viewModel.translationButtonTitle)
                }
            } else {
                Text(viewModel.translationButtonTitle)
            }
        }
        .buttonStyle(.plain)
        .font(.system(size: CGFloat(settings.typography.viewerMeta), weight: .semibold, design: .rounded))
        .foregroundStyle(.primary)
        .disabled(viewModel.translationState == .loading)
    }

    @ViewBuilder
    private func content(for content: TelegramPostContent) -> some View {
        switch content {
        case .text(let body):
            SelectableTextView(
                text: body,
                font: .systemFont(ofSize: CGFloat(settings.typography.viewerBody), weight: .regular),
                textColor: .labelColor,
                lineSpacing: 4,
                maximumWidth: 760
            )
            .frame(maxWidth: 760, alignment: .leading)

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
                    ZStack {
                        NativeVideoPlayerView(player: player)
                            .frame(maxWidth: 760)
                            .frame(minHeight: 360)

                        if viewModel.isVideoPlaying == false {
                            Button {
                                viewModel.playVideo()
                            } label: {
                                HStack(spacing: 8) {
                                    Image(systemName: "play.fill")
                                    Text("Play")
                                }
                                .font(.system(size: CGFloat(settings.typography.viewerMeta), weight: .semibold, design: .rounded))
                                .padding(.horizontal, 16)
                                .padding(.vertical, 10)
                            }
                            .buttonStyle(VideoPlayOverlayButtonStyle(colorScheme: colorScheme))
                        }
                    }
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
                SelectableTextView(
                    text: caption,
                    font: .systemFont(ofSize: CGFloat(settings.typography.viewerCaption), weight: .regular),
                    textColor: .labelColor,
                    maximumWidth: 760
                )
                .frame(maxWidth: 760, alignment: .leading)
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
        .background(AppTheme.readerChipFill(for: colorScheme), in: Capsule(style: .continuous))
        .overlay(
            Capsule(style: .continuous)
                .strokeBorder(AppTheme.readerChipStroke(for: colorScheme), lineWidth: 1)
        )
        .padding(.trailing, 14)
        .padding(.bottom, 14)
        .allowsHitTesting(false)
    }
}

private struct ViewerContentHeightKey: PreferenceKey {
    static let defaultValue: CGFloat = 0

    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
        value = nextValue()
    }
}

private struct ViewerViewportHeightKey: PreferenceKey {
    static let defaultValue: CGFloat = 0

    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
        value = nextValue()
    }
}

private struct NavBackButtonStyle: ButtonStyle {
    let colorScheme: ColorScheme

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .foregroundStyle(.secondary)
            .background(
                Circle()
                    .fill(colorScheme == .dark ? Color.white.opacity(configuration.isPressed ? 0.08 : 0.12) : Color.white.opacity(configuration.isPressed ? 0.72 : 0.92))
            )
            .overlay(
                Circle()
                    .strokeBorder(AppTheme.readerChipStroke(for: colorScheme), lineWidth: 1)
            )
            .shadow(color: colorScheme == .dark ? .black.opacity(configuration.isPressed ? 0.18 : 0.3) : .black.opacity(configuration.isPressed ? 0.03 : 0.08), radius: 10, x: 0, y: 4)
            .scaleEffect(configuration.isPressed ? 0.97 : 1)
    }
}

private struct NativeVideoPlayerView: NSViewRepresentable {
    let player: AVPlayer

    func makeNSView(context: Context) -> PlayerLayerView {
        let view = PlayerLayerView()
        view.player = player
        return view
    }

    func updateNSView(_ nsView: PlayerLayerView, context: Context) {
        if nsView.player !== player {
            nsView.player = player
        }
    }
}

private final class PlayerLayerView: NSView {
    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        wantsLayer = true
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        wantsLayer = true
    }

    override func makeBackingLayer() -> CALayer {
        let layer = AVPlayerLayer()
        layer.videoGravity = .resizeAspect
        return layer
    }

    override func layout() {
        super.layout()
        layer?.frame = bounds
    }

    var player: AVPlayer? {
        get {
            (layer as? AVPlayerLayer)?.player
        }
        set {
            wantsLayer = true
            if layer == nil {
                layer = makeBackingLayer()
            }
            if let playerLayer = layer as? AVPlayerLayer {
                playerLayer.player = newValue
                playerLayer.videoGravity = .resizeAspect
            }
        }
    }
}

private struct VideoPlayOverlayButtonStyle: ButtonStyle {
    let colorScheme: ColorScheme

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .foregroundStyle(.primary)
            .background(
                Capsule(style: .continuous)
                    .fill(colorScheme == .dark ? Color.white.opacity(configuration.isPressed ? 0.10 : 0.14) : Color.white.opacity(configuration.isPressed ? 0.80 : 0.92))
            )
            .overlay(
                Capsule(style: .continuous)
                    .strokeBorder(AppTheme.readerChipStroke(for: colorScheme), lineWidth: 1)
            )
            .shadow(color: colorScheme == .dark ? .black.opacity(0.25) : .black.opacity(0.10), radius: 10, x: 0, y: 4)
            .scaleEffect(configuration.isPressed ? 0.97 : 1)
    }
}
