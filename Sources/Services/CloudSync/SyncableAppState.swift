import Foundation

struct SyncableAppState: Codable, Hashable {
    static let currentSchemaVersion = 2

    var schemaVersion = currentSchemaVersion
    var watchedChannels: [WatchedChannel] = []
    var rssFeeds: [RSSFeedSource] = []
    var selectedChannelID: Int64?
    var selectedRSSFeedID: String?
    var feedDisplayMode: FeedViewModel.DisplayMode?
    var lastOpenedPost: LastOpenedPostState?
    var readingAnchor: NewsReadingAnchor?
    var recentFeedPosts: [UnreadPost] = []
    var readPostIDs: [UnreadPostIdentity] = []
    var syncMetadata = AppSyncMetadata()
    var syncedSources: SyncedNewsSources?

    init() {}

    private enum CodingKeys: String, CodingKey {
        case schemaVersion
        case watchedChannels
        case rssFeeds
        case selectedChannelID
        case selectedRSSFeedID
        case feedDisplayMode
        case lastOpenedPost
        case readingAnchor
        case recentFeedPosts
        case readPostIDs
        case syncMetadata
        case syncedSources
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        schemaVersion = try container.decodeIfPresent(Int.self, forKey: .schemaVersion) ?? 1
        watchedChannels = try container.decodeIfPresent([WatchedChannel].self, forKey: .watchedChannels) ?? []
        rssFeeds = try container.decodeIfPresent([RSSFeedSource].self, forKey: .rssFeeds) ?? []
        selectedChannelID = try container.decodeIfPresent(Int64.self, forKey: .selectedChannelID)
        selectedRSSFeedID = try container.decodeIfPresent(String.self, forKey: .selectedRSSFeedID)
        feedDisplayMode = try container.decodeIfPresent(FeedViewModel.DisplayMode.self, forKey: .feedDisplayMode)
        lastOpenedPost = try container.decodeIfPresent(LastOpenedPostState.self, forKey: .lastOpenedPost)
        readingAnchor = try container.decodeIfPresent(NewsReadingAnchor.self, forKey: .readingAnchor)
        recentFeedPosts = try container.decodeIfPresent([UnreadPost].self, forKey: .recentFeedPosts) ?? []
        readPostIDs = try container.decodeIfPresent([UnreadPostIdentity].self, forKey: .readPostIDs) ?? []
        syncMetadata = try container.decodeIfPresent(AppSyncMetadata.self, forKey: .syncMetadata) ?? AppSyncMetadata()
        syncedSources = try container.decodeIfPresent(SyncedNewsSources.self, forKey: .syncedSources)
    }

    init(local state: PersistedAppState) {
        schemaVersion = Self.currentSchemaVersion
        watchedChannels = state.watchedChannels
        rssFeeds = state.rssFeeds
        selectedChannelID = state.selectedChannelID
        selectedRSSFeedID = state.selectedRSSFeedID
        feedDisplayMode = nil
        readingAnchor = Self.resolvedReadingAnchor(in: state)
        lastOpenedPost = readingAnchor?.lastOpenedPost
        recentFeedPosts = Self.filteredRecentPosts(
            state.recentFeedPosts,
            channels: state.watchedChannels,
            feeds: state.rssFeeds
        )
        readPostIDs = []
        syncMetadata = state.syncMetadata.withActiveDefaults(
            channels: state.watchedChannels,
            feeds: state.rssFeeds
        )
        syncedSources = SyncedNewsSources(
            telegramChannels: watchedChannels,
            rssFeeds: rssFeeds,
            selectedTelegramChannelID: selectedChannelID,
            selectedRSSFeedID: selectedRSSFeedID,
            metadata: syncMetadata
        )
    }

    func applied(to local: PersistedAppState) -> PersistedAppState {
        var state = local
        let sources = effectiveSources
        state.watchedChannels = sources.telegramChannels.sorted {
            $0.displayTitle.localizedCaseInsensitiveCompare($1.displayTitle) == .orderedAscending
        }
        state.rssFeeds = sources.rssFeeds.sorted {
            $0.title.localizedCaseInsensitiveCompare($1.title) == .orderedAscending
        }
        state.selectedChannelID = sources.selectedTelegramChannelID.flatMap { selectedID in
            state.watchedChannels.contains(where: { $0.chatID == selectedID }) ? selectedID : nil
        } ?? state.watchedChannels.first?.chatID
        state.selectedRSSFeedID = sources.selectedRSSFeedID.flatMap { selectedID in
            state.rssFeeds.contains(where: { $0.id == selectedID }) ? selectedID : nil
        } ?? state.rssFeeds.first?.id
        state.feedDisplayMode = nil
        state.readingAnchor = Self.validatedReadingAnchor(
            effectiveReadingAnchor,
            channels: state.watchedChannels,
            feeds: state.rssFeeds
        )
        state.lastOpenedPost = state.readingAnchor?.lastOpenedPost
        state.syncMetadata = sources.metadata.withActiveDefaults(
            channels: state.watchedChannels,
            feeds: state.rssFeeds
        )
        state.readPostIDs = []
        state.recentFeedPosts = Self.filteredRecentPosts(
            recentFeedPosts,
            channels: state.watchedChannels,
            feeds: state.rssFeeds
        )
        return state
    }

