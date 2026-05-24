import XCTest
@testable import TeleFeed

@MainActor
final class SyncableAppStateTests: XCTestCase {
    func testMergedKeepsDifferentRecentPostsSortedByDate() {
        let channel = makeChannel(id: 100, title: "News")
        let older = makePost(channel: channel, messageID: 1, date: Date().addingTimeInterval(-200))
        let newer = makePost(channel: channel, messageID: 2, date: Date().addingTimeInterval(-100))

        let local = makeSyncable(channels: [channel], posts: [older])
        let remote = makeSyncable(channels: [channel], posts: [newer])

        let merged = local.merged(with: remote)

        XCTAssertEqual(merged.recentFeedPosts.map(\.id), [newer.id, older.id])
    }

    func testNewerRemoteReadingAnchorWinsAndIsValidated() {
        let channel = makeChannel(id: 100, title: "News")
        let localPost = makePost(channel: channel, messageID: 1, date: Date().addingTimeInterval(-200))
        let remotePost = makePost(channel: channel, messageID: 2, date: Date().addingTimeInterval(-100))
        var localState = makeState(channels: [channel], posts: [localPost])
        localState.readingAnchor = NewsReadingAnchor(post: localPost, readAt: Date(timeIntervalSince1970: 300))
        var remoteState = makeState(channels: [channel], posts: [remotePost])
        remoteState.readingAnchor = NewsReadingAnchor(post: remotePost, readAt: Date(timeIntervalSince1970: 400))

        let merged = SyncableAppState(local: localState).merged(with: SyncableAppState(local: remoteState))

        XCTAssertEqual(merged.readingAnchor?.postID, remotePost.id)
    }

    func testRecentPostsFromDeletedSourceAreDropped() {
        let channel = makeChannel(id: 100, title: "News")
        let post = makePost(channel: channel, messageID: 1, date: Date().addingTimeInterval(-100))
        var localState = makeState(channels: [channel], posts: [post])
        localState.syncMetadata.channelRecords[channel.syncKey] = SyncRecordMetadata(
            updatedAt: Date(timeIntervalSince1970: 100)
        )
        let local = SyncableAppState(local: localState)
        var remoteState = makeState(channels: [], posts: [])
        remoteState.syncMetadata.channelRecords[channel.syncKey] = SyncRecordMetadata(
            updatedAt: Date(timeIntervalSince1970: 500),
            deletedAt: Date(timeIntervalSince1970: 500)
        )

        let merged = local.merged(with: SyncableAppState(local: remoteState))

        XCTAssertTrue(merged.watchedChannels.isEmpty)
        XCTAssertTrue(merged.recentFeedPosts.isEmpty)
    }

    func testRecentPostsOlderThanRetentionAreDropped() {
        let channel = makeChannel(id: 100, title: "News")
        let freshPost = makePost(channel: channel, messageID: 1, date: Date().addingTimeInterval(-60 * 60))
        let stalePost = makePost(channel: channel, messageID: 2, date: Date().addingTimeInterval(-25 * 60 * 60))

        let state = makeSyncable(channels: [channel], posts: [freshPost, stalePost])

        XCTAssertEqual(state.recentFeedPosts.map(\.id), [freshPost.id])
    }

    func testTombstoneBeatsStaleLocalSource() {
        let channel = makeChannel(id: 100, title: "News")
        var localState = makeState(channels: [channel], posts: [])
        localState.syncMetadata.channelRecords[channel.syncKey] = SyncRecordMetadata(
            updatedAt: Date(timeIntervalSince1970: 100)
        )
        var remoteState = makeState(channels: [], posts: [])
        remoteState.syncMetadata.channelRecords[channel.syncKey] = SyncRecordMetadata(
            updatedAt: Date(timeIntervalSince1970: 200),
            deletedAt: Date(timeIntervalSince1970: 200)
        )

        let merged = SyncableAppState(local: localState).merged(with: SyncableAppState(local: remoteState))

        XCTAssertTrue(merged.watchedChannels.isEmpty)
    }

