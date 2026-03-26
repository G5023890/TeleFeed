import SwiftUI

struct ChannelsManagementView: View {
    @ObservedObject var viewModel: ChannelsViewModel
    @ObservedObject var rssViewModel: RSSFeedsViewModel
    let onAdd: () -> Void
    let onRemove: () -> Void
    let onSelect: (Int64?) -> Void
    let onAddRSS: () -> Void
    let onRemoveRSS: () -> Void
    let onSelectRSS: (String?) -> Void
    let onClose: (() -> Void)?
    @Environment(\.colorScheme) private var colorScheme

    init(
        viewModel: ChannelsViewModel,
        rssViewModel: RSSFeedsViewModel,
        onAdd: @escaping () -> Void,
        onRemove: @escaping () -> Void,
        onSelect: @escaping (Int64?) -> Void,
        onAddRSS: @escaping () -> Void,
        onRemoveRSS: @escaping () -> Void,
        onSelectRSS: @escaping (String?) -> Void,
        onClose: (() -> Void)? = nil
    ) {
        self.viewModel = viewModel
        self.rssViewModel = rssViewModel
        self.onAdd = onAdd
        self.onRemove = onRemove
        self.onSelect = onSelect
        self.onAddRSS = onAddRSS
        self.onRemoveRSS = onRemoveRSS
        self.onSelectRSS = onSelectRSS
        self.onClose = onClose
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            header

            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    sourceSection(
                        title: L10n.tr("sidebar.channels"),
                        subtitle: L10n.tr("sidebar.telegramSubtitle"),
                        count: viewModel.channels.count,
                        inputText: $viewModel.channelInput,
                        placeholder: L10n.tr("sidebar.channelPlaceholder"),
                        buttonTitle: L10n.tr("sidebar.addChannel"),
                        onAdd: onAdd,
                        rows: viewModel.channels.map { AnySourceRow.telegram($0) },
                        selectedID: viewModel.selectedChannel.map { AnySourceRow.telegram($0) },
                        errorMessage: viewModel.errorMessage,
                        emptyMessage: L10n.tr("sidebar.empty"),
                        removeEnabled: viewModel.selectedChannelID != nil,
                        removeAction: onRemove,
                        rowTap: { row in
                            if case .telegram(let channel) = row {
                                viewModel.selectedChannelID = channel.chatID
                                onSelect(channel.chatID)
                            }
                        }
                    )

                    sourceSection(
                        title: L10n.tr("sidebar.rssFeeds"),
                        subtitle: L10n.tr("sidebar.rssSubtitle"),
                        count: rssViewModel.feeds.count,
                        inputText: $rssViewModel.feedInput,
                        placeholder: L10n.tr("sidebar.rssPlaceholder"),
                        buttonTitle: L10n.tr("sidebar.addRSS"),
                        onAdd: onAddRSS,
                        rows: rssViewModel.feeds.map { AnySourceRow.rss($0) },
                        selectedID: rssViewModel.feed(for: rssViewModel.selectedFeedID).map { AnySourceRow.rss($0) },
                        errorMessage: rssViewModel.errorMessage,
                        emptyMessage: L10n.tr("sidebar.rssEmpty"),
                        removeEnabled: rssViewModel.selectedFeedID != nil,
                        removeAction: onRemoveRSS,
                        rowTap: { row in
                            if case .rss(let feed) = row {
                                rssViewModel.selectedFeedID = feed.id
                                onSelectRSS(feed.id)
                            }
                        }
                    )
                }
                .padding(.vertical, 2)
            }
        }
        .padding(18)
    }

    private var header: some View {
        HStack(alignment: .top, spacing: 12) {
            VStack(alignment: .leading, spacing: 4) {
                Text(L10n.tr("sidebar.channels"))
                    .font(.system(size: 22, weight: .semibold, design: .rounded))
                Text(L10n.tr("sidebar.subtitle"))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
            }

            Spacer(minLength: 0)

            Text("\(viewModel.channels.count + rssViewModel.feeds.count)")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
                .padding(.horizontal, 10)
                .padding(.vertical, 5)
                .background(AppTheme.chipFill(for: colorScheme), in: Capsule(style: .continuous))
                .overlay(
                    Capsule(style: .continuous)
                        .strokeBorder(AppTheme.chipStroke(for: colorScheme), lineWidth: 1)
                )

            if let onClose {
                Button(action: onClose) {
                    Image(systemName: "xmark")
                        .font(.system(size: 13, weight: .semibold))
                        .frame(width: 30, height: 30)
                }
                .buttonStyle(DrawerIconButtonStyle(colorScheme: colorScheme))
                .help(L10n.tr("general.close"))
            }
        }
    }

    private func sourceSection(
        title: String,
        subtitle: String,
        count: Int,
        inputText: Binding<String>,
        placeholder: String,
        buttonTitle: String,
        onAdd: @escaping () -> Void,
        rows: [AnySourceRow],
        selectedID: AnySourceRow?,
        errorMessage: String?,
        emptyMessage: String,
        removeEnabled: Bool,
        removeAction: @escaping () -> Void,
        rowTap: @escaping (AnySourceRow) -> Void
    ) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            sectionHeader(title: title, subtitle: subtitle, count: count)

            sourceInput(
                text: inputText,
                placeholder: placeholder,
                buttonTitle: buttonTitle,
                action: onAdd
            )

            LazyVStack(spacing: 10) {
                ForEach(rows) { row in
                    sourceRow(row, isSelected: selectedID == row, tap: rowTap)
                }
            }

            sectionFooter(
                errorMessage: errorMessage,
                emptyMessage: emptyMessage,
                hasItems: rows.isEmpty == false,
                removeEnabled: removeEnabled,
                removeAction: removeAction
            )
        }
    }

    private func sourceRow(_ row: AnySourceRow, isSelected: Bool, tap: @escaping (AnySourceRow) -> Void) -> some View {
        Button {
            tap(row)
        } label: {
            HStack(alignment: .center, spacing: 12) {
                sourceIcon(title: row.title)

                VStack(alignment: .leading, spacing: 4) {
                    Text(row.title)
                        .font(.headline)
                        .foregroundStyle(.primary)
                        .lineLimit(1)
                    Text(row.subtitle)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }

                Spacer(minLength: 8)
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 12)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .buttonStyle(.plain)
        .background(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .fill(isSelected ? AppTheme.surfaceFill(for: colorScheme) : AppTheme.inputFill(for: colorScheme).opacity(colorScheme == .dark ? 0.8 : 0.7))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .strokeBorder(
                    isSelected ? AppTheme.surfaceStroke(for: colorScheme) : AppTheme.surfaceStroke(for: colorScheme).opacity(0.7),
                    lineWidth: isSelected ? 1.2 : 1
                )
        )
        .shadow(color: isSelected ? (colorScheme == .dark ? .black.opacity(0.4) : .black.opacity(0.08)) : .clear, radius: 12, x: 0, y: 6)
    }

    private func sourceIcon(title: String) -> some View {
        let letter = title.prefix(1).uppercased()
        return ZStack {
            Circle()
                .fill(AppTheme.surfaceFill(for: colorScheme))
                .overlay(
                    Circle()
                        .strokeBorder(AppTheme.surfaceStroke(for: colorScheme), lineWidth: 1)
                )
            Text(letter)
                .font(.system(size: 13, weight: .semibold, design: .rounded))
                .foregroundStyle(.secondary)
        }
        .frame(width: 34, height: 34)
    }

    private func sectionHeader(title: String, subtitle: String, count: Int) -> some View {
        HStack(alignment: .top, spacing: 12) {
            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                    .font(.system(size: 18, weight: .semibold, design: .rounded))
                Text(subtitle)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
            }

            Spacer(minLength: 0)

            Text("\(count)")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
                .padding(.horizontal, 10)
                .padding(.vertical, 5)
                .background(AppTheme.chipFill(for: colorScheme), in: Capsule(style: .continuous))
                .overlay(
                    Capsule(style: .continuous)
                        .strokeBorder(AppTheme.chipStroke(for: colorScheme), lineWidth: 1)
                )
        }
    }

    private func sourceInput(
        text: Binding<String>,
        placeholder: String,
        buttonTitle: String,
        action: @escaping () -> Void
    ) -> some View {
        HStack(spacing: 10) {
            TextField(placeholder, text: text)
                .textFieldStyle(.plain)
                .padding(.horizontal, 14)
                .padding(.vertical, 11)
                .background(AppTheme.inputFill(for: colorScheme), in: RoundedRectangle(cornerRadius: 18, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: 18, style: .continuous)
                        .strokeBorder(AppTheme.surfaceStroke(for: colorScheme), lineWidth: 1)
                )

            Button(buttonTitle, action: action)
                .buttonStyle(AddChannelButtonStyle(colorScheme: colorScheme))
        }
    }

    private func sectionFooter(
        errorMessage: String?,
        emptyMessage: String,
        hasItems: Bool,
        removeEnabled: Bool,
        removeAction: @escaping () -> Void
    ) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            if let errorMessage {
                Text(errorMessage)
                    .font(.callout)
                    .foregroundStyle(.red)
            } else if hasItems == false {
                Text(emptyMessage)
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }

            Button(role: .destructive, action: removeAction) {
                Text(L10n.tr("sidebar.remove"))
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(RemoveButtonStyle(colorScheme: colorScheme))
            .disabled(removeEnabled == false)
        }
    }
}

