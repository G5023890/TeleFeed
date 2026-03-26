import Foundation

@MainActor
final class ChannelsViewModel: ObservableObject {
    @Published var channels: [WatchedChannel]
    @Published var selectedChannelID: Int64?
    @Published var channelInput = ""
    @Published var errorMessage: String?

    init(channels: [WatchedChannel], selectedChannelID: Int64? = nil) {
        self.channels = channels.sorted { $0.title.localizedCaseInsensitiveCompare($1.title) == .orderedAscending }
        self.selectedChannelID = selectedChannelID ?? self.channels.first?.chatID
    }

    var selectedChannel: WatchedChannel? {
        channel(for: selectedChannelID)
    }

    func channel(for chatID: Int64?) -> WatchedChannel? {
        guard let chatID else {
            return nil
        }
        return channels.first(where: { $0.chatID == chatID })
    }

    func contains(chatID: Int64) -> Bool {
        channels.contains(where: { $0.chatID == chatID })
    }

    func contains(username: String) -> Bool {
        let normalizedUsername = username.lowercased()
        return channels.contains(where: { $0.username.lowercased() == normalizedUsername })
    }

    func add(_ channel: WatchedChannel) throws {
        guard contains(chatID: channel.chatID) == false else {
            throw TelegramServiceError.invalidChannel
        }
        channels.append(channel)
        channels.sort { $0.title.localizedCaseInsensitiveCompare($1.title) == .orderedAscending }
        selectedChannelID = channel.chatID
    }

    func removeSelectedChannel() {
        guard let selectedChannelID else {
            return
        }

        channels.removeAll { $0.chatID == selectedChannelID }
        self.selectedChannelID = channels.first?.chatID
    }

    func update(_ channel: WatchedChannel) {
        guard let index = channels.firstIndex(where: { $0.chatID == channel.chatID }) else {
            return
        }
        channels[index] = channel
        channels.sort { $0.title.localizedCaseInsensitiveCompare($1.title) == .orderedAscending }
    }

    func reconcile(_ channel: WatchedChannel, previousChatID: Int64, previousUsername: String) {
        let normalizedUsername = previousUsername.lowercased()
        guard let index = channels.firstIndex(where: {
            $0.chatID == previousChatID || $0.username.lowercased() == normalizedUsername
        }) else {
            return
        }

        channels[index] = channel
        if selectedChannelID == previousChatID {
            selectedChannelID = channel.chatID
        }
        channels.sort { $0.title.localizedCaseInsensitiveCompare($1.title) == .orderedAscending }
    }

    func registerIncoming(_ post: UnreadPost) -> WatchedChannel? {
        guard post.sourceKind == .telegram else {
            return nil
        }
        guard let index = channels.firstIndex(where: { $0.chatID == post.chatID }) else {
            return nil
        }

        objectWillChange.send()
        let inserted = channels[index].registerIncoming(messageID: post.messageID)
        guard inserted else {
            return nil
        }
        return channels[index]
    }

    func markAsRead(chatID: Int64, messageID: Int64) {
        guard let index = channels.firstIndex(where: { $0.chatID == chatID }) else {
            return
        }
        objectWillChange.send()
        channels[index].markAsReadUpTo(messageID: messageID)
    }

    func markAsNotified(chatID: Int64, messageID: Int64) {
        guard let index = channels.firstIndex(where: { $0.chatID == chatID }) else {
            return
        }
        objectWillChange.send()
        channels[index].markAsNotified(messageID: messageID)
    }

    func applyUnreadState(chatID: Int64, lastReadInboxMessageID: Int64, unreadCount: Int) {
        guard let index = channels.firstIndex(where: { $0.chatID == chatID }) else {
            return
        }

        objectWillChange.send()
        channels[index].applyUnreadState(
            lastReadInboxMessageID: lastReadInboxMessageID,
            unreadCount: unreadCount
        )
    }
}
