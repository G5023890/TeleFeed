import Foundation
import ServiceManagement

@MainActor
final class MainViewModel: ObservableObject {
    @Published var authViewModel: AuthViewModel
    @Published var channelsViewModel: ChannelsViewModel
    @Published var feedViewModel = FeedViewModel()
    @Published var viewerViewModel = ViewerViewModel()
    @Published var settings: AppSettings
    @Published var showingSettings = false
    @Published var connectionStatus: TelegramConnectionStatus = .offline
    @Published var viewerPresentedPost: UnreadPost?
    @Published var selectedUnreadPostID: UnreadPostIdentity?
    @Published var isSidebarPresented = false
    @Published var unreadColumnWidth: CGFloat

    var showWindow: (() -> Void)?

    private let stateStore: StateStoreProtocol
    private let telegramService: TelegramServiceProtocol
    private let notificationService: NotificationServiceProtocol
    private var channelNavigationStates: [Int64: ChannelUnreadState] = [:]
    private var sessionFeedPosts: [UnreadPostIdentity: UnreadPost] = [:]
    private var unreadFocusTimerTask: Task<Void, Never>?
    private var unreadColumnWidthPersistTask: Task<Void, Never>?

    init(
        stateStore: StateStoreProtocol,
        telegramService: TelegramServiceProtocol,
        notificationService: NotificationServiceProtocol
    ) {
        let state = stateStore.load()
        self.stateStore = stateStore
        self.telegramService = telegramService
        self.notificationService = notificationService
        self.settings = state.settings
        self.unreadColumnWidth = CGFloat(state.unreadColumnWidth ?? 300)
        self.authViewModel = AuthViewModel()
        self.channelsViewModel = ChannelsViewModel(
            channels: state.watchedChannels,
            selectedChannelID: state.selectedChannelID
        )
    }

    func start() async {
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
        await telegramService.start()
        await synchronizeAuthState()
    }

    func shutdown() async {
        cancelUnreadFocusTimer()
        unreadColumnWidthPersistTask?.cancel()
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
        Task {
            await refreshSelectedChannel()
        }
    }