    func merged(with remote: SyncableAppState) -> SyncableAppState {
        var merged = self
        let localSources = effectiveSources
        let remoteSources = remote.effectiveSources
        merged.schemaVersion = max(schemaVersion, remote.schemaVersion)
        merged.syncMetadata = localSources.metadata.merged(with: remoteSources.metadata)
        merged.watchedChannels = Self.mergeChannels(
            local: localSources.telegramChannels,
            remote: remoteSources.telegramChannels,
            metadata: merged.syncMetadata
        )
        merged.rssFeeds = Self.mergeFeeds(
            local: localSources.rssFeeds,
            remote: remoteSources.rssFeeds,
            metadata: merged.syncMetadata
        )
        merged.readPostIDs = []
        merged.readingAnchor = Self.readingAnchor(
            local: effectiveReadingAnchor,
            remote: remote.effectiveReadingAnchor,
            channels: merged.watchedChannels,
            feeds: merged.rssFeeds
        )
        merged.lastOpenedPost = merged.readingAnchor?.lastOpenedPost
        merged.recentFeedPosts = Self.mergeRecentPosts(
            local: recentFeedPosts,
            remote: remote.recentFeedPosts,
            channels: merged.watchedChannels,
            feeds: merged.rssFeeds
        )
        merged.selectedChannelID = Self.selectedChannelID(
            local: localSources.selectedTelegramChannelID,
            remote: remoteSources.selectedTelegramChannelID,
            channels: merged.watchedChannels,
            metadata: merged.syncMetadata
        )
        merged.selectedRSSFeedID = Self.selectedRSSFeedID(
            local: localSources.selectedRSSFeedID,
            remote: remoteSources.selectedRSSFeedID,
            feeds: merged.rssFeeds,
            metadata: merged.syncMetadata
        )
        merged.feedDisplayMode = nil
        merged.syncMetadata = merged.syncMetadata.withActiveDefaults(
            channels: merged.watchedChannels,
            feeds: merged.rssFeeds
        )
        merged.syncedSources = SyncedNewsSources(
            telegramChannels: merged.watchedChannels,
            rssFeeds: merged.rssFeeds,
            selectedTelegramChannelID: merged.selectedChannelID,
            selectedRSSFeedID: merged.selectedRSSFeedID,
            metadata: merged.syncMetadata
        )
        return merged
    }

    var sourceStatusSummary: String {
        effectiveSources.statusSummary
    }

    private var effectiveSources: SyncedNewsSources {
        syncedSources ?? SyncedNewsSources(
            telegramChannels: watchedChannels,
            rssFeeds: rssFeeds,
            selectedTelegramChannelID: selectedChannelID,
            selectedRSSFeedID: selectedRSSFeedID,
            metadata: syncMetadata
        )
    }

    private var effectiveReadingAnchor: NewsReadingAnchor? {
        if let readingAnchor {
            return readingAnchor
        }

        return lastOpenedPost.map { NewsReadingAnchor(lastOpenedPost: $0) }
    }

    private static func mergeChannels(
        local: [WatchedChannel],
        remote: [WatchedChannel],
        metadata: AppSyncMetadata
    ) -> [WatchedChannel] {
        var merged = local
        for channel in remote {
            if let index = merged.firstIndex(where: { channelsMatch($0, channel) }) {
                let current = merged[index]
                if metadata.updatedAt(forChannel: channel) >= metadata.updatedAt(forChannel: current) {
                    merged[index] = channel
                }
            } else {
                merged.append(channel)
            }
        }

        return merged
            .filter { metadata.isChannelDeleted($0) == false }
            .sorted { $0.displayTitle.localizedCaseInsensitiveCompare($1.displayTitle) == .orderedAscending }
    }

