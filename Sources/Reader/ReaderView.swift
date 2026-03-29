import AppKit
import SwiftUI

struct ReaderView: View {
    @ObservedObject var viewModel: ReaderViewModel
    let settings: AppSettings
    let onBack: () -> Void
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 22) {
                header

                switch viewModel.phase {
                case .idle, .loading:
                    loadingState
                case .failed(let message):
                    errorState(message: message)
                case .loaded:
                    if let article = viewModel.displayedArticle {
                        articleBody(article)
                    } else {
                        loadingState
                    }
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 2)
        }
        .padding(22)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
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

                        Spacer(minLength: 0)

                        safariButton
                        translateButton
                    }
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
                .frame(maxWidth: .infinity, minHeight: 180, alignment: .center)
        }
        .frame(maxWidth: 760, alignment: .leading)
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
        .frame(maxWidth: 760, alignment: .leading)
    }

    private func articleBody(_ article: ReaderArticle) -> some View {
        VStack(alignment: .leading, spacing: 18) {
            if let imageURL = article.imageURL {
                AsyncImage(url: imageURL) { phase in
                    switch phase {
                    case .empty:
                        ProgressView()
                            .frame(maxWidth: .infinity, minHeight: 220)
                    case .success(let image):
                        image
                            .resizable()
                            .scaledToFit()
                            .clipShape(RoundedRectangle(cornerRadius: 24, style: .continuous))
                            .shadow(color: .black.opacity(0.12), radius: 18, x: 0, y: 10)
                    case .failure:
                        EmptyView()
                    @unknown default:
                        EmptyView()
                    }
                }
            }

            VStack(alignment: .leading, spacing: 18) {
                if article.blocks.isEmpty {
                    readableTextBlock(
                        article.body,
                        fontSize: CGFloat(settings.typography.readerBody),
                        weight: .regular,
                        lineSpacing: 6
                    )
                } else {
                    ForEach(Array(article.blocks.enumerated()), id: \.offset) { _, block in
                        blockView(block)
                    }
                }
            }
            .frame(maxWidth: 760, alignment: .leading)
        }
        .frame(maxWidth: 760, alignment: .leading)
    }

    @ViewBuilder
    private func blockView(_ block: ReaderArticle.Block) -> some View {
        switch block {
        case .heading(let text, let level):
            Text(text)
                .font(headingFont(for: level))
                .foregroundStyle(.primary)
                .lineLimit(nil)
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: .infinity, alignment: .leading)

        case .paragraph(let text):
            readableTextBlock(text, fontSize: CGFloat(settings.typography.readerBody), weight: .regular, lineSpacing: 6)

        case .quote(let text):
            HStack(alignment: .top, spacing: 12) {
                RoundedRectangle(cornerRadius: 2, style: .continuous)
                    .fill(AppTheme.readerChipStroke(for: colorScheme))
                    .frame(width: 4)
                    .padding(.top, 4)

                readableTextBlock(text, fontSize: CGFloat(settings.typography.readerQuote), weight: .regular, lineSpacing: 6)
                    .foregroundStyle(.secondary)
            }
            .padding(16)
            .background(AppTheme.readerChipFill(for: colorScheme), in: RoundedRectangle(cornerRadius: 20, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 20, style: .continuous)
                    .strokeBorder(AppTheme.readerChipStroke(for: colorScheme), lineWidth: 1)
            )

        case .list(let items, let ordered):
            VStack(alignment: .leading, spacing: 10) {
                ForEach(Array(items.enumerated()), id: \.offset) { index, item in
                    HStack(alignment: .top, spacing: 10) {
                        Text(ordered ? "\(index + 1)." : "•")
                            .font(.system(size: CGFloat(settings.typography.readerListBullet), weight: .semibold, design: .rounded))
                            .foregroundStyle(.secondary)
                            .frame(width: 22, alignment: .trailing)

                        readableTextBlock(item, fontSize: CGFloat(settings.typography.readerBody), weight: .regular, lineSpacing: 6)
                    }
                }
            }

        case .code(let text):
            readableTextBlock(text, fontSize: CGFloat(settings.typography.readerCode), weight: .regular, lineSpacing: 4)
                .fontDesign(.monospaced)
                .padding(14)
                .background(AppTheme.readerChipFill(for: colorScheme), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: 16, style: .continuous)
                        .strokeBorder(AppTheme.readerChipStroke(for: colorScheme), lineWidth: 1)
                )

        case .separator:
            Divider()
                .overlay(AppTheme.separatorColor(for: colorScheme))
                .padding(.vertical, 4)
        }
    }

    private func readableTextBlock(
        _ text: String,
        fontSize: CGFloat,
        weight: NSFont.Weight,
        lineSpacing: CGFloat
    ) -> some View {
        SelectableTextView(
            text: text,
            font: .systemFont(ofSize: fontSize, weight: weight),
            textColor: .labelColor,
            lineSpacing: lineSpacing,
            maximumWidth: 760
        )
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func headingFont(for level: Int) -> Font {
        switch level {
        case 1:
            return .system(size: CGFloat(settings.typography.readerHeading1), weight: .bold, design: .rounded)
        case 2:
            return .system(size: CGFloat(settings.typography.readerHeading2), weight: .bold, design: .rounded)
        case 3:
            return .system(size: CGFloat(settings.typography.readerHeading3), weight: .semibold, design: .rounded)
        case 4:
            return .system(size: CGFloat(settings.typography.readerHeading4), weight: .semibold, design: .rounded)
        case 5, 6:
            return .system(size: CGFloat(settings.typography.readerHeading5), weight: .semibold, design: .rounded)
        default:
            return .system(size: CGFloat(settings.typography.readerHeading6), weight: .bold, design: .rounded)
        }
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