    func openSettings() {
        showingSettings = true
        showWindow?()
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
                await refreshSelectedChannel()
            } catch {
                channelsViewModel.errorMessage = error.localizedDescription == TelegramServiceError.invalidChannel.localizedDescription
                    ? L10n.tr("channels.invalid")
                    : error.localizedDescription
            }
        }
    }

    func removeSelectedChannel() {
        guard let removedChannelID = channelsViewModel.selectedChannelID else {
            return
        }

        channelsViewModel.removeSelectedChannel()
        channelNavigationStates.removeValue(forKey: removedChannelID)

        persistState()
        Task {
            await syncWatchedChannels()
            await refreshSelectedChannel()
        }
    }

    func refreshSelectedChannel() async {
        feedViewModel.isLoading = true
        feedViewModel.errorMessage = nil

        defer {
            feedViewModel.isLoading = false
        }

        guard channelsViewModel.channels.isEmpty == false else {
            feedViewModel.reset()
            selectedUnreadPostID = nil
            cancelUnreadFocusTimer()
            viewerPresentedPost = nil
            viewerViewModel.dismiss()
            sessionFeedPosts.removeAll()
            return
        }

        var encounteredError: String?
        for channel in channelsViewModel.channels {
            do {
                let syncedChannel = try await synchronizeChannel(channel)
                let posts = try await telegramService.fetchUnreadPosts(for: syncedChannel, limit: 50)
                storeSessionPosts(posts)
                updateNavigationState(for: syncedChannel.chatID) { state in
                    state.unreadPosts = sortedUnreadPosts(posts)
                }
            } catch {
                encounteredError = encounteredError ?? error.localizedDescription
            }
        }
        refreshAggregatedFeedPresentation()

        if let encounteredError {
            feedViewModel.errorMessage = encounteredError
        }
    }

    func openPost(_ post: UnreadPost) {
        selectUnreadPost(post.id)
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

        selectedUnreadPostID = postID

        guard let postID else {
            cancelUnreadFocusTimer()
            return
        }

        guard let post = feedViewModel.posts.first(where: { $0.id == postID }) else {
            cancelUnreadFocusTimer()
            return
        }

        present(post, startUnreadTimer: true, updateSelection: true)
    }

    func closeViewer() {
        cancelUnreadFocusTimer()
        viewerPresentedPost = nil
        viewerViewModel.dismiss()
    }

    private func markPostAsRead(_ post: UnreadPost) {
        cancelUnreadFocusTimer()
        channelsViewModel.markAsRead(chatID: post.chatID, messageID: post.messageID)
        notificationService.removeNotification(chatID: post.chatID, messageID: post.messageID)
        feedViewModel.markRead(identity: post.id)
        updateNavigationState(for: post.chatID) { state in
            state.unreadPosts.removeAll { $0.messageID == post.messageID }
            state.lastViewedPost = nil
        }

        persistState()

        Task {
            do {
                try await telegramService.markPostAsRead(post)
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
                showingSettings = false
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
        showingSettings = false
    }

    func logout() {
        authViewModel.isBusy = true
        authViewModel.errorMessage = nil
        authViewModel.state = .initializing
        Task {
            do {
                try await telegramService.logout()
                feedViewModel.reset()
                viewerViewModel.dismiss()
                viewerPresentedPost = nil
                selectedUnreadPostID = nil
                cancelUnreadFocusTimer()
                channelNavigationStates.removeAll()
                showingSettings = false
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

    func updateUnreadColumnWidth(_ width: CGFloat) {
        let normalizedWidth = max(240, min(width, 420))
        guard abs(unreadColumnWidth - normalizedWidth) > 1 else {
            return
        }

        unreadColumnWidth = normalizedWidth
        unreadColumnWidthPersistTask?.cancel()
        unreadColumnWidthPersistTask = Task { [weak self] in
            try? await Task.sleep(for: .milliseconds(250))
            await MainActor.run {
                self?.persistState()
            }
        }
    }

    func openChannel(chatID: Int64) {
        channelsViewModel.selectedChannelID = chatID
        isSidebarPresented = false
        persistState()
        showWindow?()
        refreshAggregatedFeedPresentation()
        Task {
            await refreshSelectedChannel()
        }
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
                    await refreshSelectedChannel()
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

            for post in sessionFeedPosts.values where post.chatID == chatID && post.messageID <= lastReadInboxMessageID {
                feedViewModel.markRead(identity: post.id)
            }

            refreshAggregatedFeedPresentation()
            persistState()

        case .unreadPost(let post):
            guard var watchedChannel = channelsViewModel.registerIncoming(post) else {
                return
            }
            persistState()

            let hydratedPost = post.channelTitle.isEmpty ? post.updatingChannelTitle(watchedChannel.title) : post
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
            authViewModel.debugMessage = "Skipped channel metadata refresh for \(channel.title)"
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
        let allPosts = aggregateSessionPosts()
        feedViewModel.setPosts(allPosts)
        feedViewModel.errorMessage = nil

        guard let selectedUnreadPostID else {
            if viewerPresentedPost == nil, let firstUnreadPost = allPosts.first {
                selectedUnreadPostID = firstUnreadPost.id
                present(firstUnreadPost, startUnreadTimer: true, updateSelection: true)
            }
            return
        }

        if let selectedPost = allPosts.first(where: { $0.id == selectedUnreadPostID }) {
            if viewerPresentedPost?.id != selectedUnreadPostID {
                present(selectedPost, startUnreadTimer: true, updateSelection: true)
            }
        } else if viewerPresentedPost != nil {
            closeViewer()
        }
    }

    private func present(
        _ post: UnreadPost,
        startUnreadTimer: Bool,
        updateSelection: Bool
    ) {
        viewerPresentedPost = post
        viewerViewModel.present(post: post, telegramService: telegramService)
        updateNavigationState(for: post.chatID) { state in
            state.lastViewedPost = post
        }
        if updateSelection {
            selectedUnreadPostID = post.id
        }

        if startUnreadTimer {
            scheduleUnreadFocusTimer(for: post)
        } else {
            cancelUnreadFocusTimer()
        }
    }

    private func scheduleUnreadFocusTimer(for post: UnreadPost) {
        cancelUnreadFocusTimer()
        unreadFocusTimerTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(5))
            guard let self else {
                return
            }
            await MainActor.run {
                self.handleUnreadFocusTimerFired(for: post)
            }
        }
    }

    private func handleUnreadFocusTimerFired(for post: UnreadPost) {
        guard selectedUnreadPostID == post.id else {
            return
        }
        guard viewerPresentedPost?.id == post.id else {
            return
        }
        markPostAsRead(post)
    }

    private func cancelUnreadFocusTimer() {
        unreadFocusTimerTask?.cancel()
        unreadFocusTimerTask = nil
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
        sortedUnreadPosts(sessionFeedPosts.values.map { $0 })
    }

    private func storeSessionPosts(_ posts: [UnreadPost]) {
        for post in posts {
            sessionFeedPosts[post.id] = post
        }
    }

    private func sortedUnreadPosts(_ posts: [UnreadPost]) -> [UnreadPost] {
        posts.sorted { lhs, rhs in
            if lhs.date == rhs.date {
                if lhs.chatID == rhs.chatID {
                    return lhs.messageID > rhs.messageID
                }
                return lhs.chatID > rhs.chatID
            }
            return lhs.date > rhs.date
        }
    }

    private func persistState() {
        do {
            try stateStore.save(PersistedAppState(
                settings: settings,
                watchedChannels: channelsViewModel.channels,
                selectedChannelID: channelsViewModel.selectedChannelID,
                unreadColumnWidth: Double(unreadColumnWidth)
            ))
        } catch {
            authViewModel.errorMessage = error.localizedDescription
        }
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
}

private struct ChannelUnreadState {
    var unreadPosts: [UnreadPost] = []
    var lastViewedPost: UnreadPost?
}
