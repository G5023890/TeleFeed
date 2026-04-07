import Foundation
import ServiceManagement
import OSLog
import SwiftUI

@MainActor
final class MainViewModel: ObservableObject {
    private static let logger = Logger(subsystem: "com.codex.TeleFeed", category: "MainViewModel")
    private static let defaultUnreadColumnWidth: CGFloat = 420

    @Published var authViewModel: AuthViewModel
    @Published var channelsViewModel: ChannelsViewModel
    @Published var rssFeedsViewModel: RSSFeedsViewModel
    @Published var feedViewModel = FeedViewModel()
    @Published var viewerViewModel: ViewerViewModel
    @Published var settings: AppSettings
    @Published var connectionStatus: TelegramConnectionStatus = .offline
    @Published var viewerPresentedPost: UnreadPost?
    @Published var selectedUnreadPostID: UnreadPostIdentity?
    @Published var detailPresentation: DetailPresentation = .post
    @Published var isSidebarPresented = false
    var unreadColumnWidth: CGFloat
    var windowFrame: WindowFrameState?

    var showWindow: (() -> Void)?

    private let stateStore: StateStoreProtocol
    private let telegramService: TelegramServiceProtocol
    private let rssService: RSSServiceProtocol
    private let notificationService: NotificationServiceProtocol
    private let readFeedRetentionInterval: TimeInterval = 24 * 60 * 60
    private let rssPollingInterval: TimeInterval = 10 * 60
    private var channelNavigationStates: [Int64: ChannelUnreadState] = [:]
    private var sessionFeedPosts: [UnreadPostIdentity: UnreadPost] = [:]
    private var rssPollingTask: Task<Void, Never>?
    private var isRefreshingTelegramSources = false
    private var isRefreshingRSSFeeds = false
    let readerViewModel: ReaderViewModel

    init(
        stateStore: StateStoreProtocol,
        telegramService: TelegramServiceProtocol,
        rssService: RSSServiceProtocol,
        notificationService: NotificationServiceProtocol,
        readerService: ReaderServiceProtocol,
        translationService: TranslationServiceProtocol
    ) {
        let state = stateStore.load()
        self.stateStore = stateStore
        self.telegramService = telegramService
        self.rssService = rssService
        self.notificationService = notificationService
        self.viewerViewModel = ViewerViewModel(translationService: translationService)
        self.readerViewModel = ReaderViewModel(
            readerService: readerService,
            translationService: translationService
        )
        self.settings = state.settings
        self.unreadColumnWidth = Self.defaultUnreadColumnWidth
        self.windowFrame = state.windowFrame
        self.authViewModel = AuthViewModel()
        self.channelsViewModel = ChannelsViewModel(
            channels: state.watchedChannels,
            selectedChannelID: state.selectedChannelID
        )
        let hasRetainedRSSPosts = state.recentFeedPosts.contains { $0.sourceKind == .rss }
        let loadedRSSFeeds = hasRetainedRSSPosts ? state.rssFeeds : state.rssFeeds.map { $0.resettingCursor() }
        self.rssFeedsViewModel = RSSFeedsViewModel(
            feeds: loadedRSSFeeds,
            selectedFeedID: state.selectedRSSFeedID
        )
        self.feedViewModel = FeedViewModel(displayMode: state.feedDisplayMode ?? .all)
        if hasRetainedRSSPosts == false, state.rssFeeds.isEmpty == false {
            Self.logger.debug("RSS cache is empty, forcing a fresh backfill on startup")
        }
        let retainedPosts = Self.sortedSessionPosts(Self.prunedSessionPosts(
            state.recentFeedPosts,
            readIDs: Set(state.readPostIDs),
            readRetentionInterval: readFeedRetentionInterval
        ))
        let normalizedRetainedPosts = retainedPosts.map { post -> UnreadPost in
            guard
                post.sourceKind == .telegram,
                post.channelTitle.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
                let watchedChannel = self.channelsViewModel.channel(for: post.chatID)
            else {
                return post
            }

            return post.updatingChannelTitle(watchedChannel.displayTitle)
        }
        self.sessionFeedPosts = Dictionary(uniqueKeysWithValues: normalizedRetainedPosts.map { ($0.id, $0) })
        self.feedViewModel.readPostIDs = Set(state.readPostIDs)
        self.feedViewModel.setPosts(normalizedRetainedPosts)
        self.selectedUnreadPostID = Self.initialSelectionID(
            from: normalizedRetainedPosts,
            readIDs: self.feedViewModel.readPostIDs
        )
    }