    private static func mergeFeeds(
        local: [RSSFeedSource],
        remote: [RSSFeedSource],
        metadata: AppSyncMetadata
    ) -> [RSSFeedSource] {
        var merged = local
        for feed in remote {
            if let index = merged.firstIndex(where: { $0.syncKey == feed.syncKey }) {
                let current = merged[index]
                if metadata.updatedAt(forFeed: feed) >= metadata.updatedAt(forFeed: current) {
                    merged[index] = feed
                }
            } else {
                merged.append(feed)
            }
        }

        return merged
            .filter { metadata.isFeedDeleted($0) == false }
            .sorted { $0.title.localizedCaseInsensitiveCompare($1.title) == .orderedAscending }
    }

    private static func channelsMatch(_ lhs: WatchedChannel, _ rhs: WatchedChannel) -> Bool {
        if lhs.chatID == rhs.chatID {
            return true
        }
        let lhsUsername = lhs.username.trimmingCharacters(in: .whitespacesAndNewlines)
        let rhsUsername = rhs.username.trimmingCharacters(in: .whitespacesAndNewlines)
        return lhsUsername.isEmpty == false && lhsUsername.caseInsensitiveCompare(rhsUsername) == .orderedSame
    }

    private static func selectedChannelID(
        local: Int64?,
        remote: Int64?,
        channels: [WatchedChannel],
        metadata: AppSyncMetadata
    ) -> Int64? {
        let localDate = local.flatMap { id in channels.first(where: { $0.chatID == id }) }.map(metadata.updatedAt(forChannel:)) ?? .distantPast
        let remoteDate = remote.flatMap { id in channels.first(where: { $0.chatID == id }) }.map(metadata.updatedAt(forChannel:)) ?? .distantPast
        let selected = remoteDate >= localDate ? remote : local
        if let selected, channels.contains(where: { $0.chatID == selected }) {
            return selected
        }
        return channels.first?.chatID
    }

    private static func selectedRSSFeedID(
        local: String?,
        remote: String?,
        feeds: [RSSFeedSource],
        metadata: AppSyncMetadata
    ) -> String? {
        let localDate = local.flatMap { id in feeds.first(where: { $0.id == id }) }.map(metadata.updatedAt(forFeed:)) ?? .distantPast
        let remoteDate = remote.flatMap { id in feeds.first(where: { $0.id == id }) }.map(metadata.updatedAt(forFeed:)) ?? .distantPast
        let selected = remoteDate >= localDate ? remote : local
        if let selected, feeds.contains(where: { $0.id == selected }) {
            return selected
        }
        return feeds.first?.id
    }

    private static func readingAnchor(
        local: NewsReadingAnchor?,
        remote: NewsReadingAnchor?,
        channels: [WatchedChannel],
        feeds: [RSSFeedSource]
    ) -> NewsReadingAnchor? {
        let selected: NewsReadingAnchor?
        switch (local, remote) {
        case (.some(let local), .some(let remote)):
            selected = remote.readAt >= local.readAt ? remote : local
        case (.some(let local), .none):
            selected = local
        case (.none, .some(let remote)):
            selected = remote
        case (.none, .none):
            selected = nil
        }

        return validatedReadingAnchor(selected, channels: channels, feeds: feeds)
    }

    private static func mergeRecentPosts(
        local: [UnreadPost],
        remote: [UnreadPost],
        channels: [WatchedChannel],
        feeds: [RSSFeedSource]
    ) -> [UnreadPost] {
        var mergedByID: [UnreadPostIdentity: UnreadPost] = [:]

        for post in filteredRecentPosts(local, channels: channels, feeds: feeds) {
            mergedByID[post.id] = post
        }

        for post in filteredRecentPosts(remote, channels: channels, feeds: feeds) {
            if let current = mergedByID[post.id] {
                mergedByID[post.id] = preferredPost(current, post)
            } else {
                mergedByID[post.id] = post
            }
        }

        return sortedRecentPosts(Array(mergedByID.values))
    }

    private static func filteredRecentPosts(
        _ posts: [UnreadPost],
        channels: [WatchedChannel],
        feeds: [RSSFeedSource]
    ) -> [UnreadPost] {
        let channelIDs = Set(channels.map(\.chatID))
        let feedIDs = Set(feeds.map(\.id))
        return sortedRecentPosts(posts.filter { post in
            guard NewsCachePolicy.isRetained(post) else {
                return false
            }

            switch post.sourceKind {
            case .telegram:
                return channelIDs.contains(post.chatID)
            case .rss:
                return feedIDs.contains(post.sourceIdentifier)
            }
        })
    }

    private static func sortedRecentPosts(_ posts: [UnreadPost]) -> [UnreadPost] {
        NewsCachePolicy.retainedPosts(posts)
    }

