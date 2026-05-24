import Foundation
#if canImport(WebKit)
import WebKit
#endif

enum NewsCachePolicy {
    static let retentionInterval: TimeInterval = 24 * 60 * 60

    static func isRetained(_ post: UnreadPost, now: Date = Date()) -> Bool {
        guard isSupported(post) else {
            return false
        }

        guard post.hasPublicationDate else {
            return true
        }

        return post.date >= now.addingTimeInterval(-retentionInterval)
    }

    static func isSupported(_ post: UnreadPost) -> Bool {
        if case .unsupported = post.content {
            return false
        }
        return true
    }

    static func sorted(_ posts: [UnreadPost]) -> [UnreadPost] {
        posts.sorted { lhs, rhs in
            if lhs.date == rhs.date {
                if lhs.id.sourceKind == rhs.id.sourceKind, lhs.id.sourceIdentifier == rhs.id.sourceIdentifier {
                    return lhs.messageID > rhs.messageID
                }
                if lhs.id.sourceKind != rhs.id.sourceKind {
                    return lhs.id.sourceKind.rawValue > rhs.id.sourceKind.rawValue
                }
                return lhs.id.sourceIdentifier > rhs.id.sourceIdentifier
            }
            return lhs.date > rhs.date
        }
    }

    static func retainedPosts(_ posts: [UnreadPost], now: Date = Date()) -> [UnreadPost] {
        sorted(posts.filter { isRetained($0, now: now) })
    }

    static func nextDailyCleanupDate(after date: Date = Date(), calendar: Calendar = .current) -> Date {
        calendar.nextDate(
            after: date,
            matching: DateComponents(hour: 0, minute: 5, second: 0),
            matchingPolicy: .nextTime
        ) ?? date.addingTimeInterval(retentionInterval)
    }
}

enum AppCacheCleaner {
    static func cleanDailyCaches() async {
        URLCache.shared.removeAllCachedResponses()
        await removeWebKitData()
        removeKnownFileCaches()
    }

    #if canImport(WebKit)
    @MainActor
    private static func removeWebKitData() async {
        let store = WKWebsiteDataStore.default()
        let types = WKWebsiteDataStore.allWebsiteDataTypes()
        await withCheckedContinuation { continuation in
            store.removeData(ofTypes: types, modifiedSince: .distantPast) {
                continuation.resume()
            }
        }
    }
    #else
    private static func removeWebKitData() async {}
    #endif

    private static func removeKnownFileCaches(fileManager: FileManager = .default) {
        guard let cachesDirectory = fileManager.urls(for: .cachesDirectory, in: .userDomainMask).first else {
            return
        }

        if let bundleIdentifier = Bundle.main.bundleIdentifier {
            removeContents(
                of: cachesDirectory.appendingPathComponent(bundleIdentifier, isDirectory: true),
                fileManager: fileManager
            )
        }

        removeContents(
            of: cachesDirectory
                .appendingPathComponent("TeleFeed", isDirectory: true)
                .appendingPathComponent("TDLibTempMedia", isDirectory: true),
            fileManager: fileManager
        )
    }

    private static func removeContents(of directory: URL, fileManager: FileManager) {
        guard let children = try? fileManager.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil) else {
            return
        }

        for child in children {
            try? fileManager.removeItem(at: child)
        }
    }
}

struct WatchedChannel: Codable, Hashable, Identifiable {
    var chatID: Int64
    var supergroupID: Int64?
    var title: String
    var username: String
    var unreadCount: Int
    var lastReadInboxMessageID: Int64
    var lastNotifiedMessageID: Int64?

    var id: Int64 { chatID }

    var syncKey: String {
        if chatID != 0 {
            return "chat:\(chatID)"
        }

        return "username:\(username.trimmingCharacters(in: .whitespacesAndNewlines).lowercased())"
    }

    var displayTitle: String {
        let trimmedTitle = title.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmedTitle.isEmpty == false {
            return trimmedTitle
        }

        let trimmedUsername = username.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmedUsername.isEmpty == false {
            return "@\(trimmedUsername)"
        }

        return L10n.tr("channels.untitled")
    }

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
    var rssFeeds: [RSSFeedSource] = []
    var selectedChannelID: Int64? = nil
    var selectedRSSFeedID: String? = nil
    var feedDisplayMode: FeedViewModel.DisplayMode? = nil
    var lastOpenedPost: LastOpenedPostState? = nil
    var readingAnchor: NewsReadingAnchor? = nil
    var unreadColumnWidth: Double? = nil
    var windowFrame: WindowFrameState? = nil
    var recentFeedPosts: [UnreadPost] = []
    var readPostIDs: [UnreadPostIdentity] = []
    var readPostRetentionDates: [UnreadPostIdentity: Date] = [:]
    var syncMetadata = AppSyncMetadata()
}