    func start() async {
        Self.logger.info("MainViewModel.start begin")
        let saved = await telegramService.loadSavedCredentials()
        authViewModel.apiID = saved?.apiID ?? ""
        authViewModel.apiHash = saved?.apiHash ?? ""
        authViewModel.debugMessage = "App started"

        telegramService.onEvent = { [weak self] event in
            self?.handle(event: event)
        }

        notificationService.onOpenChannel = { [weak self] route in
            self?.openChannel(chatID: route.chatID)
        }

        await notificationService.requestAuthorization()
        syncLaunchAtLogin()
        startRSSPolling()
        await telegramService.start()
        await synchronizeAuthState()
        kickoffBackgroundRefresh()
    }

    func shutdown() async {
        rssPollingTask?.cancel()
        rssPollingTask = nil
        persistState()
        await telegramService.shutdown()
    }

    func openHome() {
        if channelsViewModel.selectedChannelID == nil {
            channelsViewModel.selectedChannelID = channelsViewModel.channels.first?.chatID
            persistState()
        }
        showWindow?()
        refreshAggregatedFeedPresentation()
        kickoffBackgroundRefresh()
    }

    func toggleSidebar() {
        isSidebarPresented.toggle()
    }

    @discardableResult
    func closeSidebar() -> Bool {
        guard isSidebarPresented else {
            return false
        }

        isSidebarPresented = false
        return true
    }

    func selectChannel(_ chatID: Int64?) {
        channelsViewModel.selectedChannelID = chatID
        isSidebarPresented = false
        persistState()
    }

    func selectRSSFeed(_ feedID: String?) {
        rssFeedsViewModel.selectedFeedID = feedID
        isSidebarPresented = false
        persistState()
    }

    func addChannel() {
        let rawInput = channelsViewModel.channelInput
        channelsViewModel.errorMessage = nil

        Task {
            do {
                let channel = try await telegramService.resolveChannel(from: rawInput)
                guard
                    channelsViewModel.contains(chatID: channel.chatID) == false,
                    channelsViewModel.contains(username: channel.username) == false
                else {
                    throw TelegramServiceError.invalidChannel
                }
                try channelsViewModel.add(channel)
                channelsViewModel.channelInput = ""
                isSidebarPresented = false
                persistState()
                await syncWatchedChannels()
                kickoffBackgroundRefresh()
            } catch {
                channelsViewModel.errorMessage = error.localizedDescription == TelegramServiceError.invalidChannel.localizedDescription
                    ? L10n.tr("channels.invalid")
                    : error.localizedDescription
            }
        }
    }

    func addRSSFeed() {
        let rawInput = rssFeedsViewModel.feedInput
        rssFeedsViewModel.errorMessage = nil

        Task {
            do {
                let feed = try await rssService.resolveFeed(from: rawInput)
                try rssFeedsViewModel.add(feed)
                rssFeedsViewModel.feedInput = ""
                isSidebarPresented = false
                persistState()
                kickoffBackgroundRefresh()
            } catch {
                rssFeedsViewModel.errorMessage = error.localizedDescription
            }
        }
    }

    func removeSelectedChannel() {
        guard let removedChannelID = channelsViewModel.selectedChannelID else {
            return
        }

        channelsViewModel.removeSelectedChannel()
        channelNavigationStates.removeValue(forKey: removedChannelID)
        removeSessionPosts(for: removedChannelID)

        persistState()
        Task {
            await syncWatchedChannels()
            kickoffBackgroundRefresh()
        }
    }

    func removeSelectedRSSFeed() {
        guard let removedFeed = rssFeedsViewModel.removeSelectedFeed() else {
            return
        }

        removeSessionPosts(for: removedFeed)
        persistState()
        refreshAggregatedFeedPresentation()
    }

