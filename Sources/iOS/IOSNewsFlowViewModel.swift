import Foundation
import SwiftUI

@MainActor
final class IOSNewsFlowViewModel: ObservableObject {
    private static let readingAnchorCheckpointInterval: TimeInterval = 60
    private static let activeReadingInteractionInterval: TimeInterval = 2 * 60

    enum Route: Hashable {
        case detail(UnreadPostIdentity)
        case reader(UnreadPostIdentity)
    }

    @Published var draftFilter = DraftNewsFilterState()
    @Published private(set) var appliedFilter = AppliedNewsFilterState()
    @Published var path: [Route] = []
    @Published var isSourcesDrawerPresented = false
    @Published var selectedChannelID: Int64?
    @Published var selectedRSSFeedID: String?
    @Published private(set) var authState: TelegramAuthState = .initializing
    @Published private(set) var connectionStatus: TelegramConnectionStatus = .offline
    @Published private(set) var watchedChannels: [WatchedChannel] = []
    @Published private(set) var rssFeeds: [RSSFeedSource] = []
    @Published private(set) var isRefreshing = false
    @Published private(set) var isBusy = false
    @Published private(set) var focusedPostID: UnreadPostIdentity?
    @Published var apiID = ""
    @Published var apiHash = ""
    @Published var password = ""
    @Published var telegramInput = ""
    @Published var rssInput = ""
    @Published var statusMessage: String?
    @Published var errorMessage: String?

    let feedViewModel: FeedViewModel

    private let secureStorage: SecureStorageProtocol
    private let stateStore: StateStoreProtocol
    private let cloudSyncService: CloudSyncServiceProtocol
    private let telegramService: TelegramServiceProtocol
    private let rssService: RSSServiceProtocol
    private let notificationService: NotificationServiceProtocol
    private var state: PersistedAppState
    private var sessionFeedPosts: [UnreadPostIdentity: UnreadPost] = [:]
    private var lastAutoOpenedPost: NewsReadingAnchor?
    private var startupTask: Task<Void, Never>?
    private var cloudPushTask: Task<Void, Never>?
    private var cloudSyncTask: Task<Void, Never>?
    private var readingAnchorCheckpointTask: Task<Void, Never>?
    private var newsCacheCleanupTask: Task<Void, Never>?
    private var isReadingAnchorCheckpointDirty = false
    private var lastLocalFocusInteractionAt: Date?

    init(
        secureStorage: SecureStorageProtocol = KeychainSecureStorage(),
        stateStore: StateStoreProtocol = FileAppStateStore(),
        cloudSyncService: CloudSyncServiceProtocol = CloudSyncService(),
        telegramService: TelegramServiceProtocol? = nil,
        rssService: RSSServiceProtocol = RSSService(),
        notificationService: NotificationServiceProtocol = LocalNotificationService()
    ) {
        self.secureStorage = secureStorage
        self.stateStore = stateStore
        self.cloudSyncService = cloudSyncService
        self.telegramService = telegramService ?? TelegramService(secureStorage: secureStorage)
        self.rssService = rssService
        self.notificationService = notificationService

        let loadedState = stateStore.load()
        self.state = loadedState
        self.watchedChannels = loadedState.watchedChannels
        self.rssFeeds = loadedState.rssFeeds
        self.selectedChannelID = loadedState.selectedChannelID ?? loadedState.watchedChannels.first?.chatID
        self.selectedRSSFeedID = loadedState.selectedRSSFeedID ?? loadedState.rssFeeds.first?.id
        self.feedViewModel = FeedViewModel(displayMode: loadedState.feedDisplayMode)
        let normalizedPosts = Self.normalizedPosts(
            loadedState.recentFeedPosts,
            channels: loadedState.watchedChannels
        )
        self.feedViewModel.setPosts(normalizedPosts)
        self.sessionFeedPosts = Dictionary(uniqueKeysWithValues: normalizedPosts.map { ($0.id, $0) })
        let focusedPost = Self.preferredPost(from: normalizedPosts, readingAnchor: loadedState.effectiveReadingAnchor)
        self.focusedPostID = focusedPost?.id
        self.feedViewModel.viewedPostID = focusedPost?.id
    }

