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
        VStack(alignment: .leading, spacing: 16) {
            HStack(alignment: .firstTextBaseline, spacing: 12) {
                Text(L10n.tr("sidebar.channels"))
                    .font(.system(size: 22, weight: .semibold, design: .rounded))

                Spacer(minLength: 0)

                if let onClose {
                    Button(action: onClose) {
                        Image(systemName: "xmark")
                    }
                    .buttonStyle(.borderless)
                    .help(L10n.tr("general.close"))
                }
            }

            HStack(spacing: 10) {
                TextField(L10n.tr("sidebar.channelPlaceholder"), text: $viewModel.channelInput)
                    .textFieldStyle(.roundedBorder)

                Button(L10n.tr("sidebar.addChannel"), action: onAdd)
                    .buttonStyle(.borderedProminent)
            }

            List(selection: $viewModel.selectedChannelID) {
                ForEach(viewModel.channels) { channel in
                    VStack(alignment: .leading, spacing: 4) {
                        Text(channel.title)
                            .font(.headline)
                        Text("@\(channel.username)")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        Text(L10n.tr("sidebar.unreadCount", channel.unreadCount))
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                    .padding(.vertical, 4)
                    .tag(Optional.some(channel.chatID))
                }
            }
            .scrollContentBackground(.hidden)
            .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
            .onChange(of: viewModel.selectedChannelID) { _, newValue in
                onSelect(newValue)
            }

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
            .buttonStyle(.bordered)
            .disabled(viewModel.selectedChannelID == nil)
        }
        .padding(20)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 28, style: .continuous))
    }
}