    func refreshSelectedChannel() async {
        await refreshAllSources(showLoading: true)
    }

    func openPost(_ post: UnreadPost) {
        selectUnreadPost(post.id)
    }

    func openReader(for post: UnreadPost) {
        guard post.articleURL != nil else {
            return
        }

        withAnimation(.snappy(duration: 0.28)) {
            if feedViewModel.isUnread(post) {
                markPostAsRead(post)
            }
            detailPresentation = .reader
            readerViewModel.open(post: post)
        }
    }

    func toggleReadState(for post: UnreadPost) {
        if feedViewModel.isUnread(post) {
            markPostAsRead(post)
        } else {
            feedViewModel.markUnread(identity: post.id)
            persistState()
        }
    }

    func selectUnreadPost(_ postID: UnreadPostIdentity?) {
        if let postID,
           selectedUnreadPostID == postID,
           viewerPresentedPost?.id == postID {
            return
        }

        let previousPost = viewerPresentedPost
        guard let postID else {
            withAnimation(.snappy(duration: 0.28)) {
                closeViewer()
            }
            return
        }

        guard let post = feedViewModel.posts.first(where: { $0.id == postID }) else {
            withAnimation(.snappy(duration: 0.28)) {
                closeViewer()
            }
            return
        }

        // Mark the previous post as read only when the user explicitly moves
        // to another news item.
        if let previousPost, previousPost.id != postID {
            markPostAsRead(previousPost)
        }

        present(post, updateSelection: true)
    }

    func closeReader() {
        withAnimation(.snappy(duration: 0.28)) {
            readerViewModel.dismiss()
            detailPresentation = .post
        }
    }

    func closeViewer() {
        withAnimation(.snappy(duration: 0.28)) {
            readerViewModel.dismiss()
            detailPresentation = .post
            viewerPresentedPost = nil
            viewerViewModel.dismiss()
        }
    }

    private func markPostAsRead(_ post: UnreadPost) {
        if post.sourceKind == .telegram {
            channelsViewModel.markAsRead(chatID: post.chatID, messageID: post.messageID)
            notificationService.removeNotification(chatID: post.chatID, messageID: post.messageID)
        }
        feedViewModel.markRead(identity: post.id)
        updateNavigationState(for: post.chatID) { state in
            state.unreadPosts.removeAll { $0.messageID == post.messageID }
            state.lastViewedPost = post
        }

        persistState()

        Task {
            do {
                if post.sourceKind == .telegram {
                    try await telegramService.markPostAsRead(post)
                }
                await MainActor.run {
                    self.feedViewModel.markRead(identity: post.id)
                    self.persistState()
                }
            } catch {
                await MainActor.run {
                    self.feedViewModel.errorMessage = error.localizedDescription
                }
            }
        }
    }

    func saveCredentials() {
        authViewModel.isBusy = true
        authViewModel.errorMessage = nil
        authViewModel.state = .initializing
        Task {
            do {
                try await telegramService.saveCredentials(apiIDText: authViewModel.apiID, apiHash: authViewModel.apiHash)
                await synchronizeAuthState()
            } catch {
                authViewModel.errorMessage = error.localizedDescription
            }
            authViewModel.isBusy = false
        }
    }

    func refreshQRCode() {
        authViewModel.isBusy = true
        authViewModel.errorMessage = nil
        authViewModel.state = .initializing
        Task {
            do {
                try await telegramService.resetAuthorization(preserveCredentials: true)
                await synchronizeAuthState()
            } catch {
                authViewModel.errorMessage = error.localizedDescription
            }
            authViewModel.isBusy = false
        }
    }

    func submitPassword() {
        authViewModel.isBusy = true
        Task {
            do {
                try await telegramService.submitPassword(authViewModel.password)
                await synchronizeAuthState()
                authViewModel.password = ""
            } catch {
                authViewModel.errorMessage = error.localizedDescription
            }
            authViewModel.isBusy = false
        }
    }

    func closeSettings() {
        persistState()
    }