private enum AnySourceRow: Identifiable, Equatable {
    case telegram(WatchedChannel)
    case rss(RSSFeedSource)

    var id: String {
        switch self {
        case .telegram(let channel):
            return "telegram-\(channel.chatID)"
        case .rss(let feed):
            return "rss-\(feed.id)"
        }
    }

    var title: String {
        switch self {
        case .telegram(let channel):
            return channel.title
        case .rss(let feed):
            return feed.title
        }
    }

    var subtitle: String {
        switch self {
        case .telegram(let channel):
            return "@\(channel.username)"
        case .rss(let feed):
            return feed.feedURL?.host?.replacingOccurrences(of: "www.", with: "") ?? feed.normalizedURLString
        }
    }
}

private struct DrawerIconButtonStyle: ButtonStyle {
    let colorScheme: ColorScheme

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .foregroundStyle(.secondary)
            .background(
                Circle()
                    .fill(colorScheme == .dark ? Color.white.opacity(configuration.isPressed ? 0.08 : 0.12) : Color.white.opacity(configuration.isPressed ? 0.72 : 0.9))
            )
            .overlay(
                Circle()
                    .strokeBorder(AppTheme.surfaceStroke(for: colorScheme), lineWidth: 1)
            )
            .scaleEffect(configuration.isPressed ? 0.96 : 1)
    }
}

