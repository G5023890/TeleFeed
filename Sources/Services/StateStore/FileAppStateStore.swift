import Foundation

final class FileAppStateStore: StateStoreProtocol {
    private enum DirectoryName {
        static let current = "TeleFeed"
        static let legacy = "Telega"
    }

    private let fileManager: FileManager
    private let fileURL: URL
    private let encoder = JSONEncoder()
    private let decoder = JSONDecoder()
    private var lastKnownState: PersistedAppState?

    init(fileManager: FileManager = .default) {
        self.fileManager = fileManager
        let appSupport = fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        let directory = appSupport.appendingPathComponent(DirectoryName.current, isDirectory: true)
        let legacyDirectory = appSupport.appendingPathComponent(DirectoryName.legacy, isDirectory: true)
        try? fileManager.createDirectory(at: directory, withIntermediateDirectories: true)
        fileURL = directory.appendingPathComponent("state.json")
        let legacyFileURL = legacyDirectory.appendingPathComponent("state.json")
        if fileManager.fileExists(atPath: legacyFileURL.path), fileManager.fileExists(atPath: fileURL.path) == false {
            try? fileManager.createDirectory(at: directory, withIntermediateDirectories: true)
            try? fileManager.moveItem(at: legacyFileURL, to: fileURL)
        }
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
    }

    func load() -> PersistedAppState {
        guard
            let data = try? Data(contentsOf: fileURL),
            let state = try? decoder.decode(PersistedAppState.self, from: data)
        else {
            let state = normalized(loadLegacyState())
            lastKnownState = state
            return state
        }

        let normalizedState = normalized(state)
        lastKnownState = normalizedState
        return normalizedState
    }

    func save(_ state: PersistedAppState) throws {
        var state = state
        state.syncMetadata = metadataForSave(previous: lastKnownState, next: state)
        let normalizedState = normalized(state)
        let data = try encoder.encode(normalizedState)
        try data.write(to: fileURL, options: .atomic)
        lastKnownState = normalizedState
    }

    private func loadLegacyState() -> PersistedAppState {
        let appSupport = fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        let legacyFileURL = appSupport
            .appendingPathComponent(DirectoryName.legacy, isDirectory: true)
            .appendingPathComponent("state.json")

        guard
            let data = try? Data(contentsOf: legacyFileURL),
            let state = try? decoder.decode(PersistedAppState.self, from: data)
        else {
            return PersistedAppState()
        }

        return state
    }

    private func normalized(_ state: PersistedAppState) -> PersistedAppState {
        var normalizedState = state
        let deletedRSSKeys = Set(normalizedState.syncMetadata.rssRecords.compactMap { key, metadata in
            metadata.deletedAt == nil ? nil : key
        })
        normalizedState.watchedChannels = deduplicatedWatchedChannels(normalizedState.watchedChannels)
        normalizedState.rssFeeds = mergedDefaultRSSFeeds(with: normalizedState.rssFeeds, deletedKeys: deletedRSSKeys)
        normalizedState.syncMetadata = metadataIncludingActiveRecords(for: normalizedState)
        normalizedState.recentFeedPosts = NewsCachePolicy.retainedPosts(normalizedState.recentFeedPosts)
        normalizedState.readingAnchor = normalizedState.effectiveReadingAnchor
        if let anchorPostID = normalizedState.readingAnchor?.postID,
           normalizedState.recentFeedPosts.contains(where: { $0.id == anchorPostID }) == false {
            normalizedState.readingAnchor = nil
        }
        normalizedState.lastOpenedPost = normalizedState.readingAnchor?.lastOpenedPost

        if let selectedChannelID = normalizedState.selectedChannelID,
           normalizedState.watchedChannels.contains(where: { $0.chatID == selectedChannelID }) == false {
            normalizedState.selectedChannelID = normalizedState.watchedChannels.first?.chatID
        }

        if let selectedRSSFeedID = normalizedState.selectedRSSFeedID,
           normalizedState.rssFeeds.contains(where: { $0.id == selectedRSSFeedID }) == false {
            normalizedState.selectedRSSFeedID = normalizedState.rssFeeds.first?.id
        }

        return normalizedState
    }

    private func deduplicatedWatchedChannels(_ channels: [WatchedChannel]) -> [WatchedChannel] {
        var seenChatIDs = Set<Int64>()
        var uniqueChannels: [WatchedChannel] = []

        for channel in channels.reversed() {
            if seenChatIDs.insert(channel.chatID).inserted {
                uniqueChannels.append(channel)
            }
        }

        return uniqueChannels.reversed()
    }

    private func mergedDefaultRSSFeeds(with feeds: [RSSFeedSource], deletedKeys: Set<String>) -> [RSSFeedSource] {
        var mergedFeeds = feeds
        var normalizedURLs = Set(feeds.map { $0.normalizedURLString })

        for feed in DefaultRSSFeeds.feeds
            where deletedKeys.contains(feed.syncKey) == false
            && normalizedURLs.insert(feed.normalizedURLString).inserted {
            mergedFeeds.append(feed)
        }

        return mergedFeeds.sorted {
            $0.title.localizedCaseInsensitiveCompare($1.title) == .orderedAscending
        }
    }

    private func metadataForSave(previous: PersistedAppState?, next: PersistedAppState) -> AppSyncMetadata {
        let now = Date()
        var metadata = previous?.syncMetadata ?? next.syncMetadata

        let previousChannels = Dictionary(uniqueKeysWithValues: (previous?.watchedChannels ?? []).map { ($0.syncKey, $0) })
        let nextChannels = Dictionary(uniqueKeysWithValues: next.watchedChannels.map { ($0.syncKey, $0) })
        for (key, channel) in nextChannels {
            if previousChannels[key] != channel || metadata.channelRecords[key] == nil {
                metadata.channelRecords[key] = SyncRecordMetadata(updatedAt: now)
            }
        }
        for key in previousChannels.keys where nextChannels[key] == nil {
            metadata.channelRecords[key] = SyncRecordMetadata(updatedAt: now, deletedAt: now)
        }

        let previousFeeds = Dictionary(uniqueKeysWithValues: (previous?.rssFeeds ?? []).map { ($0.syncKey, $0) })
        let nextFeeds = Dictionary(uniqueKeysWithValues: next.rssFeeds.map { ($0.syncKey, $0) })
        for (key, feed) in nextFeeds {
            if previousFeeds[key] != feed || metadata.rssRecords[key] == nil {
                metadata.rssRecords[key] = SyncRecordMetadata(updatedAt: now)
            }
        }
        for key in previousFeeds.keys where nextFeeds[key] == nil {
            metadata.rssRecords[key] = SyncRecordMetadata(updatedAt: now, deletedAt: now)
        }

        return metadata
    }

    private func metadataIncludingActiveRecords(for state: PersistedAppState) -> AppSyncMetadata {
        var metadata = state.syncMetadata
        let now = Date()

        for channel in state.watchedChannels where metadata.channelRecords[channel.syncKey] == nil {
            metadata.channelRecords[channel.syncKey] = SyncRecordMetadata(updatedAt: now)
        }

        for feed in state.rssFeeds where metadata.rssRecords[feed.syncKey] == nil {
            metadata.rssRecords[feed.syncKey] = SyncRecordMetadata(updatedAt: now)
        }

        return metadata
    }
}