    func logout() {
        authViewModel.isBusy = true
        authViewModel.errorMessage = nil
        authViewModel.state = .initializing
        Task {
            do {
                try await telegramService.logout()
                feedViewModel.reset()
                readerViewModel.dismiss()
                viewerViewModel.dismiss()
                detailPresentation = .post
                viewerPresentedPost = nil
                selectedUnreadPostID = nil
                channelNavigationStates.removeAll()
                sessionFeedPosts.removeAll()
                persistState()
            } catch {
                authViewModel.errorMessage = error.localizedDescription
            }
            authViewModel.isBusy = false
        }
    }

    func updateLaunchAtLogin(_ enabled: Bool) {
        settings.launchAtLoginEnabled = enabled
        syncLaunchAtLogin()
        persistState()
    }

    func updateTypography(_ typography: TypographySettings) {
        settings.typography = typography
        persistState()
    }

    func updateMenuBarIconStyle(_ style: MenuBarIconStyle) {
        guard settings.menuBarIconStyle != style else {
            return
        }

        settings.menuBarIconStyle = style
        persistState()
    }

    func updateWindowFrame(_ frame: WindowFrameState?) {
        guard windowFrame != frame else {
            return
        }

        windowFrame = frame
        if let frame {
            Self.logger.debug("Updating window frame to \(frame.rect.debugDescription, privacy: .public)")
        } else {
            Self.logger.debug("Clearing window frame")
        }
        persistState()
    }

    func openChannel(chatID: Int64) {
        channelsViewModel.selectedChannelID = chatID
        isSidebarPresented = false
        persistState()
        showWindow?()
        refreshAggregatedFeedPresentation()
        kickoffBackgroundRefresh()
    }

    var connectionLabel: String {
        switch connectionStatus {
        case .offline:
            return L10n.tr("state.offline")
        case .connecting:
            return L10n.tr("state.connecting")
        case .updating:
            return L10n.tr("state.updating")
        case .ready:
            return L10n.tr("state.ready")
        case .waitingForNetwork:
            return L10n.tr("state.waitingNetwork")
        }
    }

    var totalUnreadCount: Int {
        channelsViewModel.channels.reduce(0) { $0 + $1.unreadCount }
    }

    private func handle(event: TelegramEvent) {
        switch event {
        case .authChanged(let state):
            authViewModel.state = state
            authViewModel.debugMessage = "Auth event: \(authViewModel.stateDebugLabel)"
            if case .waitingPassword = state {
                break
            } else {
                authViewModel.password = ""
            }
            if case .ready = state {
                Task {
                    await reconcileChannels()
                    await syncWatchedChannels()
                    kickoffBackgroundRefresh()
                }
            }

        case .connectionChanged(let status):
            connectionStatus = status
            authViewModel.debugMessage = "Connection event: \(debugLabel(for: status))"

        case .chatUnreadStateChanged(let chatID, let lastReadInboxMessageID, let unreadCount):
            channelsViewModel.applyUnreadState(
                chatID: chatID,
                lastReadInboxMessageID: lastReadInboxMessageID,
                unreadCount: unreadCount
            )
            updateNavigationState(for: chatID) { state in
                state.unreadPosts.removeAll { $0.messageID <= lastReadInboxMessageID }
            }

            for post in sessionFeedPosts.values where post.sourceKind == .telegram && post.chatID == chatID && post.messageID <= lastReadInboxMessageID {
                feedViewModel.markRead(identity: post.id)
            }

            refreshAggregatedFeedPresentation()
            persistState()

        case .unreadPost(let post):
            guard var watchedChannel = channelsViewModel.registerIncoming(post) else {
                return
            }
            persistState()

            let hydratedPost = post.channelTitle.isEmpty ? post.updatingChannelTitle(watchedChannel.displayTitle) : post
            let shouldNotify = hydratedPost.messageID > (watchedChannel.lastNotifiedMessageID ?? 0)

            storeSessionPosts([hydratedPost])
            feedViewModel.markUnread(identity: hydratedPost.id)

            updateNavigationState(for: hydratedPost.chatID) { state in
                state.unreadPosts.removeAll { $0.id == hydratedPost.id }
                state.unreadPosts = sortedUnreadPosts(state.unreadPosts + [hydratedPost])
            }

            refreshAggregatedFeedPresentation()

            if shouldNotify {
                channelsViewModel.markAsNotified(chatID: hydratedPost.chatID, messageID: hydratedPost.messageID)
                persistState()
                Task {
                    await notificationService.postNotification(for: hydratedPost)
                }
            }

            watchedChannel = channelsViewModel.channel(for: hydratedPost.chatID) ?? watchedChannel

        case .debug(let message):
            authViewModel.debugMessage = message
        }
    }