extension PersistedAppState {
    var syncedSources: SyncedNewsSources {
        SyncedNewsSources(
            telegramChannels: watchedChannels,
            rssFeeds: rssFeeds,
            selectedTelegramChannelID: selectedChannelID,
            selectedRSSFeedID: selectedRSSFeedID,
            metadata: syncMetadata
        )
    }
}

struct SyncedNewsSources: Codable, Hashable {
    var telegramChannels: [WatchedChannel] = []
    var rssFeeds: [RSSFeedSource] = []
    var selectedTelegramChannelID: Int64?
    var selectedRSSFeedID: String?
    var metadata = AppSyncMetadata()

    var statusSummary: String {
        "Telegram: \(telegramChannels.count), RSS: \(rssFeeds.count)"
    }

    init() {}

    init(
        telegramChannels: [WatchedChannel],
        rssFeeds: [RSSFeedSource],
        selectedTelegramChannelID: Int64?,
        selectedRSSFeedID: String?,
        metadata: AppSyncMetadata
    ) {
        self.telegramChannels = telegramChannels
        self.rssFeeds = rssFeeds
        self.selectedTelegramChannelID = selectedTelegramChannelID
        self.selectedRSSFeedID = selectedRSSFeedID
        self.metadata = metadata
    }
}

struct LastOpenedPostState: Codable, Hashable {
    var postID: UnreadPostIdentity
    var postDate: Date?
    var openedAt: Date

    init(postID: UnreadPostIdentity, postDate: Date? = nil, openedAt: Date) {
        self.postID = postID
        self.postDate = postDate
        self.openedAt = openedAt
    }
}

struct NewsReadingAnchor: Codable, Hashable {
    var postID: UnreadPostIdentity?
    var publishedAt: Date
    var readAt: Date
    var sourceKind: UnreadPostSourceKind?
    var sourceIdentifier: String?

    init(
        postID: UnreadPostIdentity?,
        publishedAt: Date,
        readAt: Date,
        sourceKind: UnreadPostSourceKind?,
        sourceIdentifier: String?
    ) {
        self.postID = postID
        self.publishedAt = publishedAt
        self.readAt = readAt
        self.sourceKind = sourceKind
        self.sourceIdentifier = sourceIdentifier
    }

    init(post: UnreadPost, readAt: Date) {
        self.init(
            postID: post.id,
            publishedAt: post.date,
            readAt: readAt,
            sourceKind: post.sourceKind,
            sourceIdentifier: post.sourceIdentifier
        )
    }

    init(lastOpenedPost: LastOpenedPostState, fallbackPost: UnreadPost? = nil) {
        let post = fallbackPost?.id == lastOpenedPost.postID ? fallbackPost : nil
        self.init(
            postID: lastOpenedPost.postID,
            publishedAt: lastOpenedPost.postDate ?? post?.date ?? lastOpenedPost.openedAt,
            readAt: lastOpenedPost.openedAt,
            sourceKind: lastOpenedPost.postID.sourceKind,
            sourceIdentifier: lastOpenedPost.postID.sourceIdentifier
        )
    }

    var lastOpenedPost: LastOpenedPostState? {
        guard let postID else {
            return nil
        }

        return LastOpenedPostState(
            postID: postID,
            postDate: publishedAt,
            openedAt: readAt
        )
    }

    func isAnchoredToSource(kind: UnreadPostSourceKind, identifier: String) -> Bool {
        if sourceKind == kind, sourceIdentifier == identifier {
            return true
        }

        return postID?.sourceKind == kind && postID?.sourceIdentifier == identifier
    }
}

extension PersistedAppState {
    var effectiveReadingAnchor: NewsReadingAnchor? {
        if let readingAnchor {
            return readingAnchor
        }

        guard let lastOpenedPost else {
            return nil
        }

        let fallbackPost = recentFeedPosts.first { $0.id == lastOpenedPost.postID }
        return NewsReadingAnchor(lastOpenedPost: lastOpenedPost, fallbackPost: fallbackPost)
    }
}

struct AppSyncMetadata: Codable, Hashable {
    var channelRecords: [String: SyncRecordMetadata] = [:]
    var rssRecords: [String: SyncRecordMetadata] = [:]
}

struct SyncRecordMetadata: Codable, Hashable {
    var updatedAt: Date
    var deletedAt: Date?

    init(updatedAt: Date, deletedAt: Date? = nil) {
        self.updatedAt = updatedAt
        self.deletedAt = deletedAt
    }
}
