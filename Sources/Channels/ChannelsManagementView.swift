import SwiftUI

struct ChannelsManagementView: View {
    @ObservedObject var viewModel: ChannelsViewModel
    let onAdd: () -> Void
    let onRemove: () -> Void
    let onSelect: (Int64?) -> Void
    let onClose: (() -> Void)?

    init(
        viewModel: ChannelsViewModel,
        onAdd: @escaping () -> Void,
        onRemove: @escaping () -> Void,
        onSelect: @escaping (Int64?) -> Void,
        onClose: (() -> Void)? = nil
    ) {
        self.viewModel = viewModel
        self.onAdd = onAdd
        self.onRemove = onRemove
        self.onSelect = onSelect
        self.onClose = onClose
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            header
            addChannelField
            feedList
            footer
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

            Text("\(viewModel.channels.count)")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
                .padding(.horizontal, 10)
                .padding(.vertical, 5)
                .background(Color.white.opacity(0.86), in: Capsule(style: .continuous))
                .overlay(
                    Capsule(style: .continuous)
                        .strokeBorder(Color.black.opacity(0.05), lineWidth: 1)
                )

            if let onClose {
                Button(action: onClose) {
                    Image(systemName: "xmark")
                        .font(.system(size: 13, weight: .semibold))
                        .frame(width: 30, height: 30)
                }
                .buttonStyle(DrawerIconButtonStyle())
                .help(L10n.tr("general.close"))
            }
        }
    }

    private var addChannelField: some View {
        HStack(spacing: 10) {
            TextField(L10n.tr("sidebar.channelPlaceholder"), text: $viewModel.channelInput)
                .textFieldStyle(.plain)
                .padding(.horizontal, 14)
                .padding(.vertical, 11)
                .background(Color.white.opacity(0.88), in: RoundedRectangle(cornerRadius: 18, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: 18, style: .continuous)
                        .strokeBorder(Color.black.opacity(0.06), lineWidth: 1)
                )

            Button(L10n.tr("sidebar.addChannel"), action: onAdd)
                .buttonStyle(AddChannelButtonStyle())
        }
    }

    private var feedList: some View {
        ScrollView {
            LazyVStack(spacing: 10) {
                ForEach(viewModel.channels) { channel in
                    channelRow(channel)
                }
            }
            .padding(.vertical, 2)
        }
        .scrollIndicators(.visible)
        .frame(maxHeight: .infinity)
    }

    private func channelRow(_ channel: WatchedChannel) -> some View {
        let isSelected = viewModel.selectedChannelID == channel.chatID

        return Button {
            viewModel.selectedChannelID = channel.chatID
            onSelect(channel.chatID)
        } label: {
            HStack(alignment: .center, spacing: 12) {
                channelIcon(title: channel.title)

                VStack(alignment: .leading, spacing: 4) {
                    Text(channel.title)
                        .font(.headline)
                        .foregroundStyle(.primary)
                        .lineLimit(1)
                    Text("@\(channel.username)")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }

                Spacer(minLength: 8)

                if channel.unreadCount > 0 {
                    Text("\(channel.unreadCount)")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.secondary)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 5)
                        .background(Color.white.opacity(0.9), in: Capsule(style: .continuous))
                }
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 12)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .buttonStyle(.plain)
        .background(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .fill(isSelected ? Color.white.opacity(0.88) : Color.white.opacity(0.62))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .strokeBorder(
                    isSelected ? Color.black.opacity(0.08) : Color.black.opacity(0.04),
                    lineWidth: isSelected ? 1.2 : 1
                )
        )
        .shadow(color: isSelected ? .black.opacity(0.08) : .clear, radius: 12, x: 0, y: 6)
    }

    private func channelIcon(title: String) -> some View {
        let letter = title.prefix(1).uppercased()
        return ZStack {
            Circle()
                .fill(Color.white.opacity(0.92))
                .overlay(
                    Circle()
                        .strokeBorder(Color.black.opacity(0.06), lineWidth: 1)
                )
            Text(letter)
                .font(.system(size: 13, weight: .semibold, design: .rounded))
                .foregroundStyle(.secondary)
        }
        .frame(width: 34, height: 34)
    }

    private var footer: some View {
        VStack(alignment: .leading, spacing: 12) {
            if let errorMessage = viewModel.errorMessage {
                Text(errorMessage)
                    .font(.callout)
                    .foregroundStyle(.red)
            } else if viewModel.channels.isEmpty {
                Text(L10n.tr("sidebar.empty"))
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }

            Button(role: .destructive, action: onRemove) {
                Text(L10n.tr("sidebar.remove"))
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(RemoveButtonStyle())
            .disabled(viewModel.selectedChannelID == nil)
        }
    }
}

private struct DrawerIconButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .foregroundStyle(.secondary)
            .background(
                Circle()
                    .fill(Color.white.opacity(configuration.isPressed ? 0.72 : 0.9))
            )
            .overlay(
                Circle()
                    .strokeBorder(Color.black.opacity(0.05), lineWidth: 1)
            )
            .scaleEffect(configuration.isPressed ? 0.96 : 1)
    }
}

private struct AddChannelButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 13, weight: .semibold, design: .rounded))
            .foregroundStyle(.primary)
            .padding(.horizontal, 16)
            .padding(.vertical, 11)
            .background(
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .fill(Color.white.opacity(configuration.isPressed ? 0.72 : 0.92))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .strokeBorder(Color.black.opacity(0.06), lineWidth: 1)
            )
            .shadow(color: .black.opacity(configuration.isPressed ? 0.03 : 0.08), radius: 10, x: 0, y: 4)
            .scaleEffect(configuration.isPressed ? 0.98 : 1)
    }
}

private struct RemoveButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 13, weight: .semibold, design: .rounded))
            .foregroundStyle(.primary)
            .padding(.vertical, 11)
            .background(
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .fill(Color.white.opacity(configuration.isPressed ? 0.72 : 0.88))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .strokeBorder(Color.black.opacity(0.06), lineWidth: 1)
            )
            .scaleEffect(configuration.isPressed ? 0.98 : 1)
    }
}