    private func debugLabel(for status: TelegramConnectionStatus) -> String {
        switch status {
        case .offline:
            return "offline"
        case .connecting:
            return "connecting"
        case .updating:
            return "updating"
        case .ready:
            return "ready"
        case .waitingForNetwork:
            return "waitingForNetwork"
        }
    }

    private func synchronizeAuthState() async {
        for attempt in 1...6 {
            await telegramService.refreshAuthorizationState()
            if authViewModel.state != .initializing {
                return
            }
            authViewModel.debugMessage = "Waiting for Telegram state sync (\(attempt)/6)"
            try? await Task.sleep(for: .milliseconds(400))
        }
    }

    private func reconcileChannels() async {
        guard channelsViewModel.channels.isEmpty == false else {
            return
        }

        var didChange = false
        for channel in channelsViewModel.channels {
            do {
                let syncedChannel = try await synchronizeChannel(channel)
                didChange = didChange || syncedChannel != channel
            } catch {
                authViewModel.debugMessage = "Channel sync skipped for @\(channel.username): \(error.localizedDescription)"
            }
        }

        if didChange {
            persistState()
        }
    }

    private func synchronizeChannel(_ channel: WatchedChannel) async throws -> WatchedChannel {
        let syncedChannel: WatchedChannel
        do {
            syncedChannel = try await telegramService.refreshChannel(channel)
        } catch TelegramServiceError.invalidChannel {
            authViewModel.debugMessage = "Skipped channel metadata refresh for \(channel.displayTitle)"
            return channel
        }

        guard syncedChannel != channel else {
            return channel
        }

        channelsViewModel.reconcile(
            syncedChannel,
            previousChatID: channel.chatID,
            previousUsername: channel.username
        )
        persistState()
        await syncWatchedChannels()
        return syncedChannel
    }

    private func syncWatchedChannels() async {
        await telegramService.syncWatchedChannels(channelsViewModel.channels)
    }

    private func restoreCurrentChannelNavigationState() {
        refreshAggregatedFeedPresentation()
    }

    private func refreshAggregatedFeedPresentation() {
        pruneSessionPosts()
        let allPosts = aggregateSessionPosts()
        let rssCount = allPosts.filter { $0.sourceKind == .rss }.count
        let telegramCount = allPosts.count - rssCount
        Self.logger.info("Aggregated feed posts total=\(allPosts.count, privacy: .public) telegram=\(telegramCount, privacy: .public) rss=\(rssCount, privacy: .public)")
        feedViewModel.setPosts(allPosts)
        feedViewModel.errorMessage = nil

        guard allPosts.isEmpty == false else {
            selectedUnreadPostID = nil
            detailPresentation = .post
            viewerPresentedPost = nil
            readerViewModel.dismiss()
            viewerViewModel.dismiss()
            return
        }

        if let selectedUnreadPostID,
           let selectedPost = allPosts.first(where: { $0.id == selectedUnreadPostID })
        {
            if viewerPresentedPost?.id != selectedUnreadPostID {
                present(selectedPost, updateSelection: true)
            }
            return
        }

        if let firstUnreadPost = allPosts.last(where: { feedViewModel.isUnread($0) }) {
            selectedUnreadPostID = firstUnreadPost.id
            present(firstUnreadPost, updateSelection: true)
            return
        }

        if let oldestPost = allPosts.last {
            selectedUnreadPostID = oldestPost.id
            present(oldestPost, updateSelection: true)
            return
        }

        if viewerPresentedPost != nil {
            closeViewer()
        }
    }