    deinit {
        startupTask?.cancel()
        cloudPushTask?.cancel()
        cloudSyncTask?.cancel()
        readingAnchorCheckpointTask?.cancel()
        newsCacheCleanupTask?.cancel()
    }

    var setupTitle: String? {
        if hasConfiguredSources == false {
            return "Добавьте RSS или Telegram источник"
        }

        switch authState {
        case .missingCredentials:
            return "Telegram ждёт API ID и API Hash"
        case .waitingPhoneNumber:
            return "Telegram ждёт входа по номеру"
        case .waitingForQRCode:
            return "Telegram ждёт QR-вход"
        case .waitingPassword:
            return "Telegram ждёт пароль"
        case .failed(let message):
            return message
        default:
            return nil
        }
    }

    var setupSubtitle: String {
        let rssPart = "\(rssFeeds.count) RSS"
        let telegramPart = "\(watchedChannels.count) Telegram"
        return "Источники: \(rssPart), \(telegramPart). Новости можно фильтровать уже сейчас, если есть сохранённые записи."
    }

    var filteredPosts: [UnreadPost] {
        feedViewModel.filteredPosts(matching: appliedFilter)
    }

    var hasReadingAnchor: Bool {
        state.effectiveReadingAnchor?.postID != nil
    }

    func start() {
        guard startupTask == nil else {
            return
        }

        telegramService.onEvent = { [weak self] event in
            self?.handle(event)
        }

        notificationService.onOpenChannel = { [weak self] route in
            self?.statusMessage = "Открыт канал \(route.chatID)"
        }

        startupTask = Task { [weak self] in
            guard let self else {
                return
            }

            await notificationService.requestAuthorization()
            if let saved = await telegramService.loadSavedCredentials() {
                apiID = saved.apiID
                apiHash = saved.apiHash
            }
            await syncCloudState(reason: "startup")
            startReadingAnchorCheckpointLoop()
            startNewsCacheCleanupLoop()
            await telegramService.start()
            await refreshAllSources()
        }
    }

    func stop() async {
        readingAnchorCheckpointTask?.cancel()
        readingAnchorCheckpointTask = nil
        newsCacheCleanupTask?.cancel()
        newsCacheCleanupTask = nil
        persistState(pushToCloud: false)
        await flushReadingAnchorCheckpoint(reason: "background")
        await pushCloudState(reason: "background", applyRemoteFocus: false)
        await telegramService.shutdown()
    }

    func resumeFromForeground() {
        cloudSyncTask?.cancel()
        cloudSyncTask = Task { [weak self] in
            self?.startReadingAnchorCheckpointLoop()
            self?.startNewsCacheCleanupLoop()
            await self?.syncCloudState(reason: "foreground")
            await self?.refreshAllSources()
        }
    }

    func performBackgroundRefresh() async {
        if let saved = await telegramService.loadSavedCredentials() {
            apiID = saved.apiID
            apiHash = saved.apiHash
        }
        await syncCloudState(reason: "background refresh")
        await telegramService.start()
        await telegramService.refreshAuthorizationState()
        await refreshAllSources()
        await pushCloudState(reason: "background refresh")
    }

    func presentSourcesDrawer() {
        isSourcesDrawerPresented = true
    }

    func dismissSourcesDrawer() {
        isSourcesDrawerPresented = false
    }

    func applyDrawerFilters() {
        appliedFilter = AppliedNewsFilterState(draft: draftFilter)
        dismissSourcesDrawer()
        Task {
            await refreshAllSources()
        }
    }

    func open(_ post: UnreadPost) {
        registerViewedPost(post, updateFocus: true)
        path.append(.detail(post.id))
    }

    func openReader(for post: UnreadPost) {
        guard post.articleURL != nil else {
            return
        }
        registerViewedPost(post, updateFocus: true)
        path.append(.reader(post.id))
    }