    func testPushMergeDoesNotDropRemoteOnlyRecentPosts() {
        let channel = makeChannel(id: 100, title: "News")
        let localPost = makePost(channel: channel, messageID: 1, date: Date().addingTimeInterval(-200))
        let remotePost = makePost(channel: channel, messageID: 2, date: Date().addingTimeInterval(-100))
        let localState = makeState(channels: [channel], posts: [localPost])
        let remoteState = makeSyncable(channels: [channel], posts: [remotePost])

        let merged = CloudSyncService.mergedStateForPush(local: localState, remote: remoteState)

        XCTAssertEqual(Set(merged.recentFeedPosts.map(\.id)), Set([localPost.id, remotePost.id]))
    }

    func testPushMergeReturnsMergedStateRatherThanOriginalLocalState() {
        let channel = makeChannel(id: 100, title: "News")
        let localPost = makePost(channel: channel, messageID: 1, date: Date().addingTimeInterval(-200))
        let remotePost = makePost(channel: channel, messageID: 2, date: Date().addingTimeInterval(-100))
        let localState = makeState(channels: [channel], posts: [localPost])
        let remoteState = makeSyncable(channels: [channel], posts: [remotePost])

        let merged = CloudSyncService.mergedStateForPush(local: localState, remote: remoteState)

        XCTAssertNotEqual(merged.recentFeedPosts.map(\.id), SyncableAppState(local: localState).recentFeedPosts.map(\.id))
        XCTAssertTrue(merged.recentFeedPosts.contains { $0.id == remotePost.id })
    }

    func testStrictFocusResolversReturnExactReadingAnchorPost() {
        let channel = makeChannel(id: 100, title: "News")
        let older = makePost(channel: channel, messageID: 1, date: Date().addingTimeInterval(-200))
        let newer = makePost(channel: channel, messageID: 2, date: Date().addingTimeInterval(-100))
        let anchor = NewsReadingAnchor(post: older, readAt: Date(timeIntervalSince1970: 300))

        XCTAssertEqual(MainViewModel.preferredSelectionPost(from: [newer, older], readingAnchor: anchor)?.id, older.id)
    }

    func testStrictFocusResolversDoNotFallbackToClosestPostWhenExactAnchorIsMissing() {
        let channel = makeChannel(id: 100, title: "News")
        let anchoredPost = makePost(channel: channel, messageID: 1, date: Date().addingTimeInterval(-200))
        let nearbyPost = makePost(channel: channel, messageID: 2, date: Date().addingTimeInterval(-199))
        let anchor = NewsReadingAnchor(post: anchoredPost, readAt: Date(timeIntervalSince1970: 300))

        XCTAssertNil(MainViewModel.preferredSelectionPost(from: [nearbyPost], readingAnchor: anchor))
    }

    private func makeSyncable(
        channels: [WatchedChannel],
        feeds: [RSSFeedSource] = [],
        posts: [UnreadPost]
    ) -> SyncableAppState {
        SyncableAppState(local: makeState(channels: channels, feeds: feeds, posts: posts))
    }

    private func makeState(
        channels: [WatchedChannel],
        feeds: [RSSFeedSource] = [],
        posts: [UnreadPost]
    ) -> PersistedAppState {
        var state = PersistedAppState()
        state.watchedChannels = channels
        state.rssFeeds = feeds
        state.selectedChannelID = channels.first?.chatID
        state.selectedRSSFeedID = feeds.first?.id
        state.recentFeedPosts = posts
        return state
    }

    private func makeChannel(id: Int64, title: String) -> WatchedChannel {
        WatchedChannel(
            chatID: id,
            supergroupID: nil,
            title: title,
            username: title.lowercased(),
            unreadCount: 0,
            lastReadInboxMessageID: 0,
            lastNotifiedMessageID: nil
        )
    }

    private func makePost(channel: WatchedChannel, messageID: Int64, date: Date) -> UnreadPost {
        UnreadPost(
            sourceKind: .telegram,
            sourceIdentifier: String(channel.chatID),
            chatID: channel.chatID,
            messageID: messageID,
            channelTitle: channel.displayTitle,
            author: nil,
            date: date,
            content: .text(body: "Post \(messageID)")
        )
    }
}