    private func present(
        _ post: UnreadPost,
        updateSelection: Bool
    ) {
        withAnimation(.snappy(duration: 0.28)) {
            detailPresentation = .post
            readerViewModel.dismiss()
            viewerPresentedPost = post
            viewerViewModel.present(post: post, telegramService: telegramService)
            if feedViewModel.isUnread(post) {
                markPostAsRead(post)
            }
            updateNavigationState(for: post.chatID) { state in
                state.lastViewedPost = post
            }
            if updateSelection {
                selectedUnreadPostID = post.id
            }
        }
    }

    private func channelNavigationState(for chatID: Int64) -> ChannelUnreadState {
        channelNavigationStates[chatID] ?? ChannelUnreadState()
    }

    private func updateNavigationState(for chatID: Int64, _ mutate: (inout ChannelUnreadState) -> Void) {
        var state = channelNavigationState(for: chatID)
        mutate(&state)
        channelNavigationStates[chatID] = state
    }

    private func aggregateSessionPosts() -> [UnreadPost] {
        Self.sortedSessionPosts(sessionFeedPosts.values.filter {
            isSupported($0) && isWithinRetention($0)
        })
    }

    private func storeSessionPosts(_ posts: [UnreadPost]) {
        for post in posts {
            guard isSupported(post), isWithinRetention(post) else {
                sessionFeedPosts.removeValue(forKey: post.id)
                continue
            }
            sessionFeedPosts[post.id] = post
        }
    }

    private func pruneSessionPosts() {
        let retainedPosts = sessionFeedPosts.values.filter { isSupported($0) && isWithinRetention($0) }
        let retainedIDs = Set(retainedPosts.map(\.id))
        sessionFeedPosts = Dictionary(uniqueKeysWithValues: retainedPosts.map { ($0.id, $0) })

        if let selectedUnreadPostID, retainedIDs.contains(selectedUnreadPostID) == false {
            self.selectedUnreadPostID = nil
            detailPresentation = .post
            viewerPresentedPost = nil
            readerViewModel.dismiss()
            viewerViewModel.dismiss()
        }
    }

    private func removeSessionPosts(for chatID: Int64) {
        sessionFeedPosts = sessionFeedPosts.filter { $0.value.sourceKind != .telegram || $0.value.chatID != chatID }
        feedViewModel.readPostIDs = Set(feedViewModel.readPostIDs.filter { $0.sourceKind != .telegram || $0.sourceIdentifier != String(chatID) })
        if selectedUnreadPostID?.sourceKind == .telegram,
           selectedUnreadPostID?.sourceIdentifier == String(chatID) {
            selectedUnreadPostID = nil
            detailPresentation = .post
            viewerPresentedPost = nil
            readerViewModel.dismiss()
            viewerViewModel.dismiss()
        }
    }

    private func removeSessionPosts(for feed: RSSFeedSource) {
        let identifier = feed.id
        sessionFeedPosts = sessionFeedPosts.filter { $0.value.sourceKind != .rss || $0.value.sourceIdentifier != identifier }
        feedViewModel.readPostIDs = Set(feedViewModel.readPostIDs.filter { $0.sourceKind != .rss || $0.sourceIdentifier != identifier })
        if selectedUnreadPostID?.sourceKind == .rss,
           selectedUnreadPostID?.sourceIdentifier == identifier {
            selectedUnreadPostID = nil
            detailPresentation = .post
            viewerPresentedPost = nil
            readerViewModel.dismiss()
            viewerViewModel.dismiss()
        }
    }

    private func isSupported(_ post: UnreadPost) -> Bool {
        if case .unsupported = post.content {
            return false
        }
        return true
    }

    private func sortedUnreadPosts(_ posts: [UnreadPost]) -> [UnreadPost] {
        Self.sortedSessionPosts(posts)
    }