    func downloadMedia(for post: UnreadPost) async throws -> URL {
        guard let descriptor = post.mediaDescriptor else {
            throw TelegramServiceError.mediaUnavailable
        }

        return try await telegramService.downloadMedia(
            for: descriptor,
            chatID: post.chatID,
            messageID: post.messageID
        )
    }

    func markPostAsViewedFromListScroll(_ post: UnreadPost) {
        guard state.effectiveReadingAnchor?.postID != post.id else {
            focusedPostID = post.id
            feedViewModel.viewedPostID = post.id
            return
        }

        state.readingAnchor = NewsReadingAnchor(post: post, readAt: Date())
        state.lastOpenedPost = state.readingAnchor?.lastOpenedPost
        focusedPostID = post.id
        feedViewModel.viewedPostID = post.id
        lastAutoOpenedPost = state.readingAnchor
        persistFocusStateForCheckpoint()
    }

    func post(for identity: UnreadPostIdentity) -> UnreadPost? {
        feedViewModel.posts.first { $0.id == identity }
    }

    func saveCredentials() {
        isBusy = true
        errorMessage = nil
        statusMessage = "Telegram подключается"
        Task {
            do {
                try await telegramService.saveCredentials(apiIDText: apiID, apiHash: apiHash)
                statusMessage = "Данные Telegram сохранены"
            } catch {
                errorMessage = error.localizedDescription
            }
            isBusy = false
        }
    }

    func refreshQRCode() {
        isBusy = true
        errorMessage = nil
        statusMessage = "Готовлю QR-вход"
        Task {
            do {
                try await telegramService.resetAuthorization(preserveCredentials: true)
                statusMessage = "Отсканируйте QR в Telegram"
            } catch {
                errorMessage = error.localizedDescription
            }
            isBusy = false
        }
    }

    func submitPassword() {
        isBusy = true
        errorMessage = nil
        Task {
            do {
                try await telegramService.submitPassword(password)
                password = ""
                statusMessage = "Пароль отправлен"
            } catch {
                errorMessage = error.localizedDescription
            }
            isBusy = false
        }
    }

    func addRSSFeed() {
        let input = rssInput.trimmingCharacters(in: .whitespacesAndNewlines)
        guard input.isEmpty == false else {
            return
        }

        isBusy = true
        errorMessage = nil
        Task {
            do {
                let feed = try await rssService.resolveFeed(from: input)
                guard rssFeeds.contains(where: { $0.normalizedURLString == feed.normalizedURLString }) == false else {
                    throw RSSServiceError.duplicateFeed
                }
                rssFeeds.append(feed)
                rssFeeds.sort { $0.title.localizedCaseInsensitiveCompare($1.title) == .orderedAscending }
                selectedRSSFeedID = feed.id
                state.rssFeeds = rssFeeds
                rssInput = ""
                persistState()
                await refreshAllSources()
            } catch {
                errorMessage = error.localizedDescription
            }
            isBusy = false
        }
    }

    func addTelegramChannel() {
        let input = telegramInput.trimmingCharacters(in: .whitespacesAndNewlines)
        guard input.isEmpty == false else {
            return
        }

        guard authState == .ready else {
            errorMessage = "Telegram должен быть авторизован для добавления каналов."
            return
        }

        isBusy = true
        errorMessage = nil
        Task {
            do {
                let channel = try await telegramService.resolveChannel(from: input)
                guard containsChannel(matching: channel) == false else {
                    throw TelegramServiceError.invalidChannel
                }

                watchedChannels.append(channel)
                watchedChannels.sort { $0.displayTitle.localizedCaseInsensitiveCompare($1.displayTitle) == .orderedAscending }
                selectedChannelID = channel.chatID
                state.watchedChannels = watchedChannels
                telegramInput = ""
                persistState()
                await telegramService.syncWatchedChannels(watchedChannels)
                await refreshAllSources()
            } catch {
                errorMessage = error.localizedDescription
            }
            isBusy = false
        }
    }

