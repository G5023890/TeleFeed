import AppKit
import SwiftUI

struct ReaderView: View {
    @ObservedObject var viewModel: ReaderViewModel
    let settings: AppSettings
    let onBack: () -> Void
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            header
            content
        }
        .padding(22)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(AppTheme.drawerFill(for: colorScheme))
    }

    private var content: some View {
        Group {
            switch viewModel.phase {
            case .idle, .loading:
                loadingState
            case .failed(let message):
                errorState(message: message)
            case .loaded:
                if let article = viewModel.displayedArticle {
                    ReaderWebView(
                        html: ReaderHTMLTemplate.makeHTML(
                            for: article,
                            settings: settings,
                            appearance: colorScheme == .dark ? .dark : .light
                        ),
                        baseURL: article.canonicalURL
                    )
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else {
                    loadingState
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(alignment: .top) {
                Button {
                    onBack()
                } label: {
                    Image(systemName: "chevron.left")
                        .font(.system(size: CGFloat(settings.typography.readerMeta), weight: .semibold))
                        .frame(width: 42, height: 42)
                }
                .buttonStyle(NavBackButtonStyle(colorScheme: colorScheme))
                .help(L10n.tr("reader.back"))

                Spacer(minLength: 0)
            }

            VStack(alignment: .leading, spacing: 10) {
                Text(viewModel.currentPost?.channelTitle ?? L10n.tr("reader.title"))
                    .font(.system(size: CGFloat(settings.typography.readerChannelTitle), weight: .semibold, design: .rounded))
                    .foregroundStyle(.secondary)
                    .lineLimit(2)

                Text(viewModel.displayedArticle?.title ?? viewModel.currentPost?.titleOrFallback ?? L10n.tr("reader.title"))
                    .font(.system(size: CGFloat(settings.typography.readerTitle), weight: .bold, design: .rounded))
                    .foregroundStyle(.primary)
                    .lineLimit(4)
                    .fixedSize(horizontal: false, vertical: true)

                HStack(alignment: .center, spacing: 8) {
                    if let post = viewModel.currentPost {
                        dateChip(post.date.formatted(date: .abbreviated, time: .shortened))

                        if let author = post.author, author.isEmpty == false {
                            dateChip(author)
                        }
                    }

                    Spacer(minLength: 0)

                    safariButton
                    translateButton
                }

                if let translationError = viewModel.translationErrorMessage {
                    Text(translationError)
                        .font(.system(size: CGFloat(settings.typography.readerMeta), weight: .semibold, design: .rounded))
                        .foregroundStyle(.red)
                }

                if let safariError = viewModel.safariErrorMessage {
                    Text(safariError)
                        .font(.system(size: CGFloat(settings.typography.readerMeta), weight: .semibold, design: .rounded))
                        .foregroundStyle(.red)
                }
            }

            Divider()
                .overlay(AppTheme.separatorColor(for: colorScheme))
        }
    }

    private func dateChip(_ text: String) -> some View {
        Text(text)
            .font(.system(size: CGFloat(settings.typography.readerMeta), weight: .semibold, design: .rounded))
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
            viewModel.toggleTranslation()
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
        .font(.system(size: CGFloat(settings.typography.readerMeta), weight: .semibold, design: .rounded))
        .foregroundStyle(.primary)
        .disabled(viewModel.canTranslate == false && viewModel.translationState != .translated)
    }

    private var safariButton: some View {
        Button {
            viewModel.openInSafari()
        } label: {
            HStack(spacing: 5) {
                Image(systemName: "safari")
                Text(viewModel.safariOpenButtonTitle)
            }
        }
        .buttonStyle(.plain)
        .font(.system(size: CGFloat(settings.typography.readerMeta), weight: .semibold, design: .rounded))
        .foregroundStyle(.primary)
        .disabled(viewModel.canOpenInSafari == false)
        .help(L10n.tr("reader.openSafari"))
    }

    private var loadingState: some View {
        VStack(alignment: .leading, spacing: 12) {
            ProgressView(L10n.tr("reader.loading"))
                .frame(maxWidth: .infinity, minHeight: 220, alignment: .center)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }

    private func errorState(message: String) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(L10n.tr("reader.error"))
                .font(.system(size: CGFloat(settings.typography.readerChannelTitle), weight: .semibold, design: .rounded))
            Text(message)
                .font(.system(size: CGFloat(settings.typography.readerBody), weight: .regular, design: .rounded))
                .foregroundStyle(.secondary)
                .textSelection(.enabled)
            Text(L10n.tr("reader.hint"))
                .font(.system(size: CGFloat(settings.typography.readerMeta), weight: .regular, design: .rounded))
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
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