    private func persistState() {
        do {
            pruneSessionPosts()
            try stateStore.save(PersistedAppState(
                settings: settings,
                watchedChannels: channelsViewModel.channels,
                rssFeeds: rssFeedsViewModel.feeds,
                selectedChannelID: channelsViewModel.selectedChannelID,
                selectedRSSFeedID: rssFeedsViewModel.selectedFeedID,
                feedDisplayMode: feedViewModel.displayMode,
                unreadColumnWidth: Double(unreadColumnWidth),
                windowFrame: windowFrame,
                recentFeedPosts: Self.sortedSessionPosts(sessionFeedPosts.values.filter { isSupported($0) && isWithinRetention($0) }),
                readPostIDs: feedViewModel.readPostIDs.sorted { lhs, rhs in
                    if lhs.sourceKind == rhs.sourceKind, lhs.sourceIdentifier == rhs.sourceIdentifier {
                        return lhs.messageID > rhs.messageID
                    }
                    if lhs.sourceKind != rhs.sourceKind {
                        return lhs.sourceKind.rawValue > rhs.sourceKind.rawValue
                    }
                    return lhs.sourceIdentifier > rhs.sourceIdentifier
                },
                readPostRetentionDates: [:]
            ))
        } catch {
            authViewModel.errorMessage = error.localizedDescription
        }
    }

    private func refreshAllSources(showLoading: Bool) async {
        Self.logger.info("refreshAllSources begin channels=\(self.channelsViewModel.channels.count, privacy: .public) rss=\(self.rssFeedsViewModel.feeds.count, privacy: .public)")

        guard channelsViewModel.channels.isEmpty == false || rssFeedsViewModel.feeds.isEmpty == false else {
            feedViewModel.reset()
            selectedUnreadPostID = nil
            viewerPresentedPost = nil
            viewerViewModel.dismiss()
            sessionFeedPosts.removeAll()
            persistState()
            return
        }

        feedViewModel.isLoading = showLoading
        feedViewModel.errorMessage = nil
        defer {
            if showLoading {
                feedViewModel.isLoading = false
            }
        }

        await refreshTelegramSources(showLoading: false)
        await refreshRSSFeeds(showLoading: false)
    }

    private func refreshTelegramSources(showLoading: Bool) async {
        guard isRefreshingTelegramSources == false else {
            Self.logger.debug("Skipping Telegram refresh because another Telegram refresh is in progress")
            return
        }

        guard channelsViewModel.channels.isEmpty == false else {
            return
        }

        Self.logger.info("refreshTelegramSources begin channels=\(self.channelsViewModel.channels.count, privacy: .public)")
        isRefreshingTelegramSources = true
        if showLoading {
            feedViewModel.isLoading = true
        }
        defer {
            if showLoading {
                feedViewModel.isLoading = false
            }
            isRefreshingTelegramSources = false
        }

        var encounteredError: String?
        for channel in channelsViewModel.channels {
            do {
                Self.logger.debug("Refreshing Telegram channel \(channel.displayTitle, privacy: .public)")
                let syncedChannel = try await synchronizeChannel(channel)
                let posts = try await telegramService.fetchUnreadPosts(for: syncedChannel, limit: 50)
                storeSessionPosts(posts)
                updateNavigationState(for: syncedChannel.chatID) { state in
                    state.unreadPosts = sortedUnreadPosts(posts)
                }
            } catch {
                Self.logger.error("Telegram refresh failed for \(channel.displayTitle, privacy: .public): \(error.localizedDescription, privacy: .public)")
                encounteredError = encounteredError ?? error.localizedDescription
            }
        }

        refreshAggregatedFeedPresentation()
        persistState()

        if let encounteredError {
            feedViewModel.errorMessage = encounteredError
        }
    }