    func removeSelectedChannel() {
        guard let selectedChannelID else {
            return
        }

        watchedChannels.removeAll { $0.chatID == selectedChannelID }
        self.selectedChannelID = watchedChannels.first?.chatID
        sessionFeedPosts = sessionFeedPosts.filter { $0.value.sourceKind != .telegram || $0.value.chatID != selectedChannelID }
        if state.effectiveReadingAnchor?.isAnchoredToSource(kind: .telegram, identifier: String(selectedChannelID)) == true {
            state.readingAnchor = nil
            state.lastOpenedPost = nil
            feedViewModel.viewedPostID = nil
            focusedPostID = nil
            lastAutoOpenedPost = nil
        }
        state.watchedChannels = watchedChannels
        refreshFeedPresentation()
        Task {
            await telegramService.syncWatchedChannels(watchedChannels)
        }
    }

    func removeSelectedRSSFeed() {
        guard let selectedRSSFeedID else {
            return
        }

        rssFeeds.removeAll { $0.id == selectedRSSFeedID }
        self.selectedRSSFeedID = rssFeeds.first?.id
        sessionFeedPosts = sessionFeedPosts.filter { $0.value.sourceKind != .rss || $0.value.sourceIdentifier != selectedRSSFeedID }
        if state.effectiveReadingAnchor?.isAnchoredToSource(kind: .rss, identifier: selectedRSSFeedID) == true {
            state.readingAnchor = nil
            state.lastOpenedPost = nil
            feedViewModel.viewedPostID = nil
            focusedPostID = nil
            lastAutoOpenedPost = nil
        }
        state.rssFeeds = rssFeeds
        refreshFeedPresentation()
    }

    func refreshAllSources() async {
        guard isRefreshing == false else {
            return
        }

        isRefreshing = true
        errorMessage = nil
        await refreshRSSFeeds()
        await refreshTelegramChannelsIfReady()
        refreshFeedPresentation()
        isRefreshing = false
    }

    private var hasConfiguredSources: Bool {
        rssFeeds.isEmpty == false || watchedChannels.isEmpty == false
    }

    private func handle(_ event: TelegramEvent) {
        switch event {
        case .authChanged(let state):
            authState = state
            if case .ready = state {
                Task {
                    await reconcileDefaultTelegramChannelsIfNeeded()
                    await refreshAllSources()
                }
            }
        case .connectionChanged(let status):
            connectionStatus = status
        case .chatUnreadStateChanged(let chatID, let lastReadInboxMessageID, let unreadCount):
            if let index = watchedChannels.firstIndex(where: { $0.chatID == chatID }) {
                watchedChannels[index].applyUnreadState(
                    lastReadInboxMessageID: lastReadInboxMessageID,
                    unreadCount: unreadCount
                )
                state.watchedChannels = watchedChannels
                persistState()
                objectWillChange.send()
            }
        case .unreadPost(let post):
            storePosts([post])
            refreshFeedPresentation()
        case .debug(let message):
            statusMessage = message
        }
    }

    private func refreshRSSFeeds() async {
        guard rssFeeds.isEmpty == false else {
            return
        }

        var refreshedFeeds = rssFeeds
        var refreshedPosts: [UnreadPost] = []
        var encounteredError: String?
        var successfulRefreshCount = 0

        for feed in rssFeeds {
            do {
                let result = try await rssService.refreshFeed(feed, limit: 20)
                if let index = refreshedFeeds.firstIndex(where: { $0.id == feed.id }) {
                    refreshedFeeds[index] = result.source
                }
                refreshedPosts.append(contentsOf: result.posts)
                successfulRefreshCount += 1
            } catch {
                encounteredError = encounteredError ?? "\(feed.title): \(error.localizedDescription)"
            }
        }

        rssFeeds = refreshedFeeds
        state.rssFeeds = refreshedFeeds
        storePosts(refreshedPosts)
        errorMessage = successfulRefreshCount == 0 ? encounteredError : nil
    }