private struct AddChannelButtonStyle: ButtonStyle {
    let colorScheme: ColorScheme

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 13, weight: .semibold, design: .rounded))
            .foregroundStyle(.primary)
            .padding(.horizontal, 16)
            .padding(.vertical, 11)
            .background(
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .fill(colorScheme == .dark ? Color.white.opacity(configuration.isPressed ? 0.08 : 0.12) : Color.white.opacity(configuration.isPressed ? 0.72 : 0.92))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .strokeBorder(AppTheme.surfaceStroke(for: colorScheme), lineWidth: 1)
            )
            .shadow(color: colorScheme == .dark ? .black.opacity(configuration.isPressed ? 0.18 : 0.28) : .black.opacity(configuration.isPressed ? 0.03 : 0.08), radius: 10, x: 0, y: 4)
            .scaleEffect(configuration.isPressed ? 0.98 : 1)
    }
}

private struct RemoveButtonStyle: ButtonStyle {
    let colorScheme: ColorScheme

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 13, weight: .semibold, design: .rounded))
            .foregroundStyle(.primary)
            .padding(.vertical, 11)
            .background(
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .fill(colorScheme == .dark ? Color.white.opacity(configuration.isPressed ? 0.08 : 0.10) : Color.white.opacity(configuration.isPressed ? 0.72 : 0.88))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .strokeBorder(AppTheme.surfaceStroke(for: colorScheme), lineWidth: 1)
            )
            .scaleEffect(configuration.isPressed ? 0.98 : 1)
    }
}