    private func refreshRSSFeeds(showLoading: Bool) async {
        guard isRefreshingRSSFeeds == false else {
            Self.logger.debug("Skipping RSS refresh because another RSS refresh is in progress")
            return
        }

        guard rssFeedsViewModel.feeds.isEmpty == false else {
            return
        }

        Self.logger.info("refreshRSSFeeds begin feeds=\(self.rssFeedsViewModel.feeds.count, privacy: .public)")
        isRefreshingRSSFeeds = true
        if showLoading {
            feedViewModel.isLoading = true
        }
        defer {
            if showLoading {
                feedViewModel.isLoading = false
            }
            isRefreshingRSSFeeds = false
        }

        var encounteredError: String?
        let service = self.rssService
        let feeds = rssFeedsViewModel.feeds

        await withTaskGroup(of: RSSRefreshOutcome.self) { group in
            for feed in feeds {
                group.addTask {
                    do {
                        return RSSRefreshOutcome(result: try await service.refreshFeed(feed, limit: 50), errorMessage: nil)
                    } catch {
                        return RSSRefreshOutcome(result: nil, errorMessage: error.localizedDescription)
                    }
                }
            }

            for await outcome in group {
                if let result = outcome.result {
                    Self.logger.info("RSS refreshed: \(result.source.title, privacy: .public) newPosts=\(result.posts.count, privacy: .public)")
                    rssFeedsViewModel.update(result.source)
                    storeSessionPosts(result.posts)
                    let rssCacheCount = self.sessionFeedPosts.values.filter { $0.sourceKind == .rss }.count
                    Self.logger.info("RSS cache now has \(rssCacheCount, privacy: .public) posts")
                } else if let message = outcome.errorMessage {
                    encounteredError = encounteredError ?? message
                    Self.logger.error("RSS refresh failed: \(message, privacy: .public)")
                }
            }
        }

        refreshAggregatedFeedPresentation()
        persistState()

        if let encounteredError {
            feedViewModel.errorMessage = encounteredError
        }
    }

    private func isWithinRetention(_ post: UnreadPost) -> Bool {
        guard isSupported(post) else {
            return false
        }

        guard feedViewModel.readPostIDs.contains(post.id) else {
            return true
        }

        guard post.hasPublicationDate else {
            return true
        }

        return post.date >= Date().addingTimeInterval(-readFeedRetentionInterval)
    }

    private static func prunedSessionPosts(
        _ posts: [UnreadPost],
        readIDs: Set<UnreadPostIdentity>,
        readRetentionInterval: TimeInterval
    ) -> [UnreadPost] {
        return posts.filter {
            guard $0.sourceKind == .telegram || $0.sourceKind == .rss else {
                return false
            }
            if readIDs.contains($0.id), $0.hasPublicationDate, $0.date < Date().addingTimeInterval(-readRetentionInterval) {
                return false
            }
            if case .unsupported = $0.content {
                return false
            }
            return true
        }
    }

    private static func sortedSessionPosts(_ posts: [UnreadPost]) -> [UnreadPost] {
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

    private static func initialSelectionID(
        from posts: [UnreadPost],
        readIDs: Set<UnreadPostIdentity>
    ) -> UnreadPostIdentity? {
        if let firstUnreadPost = posts.last(where: { readIDs.contains($0.id) == false }) {
            return firstUnreadPost.id
        }
        return posts.first?.id
    }

    private func syncLaunchAtLogin() {
        let service = SMAppService.mainApp
        do {
            if settings.launchAtLoginEnabled {
                try service.register()
            } else {
                try service.unregister()
            }
        } catch {
            authViewModel.errorMessage = error.localizedDescription
        }
    }

    private func startRSSPolling() {
        guard rssPollingTask == nil else {
            return
        }

        let interval = rssPollingInterval
        rssPollingTask = Task { [weak self] in
            while Task.isCancelled == false {
                try? await Task.sleep(for: .seconds(interval))
                guard let self else {
                    return
                }
                await self.refreshRSSFeeds(showLoading: false)
            }
        }
    }

    private func kickoffBackgroundRefresh() {
        guard channelsViewModel.channels.isEmpty == false || rssFeedsViewModel.feeds.isEmpty == false else {
            return
        }

        if channelsViewModel.channels.isEmpty == false {
            Task(priority: .utility) { [weak self] in
                await self?.refreshTelegramSources(showLoading: false)
            }
        }

        if rssFeedsViewModel.feeds.isEmpty == false {
            Task(priority: .utility) { [weak self] in
                await self?.refreshRSSFeeds(showLoading: false)
            }
        }
    }
}

enum DetailPresentation: String, Codable, Hashable {
    case post
    case reader
}

private struct RSSRefreshOutcome {
    let result: RSSFeedRefreshResult?
    let errorMessage: String?
}

private struct ChannelUnreadState {
    var unreadPosts: [UnreadPost] = []
    var lastViewedPost: UnreadPost?
}