    private func refreshTelegramChannelsIfReady() async {
        guard authState == .ready, watchedChannels.isEmpty == false else {
            return
        }

        await telegramService.syncWatchedChannels(watchedChannels)
        var refreshedPosts: [UnreadPost] = []
        var refreshedChannels = watchedChannels

        for channel in watchedChannels {
            do {
                let refreshedChannel = try await telegramService.refreshChannel(channel)
                if let index = refreshedChannels.firstIndex(where: { $0.chatID == channel.chatID }) {
                    refreshedChannels[index] = refreshedChannel
                }
                let posts = try await telegramService.fetchRecentPosts(for: refreshedChannel, limit: 20)
                refreshedPosts.append(contentsOf: posts)
            } catch {
                errorMessage = error.localizedDescription
            }
        }

        watchedChannels = refreshedChannels
        state.watchedChannels = refreshedChannels
        storePosts(refreshedPosts)
    }

    private func reconcileDefaultTelegramChannelsIfNeeded() async {
        guard authState == .ready else {
            return
        }

        var didChange = false
        for input in DefaultTelegramChannels.inputs {
            do {
                let channel = try await telegramService.resolveChannel(from: input)
                guard state.syncMetadata.isChannelDeleted(channel) == false else {
                    continue
                }
                guard containsChannel(matching: channel) == false else {
                    continue
                }
                watchedChannels.append(channel)
                didChange = true
            } catch {
                errorMessage = error.localizedDescription
            }
        }

        guard didChange else {
            return
        }

        watchedChannels.sort { $0.displayTitle.localizedCaseInsensitiveCompare($1.displayTitle) == .orderedAscending }
        state.watchedChannels = watchedChannels
        persistState()
    }

    private func containsChannel(matching channel: WatchedChannel) -> Bool {
        watchedChannels.contains {
            $0.chatID == channel.chatID || $0.username.caseInsensitiveCompare(channel.username) == .orderedSame
        }
    }

    private func storePosts(_ posts: [UnreadPost]) {
        for post in normalizedPosts(posts) {
            sessionFeedPosts[post.id] = post
        }
        refreshFeedPresentation()
    }

    private func normalizedPosts(_ posts: [UnreadPost]) -> [UnreadPost] {
        Self.normalizedPosts(posts, channels: watchedChannels)
    }

    private static func normalizedPosts(_ posts: [UnreadPost], channels: [WatchedChannel]) -> [UnreadPost] {
        posts.map { post in
            guard
                post.sourceKind == .telegram,
                post.channelTitle.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
                let channel = channels.first(where: { $0.chatID == post.chatID })
            else {
                return post
            }

            return post.updatingChannelTitle(channel.displayTitle)
        }
    }

    private func refreshFeedPresentation(pushToCloud: Bool = true, applyFocus: Bool = true) {
        let retained = retainedSessionPosts()
        sessionFeedPosts = Dictionary(uniqueKeysWithValues: retained.map { ($0.id, $0) })
        feedViewModel.setPosts(retained)
        state.recentFeedPosts = retained
        state.readPostIDs = []
        persistState(pushToCloud: pushToCloud)
        if applyFocus {
            focusLastOpenedPostIfAvailable()
        }
        objectWillChange.send()
    }

    private func retainedSessionPosts() -> [UnreadPost] {
        NewsCachePolicy.retainedPosts(sessionFeedPosts.values.filter(isActiveSupportedPost))
    }

    private func registerViewedPost(_ post: UnreadPost, updateFocus: Bool) {
        guard feedViewModel.viewedPostID != post.id else {
            markTelegramPostAsViewed(post)
            return
        }

        state.readingAnchor = NewsReadingAnchor(post: post, readAt: Date())
        state.lastOpenedPost = state.readingAnchor?.lastOpenedPost
        if updateFocus {
            focusedPostID = post.id
        }
        feedViewModel.viewedPostID = post.id
        lastAutoOpenedPost = state.readingAnchor
        persistFocusStateForCheckpoint()
        markTelegramPostAsViewed(post)
    }