    private static func preferredPost(_ lhs: UnreadPost, _ rhs: UnreadPost) -> UnreadPost {
        if richnessScore(rhs) != richnessScore(lhs) {
            return richnessScore(rhs) > richnessScore(lhs) ? rhs : lhs
        }

        if rhs.date != lhs.date {
            return rhs.date > lhs.date ? rhs : lhs
        }

        return rhs
    }

    private static func richnessScore(_ post: UnreadPost) -> Int {
        var score = 0
        if post.channelTitle.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false {
            score += 2
        }
        if let author = post.author,
           author.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false {
            score += 1
        }
        if post.articleURL != nil {
            score += 1
        }
        score += min(post.summary.count / 80, 4)
        return score
    }

    private static func isSupported(_ post: UnreadPost) -> Bool {
        if case .unsupported = post.content {
            return false
        }
        return true
    }

    private static func resolvedReadingAnchor(in state: PersistedAppState) -> NewsReadingAnchor? {
        state.effectiveReadingAnchor
    }

    private static func validatedReadingAnchor(
        _ readingAnchor: NewsReadingAnchor?,
        channels: [WatchedChannel],
        feeds: [RSSFeedSource]
    ) -> NewsReadingAnchor? {
        guard let readingAnchor else {
            return nil
        }

        if readingAnchor.publishedAt < Date().addingTimeInterval(-NewsCachePolicy.retentionInterval) {
            return nil
        }

        let sourceKind = readingAnchor.sourceKind ?? readingAnchor.postID?.sourceKind
        let sourceIdentifier = readingAnchor.sourceIdentifier ?? readingAnchor.postID?.sourceIdentifier
        guard let sourceKind, let sourceIdentifier else {
            return readingAnchor
        }

        switch sourceKind {
        case .telegram:
            return channels.contains { String($0.chatID) == sourceIdentifier } ? readingAnchor : nil
        case .rss:
            return feeds.contains { $0.id == sourceIdentifier } ? readingAnchor : nil
        }
    }
}

extension AppSyncMetadata {
    func merged(with other: AppSyncMetadata) -> AppSyncMetadata {
        AppSyncMetadata(
            channelRecords: mergedRecords(channelRecords, other.channelRecords),
            rssRecords: mergedRecords(rssRecords, other.rssRecords)
        )
    }

    func withActiveDefaults(channels: [WatchedChannel], feeds: [RSSFeedSource]) -> AppSyncMetadata {
        var metadata = self
        let now = Date()
        for channel in channels where metadata.channelRecords[channel.syncKey] == nil {
            metadata.channelRecords[channel.syncKey] = SyncRecordMetadata(updatedAt: now)
        }
        for feed in feeds where metadata.rssRecords[feed.syncKey] == nil {
            metadata.rssRecords[feed.syncKey] = SyncRecordMetadata(updatedAt: now)
        }
        return metadata
    }

    func updatedAt(forChannel channel: WatchedChannel) -> Date {
        channelRecords[channel.syncKey]?.updatedAt ?? .distantPast
    }

    func updatedAt(forFeed feed: RSSFeedSource) -> Date {
        rssRecords[feed.syncKey]?.updatedAt ?? .distantPast
    }

    func isChannelDeleted(_ channel: WatchedChannel) -> Bool {
        guard let metadata = channelRecords[channel.syncKey], let deletedAt = metadata.deletedAt else {
            return false
        }
        return deletedAt >= metadata.updatedAt
    }

    func isFeedDeleted(_ feed: RSSFeedSource) -> Bool {
        guard let metadata = rssRecords[feed.syncKey], let deletedAt = metadata.deletedAt else {
            return false
        }
        return deletedAt >= metadata.updatedAt
    }

    private func mergedRecords(
        _ lhs: [String: SyncRecordMetadata],
        _ rhs: [String: SyncRecordMetadata]
    ) -> [String: SyncRecordMetadata] {
        var merged = lhs
        for (key, value) in rhs {
            guard let current = merged[key] else {
                merged[key] = value
                continue
            }
            merged[key] = value.updatedAt >= current.updatedAt ? value : current
        }
        return merged
    }
}

private extension Array where Element == UnreadPostIdentity {
    func sortedForSync() -> [UnreadPostIdentity] {
        sorted { lhs, rhs in
            if lhs.sourceKind == rhs.sourceKind, lhs.sourceIdentifier == rhs.sourceIdentifier {
                return lhs.messageID > rhs.messageID
            }
            if lhs.sourceKind != rhs.sourceKind {
                return lhs.sourceKind.rawValue < rhs.sourceKind.rawValue
            }
            return lhs.sourceIdentifier < rhs.sourceIdentifier
        }
    }
}
