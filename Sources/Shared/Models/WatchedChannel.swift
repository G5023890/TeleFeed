import Foundation

struct WatchedChannel: Codable, Hashable, Identifiable {
    var chatID: Int64
    var supergroupID: Int64?
    var title: String
    var username: String
    var unreadCount: Int
    var lastReadInboxMessageID: Int64
    var lastNotifiedMessageID: Int64?

    var id: Int64 { chatID }

    mutating func applyUnreadState(lastReadInboxMessageID: Int64, unreadCount: Int) {
        self.lastReadInboxMessageID = lastReadInboxMessageID
        self.unreadCount = max(0, unreadCount)
    }

    mutating func registerIncoming(messageID: Int64) -> Bool {
        guard messageID > lastReadInboxMessageID else {
            return false
        }

        unreadCount += 1
        return true
    }

    mutating func markAsReadUpTo(messageID: Int64) {
        guard messageID > lastReadInboxMessageID else {
            return
        }

        lastReadInboxMessageID = messageID
        unreadCount = max(0, unreadCount - 1)
    }

    mutating func markAsNotified(messageID: Int64) {
        lastNotifiedMessageID = max(lastNotifiedMessageID ?? 0, messageID)
    }

    func mergedIdentity(with resolved: WatchedChannel) -> WatchedChannel {
        WatchedChannel(
            chatID: resolved.chatID,
            supergroupID: resolved.supergroupID,
            title: resolved.title,
            username: resolved.username,
            unreadCount: resolved.unreadCount,
            lastReadInboxMessageID: resolved.lastReadInboxMessageID,
            lastNotifiedMessageID: lastNotifiedMessageID
        )
    }
}

struct PersistedAppState: Codable {
    var settings = AppSettings()
    var watchedChannels: [WatchedChannel] = []
    var selectedChannelID: Int64? = nil
}