    private func focusLastOpenedPostIfAvailable() {
        guard let readingAnchor = state.effectiveReadingAnchor else {
            return
        }

        guard let focusedPost = preferredFocusedPost(for: readingAnchor) else {
            focusedPostID = nil
            feedViewModel.viewedPostID = nil
            lastAutoOpenedPost = readingAnchor
            return
        }

        guard focusedPostID != focusedPost.id || lastAutoOpenedPost != readingAnchor else {
            return
        }

        focusedPostID = focusedPost.id
        feedViewModel.viewedPostID = focusedPost.id
        lastAutoOpenedPost = readingAnchor
    }

    private func preferredFocusedPost(for readingAnchor: NewsReadingAnchor) -> UnreadPost? {
        Self.preferredPost(from: feedViewModel.posts, readingAnchor: readingAnchor)
    }

    static func preferredPost(
        from posts: [UnreadPost],
        readingAnchor: NewsReadingAnchor?
    ) -> UnreadPost? {
        if let postID = readingAnchor?.postID {
            return posts.first(where: { $0.id == postID })
        }

        return posts.last
    }

    private func markTelegramPostAsViewed(_ post: UnreadPost) {
        guard post.sourceKind == .telegram else {
            return
        }

        notificationService.removeNotification(chatID: post.chatID, messageID: post.messageID)
        Task {
            try? await telegramService.markPostAsRead(post)
        }
    }

    private func persistState(pushToCloud: Bool = true) {
        state.watchedChannels = watchedChannels
        state.rssFeeds = rssFeeds
        state.selectedChannelID = selectedChannelID
        state.selectedRSSFeedID = selectedRSSFeedID
        state.feedDisplayMode = nil
        state.readingAnchor = state.effectiveReadingAnchor
        state.lastOpenedPost = state.readingAnchor?.lastOpenedPost
        state.recentFeedPosts = retainedSessionPosts()
        state.readPostIDs = []

        do {
            try stateStore.save(state)
            if pushToCloud {
                scheduleCloudPush()
            }
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func persistFocusStateForCheckpoint() {
        lastLocalFocusInteractionAt = Date()
        isReadingAnchorCheckpointDirty = true
        persistState(pushToCloud: false)
    }

    private func scheduleCloudPush() {
        cloudPushTask?.cancel()
        cloudPushTask = Task { [weak self] in
            try? await Task.sleep(for: .milliseconds(900))
            await self?.pushCloudState(reason: "local change")
        }
    }

    private func startReadingAnchorCheckpointLoop() {
        guard readingAnchorCheckpointTask == nil else {
            return
        }

        let interval = Self.readingAnchorCheckpointInterval
        readingAnchorCheckpointTask = Task { [weak self] in
            while Task.isCancelled == false {
                try? await Task.sleep(for: .seconds(interval))
                guard let self else {
                    return
                }

                let didPushCheckpoint = await self.flushReadingAnchorCheckpoint(reason: "reading checkpoint")
                if didPushCheckpoint == false {
                    await self.syncCloudState(
                        reason: "reading checkpoint",
                        applyRemoteFocus: self.shouldApplyRemoteFocus()
                    )
                }
            }
        }
    }

    private func startNewsCacheCleanupLoop() {
        guard newsCacheCleanupTask == nil else {
            return
        }

        newsCacheCleanupTask = Task { [weak self] in
            while Task.isCancelled == false {
                let nextCleanup = NewsCachePolicy.nextDailyCleanupDate()
                let delay = max(60, nextCleanup.timeIntervalSinceNow)
                try? await Task.sleep(for: .seconds(delay))
                guard let self else {
                    return
                }
                self.refreshFeedPresentation()
                await AppCacheCleaner.cleanDailyCaches()
            }
        }
    }

    @discardableResult
    private func flushReadingAnchorCheckpoint(reason: String) async -> Bool {
        guard isReadingAnchorCheckpointDirty else {
            return false
        }

        isReadingAnchorCheckpointDirty = false
        await pushCloudState(reason: reason, applyRemoteFocus: shouldApplyRemoteFocus())
        return true
    }

    private func shouldApplyRemoteFocus() -> Bool {
        guard let lastLocalFocusInteractionAt else {
            return true
        }

        return Date().timeIntervalSince(lastLocalFocusInteractionAt) > Self.activeReadingInteractionInterval
    }

    private func pushCloudState(reason: String) async {
        await pushCloudState(reason: reason, applyRemoteFocus: true)
    }

    private func pushCloudState(reason: String, applyRemoteFocus: Bool) async {
        do {
            let mergedState = try await cloudSyncService.push(local: state)
            applyCloudState(mergedState, applyRemoteFocus: applyRemoteFocus)
            persistState(pushToCloud: false)
            statusMessage = "iCloud синхронизирован: \(reason) • \(mergedState.syncedSources.statusSummary)"
        } catch {
            statusMessage = "iCloud временно недоступен: \(error.localizedDescription)"
        }
    }

    private func syncCloudState(reason: String) async {
        await syncCloudState(reason: reason, applyRemoteFocus: true)
    }

    private func syncCloudState(reason: String, applyRemoteFocus: Bool) async {
        do {
            let mergedState = try await cloudSyncService.sync(local: state)
            applyCloudState(mergedState, applyRemoteFocus: applyRemoteFocus)
            persistState(pushToCloud: false)
            statusMessage = "iCloud синхронизирован: \(reason) • \(mergedState.syncedSources.statusSummary)"
        } catch {
            statusMessage = "iCloud временно недоступен: \(error.localizedDescription)"
        }
    }

    private func applyCloudState(_ mergedState: PersistedAppState) {
        applyCloudState(mergedState, applyRemoteFocus: true)
    }

    private func applyCloudState(_ mergedState: PersistedAppState, applyRemoteFocus: Bool) {
        let localReadingAnchor = state.effectiveReadingAnchor
        state = mergedState
        watchedChannels = mergedState.watchedChannels
        rssFeeds = mergedState.rssFeeds
        selectedChannelID = mergedState.selectedChannelID ?? mergedState.watchedChannels.first?.chatID
        selectedRSSFeedID = mergedState.selectedRSSFeedID ?? mergedState.rssFeeds.first?.id
        if applyRemoteFocus == false, let localReadingAnchor, isAnchorSourceActive(localReadingAnchor) {
            state.readingAnchor = localReadingAnchor
            state.lastOpenedPost = localReadingAnchor.lastOpenedPost
        }
        sessionFeedPosts = sessionFeedPosts.filter { _, post in
            switch post.sourceKind {
            case .telegram:
                return watchedChannels.contains(where: { $0.chatID == post.chatID })
            case .rss:
                return rssFeeds.contains(where: { $0.id == post.sourceIdentifier })
            }
        }
        for post in normalizedPosts(mergedState.recentFeedPosts) where isActiveSupportedPost(post) {
            sessionFeedPosts[post.id] = post
        }
        refreshFeedPresentation(pushToCloud: false, applyFocus: applyRemoteFocus)
    }

    private func isAnchorSourceActive(_ anchor: NewsReadingAnchor) -> Bool {
        let sourceKind = anchor.sourceKind ?? anchor.postID?.sourceKind
        let sourceIdentifier = anchor.sourceIdentifier ?? anchor.postID?.sourceIdentifier
        guard let sourceKind, let sourceIdentifier else {
            return true
        }

        switch sourceKind {
        case .telegram:
            return watchedChannels.contains { String($0.chatID) == sourceIdentifier }
        case .rss:
            return rssFeeds.contains { $0.id == sourceIdentifier }
        }
    }

    private func isActiveSupportedPost(_ post: UnreadPost) -> Bool {
        guard NewsCachePolicy.isRetained(post) else {
            return false
        }

        switch post.sourceKind {
        case .telegram:
            return watchedChannels.contains(where: { $0.chatID == post.chatID })
        case .rss:
            return rssFeeds.contains(where: { $0.id == post.sourceIdentifier })
        }
    }
}
