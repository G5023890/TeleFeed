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
    @Published var isSidebarPresented = false

    var showWindow: (() -> Void)?

    private let stateStore: StateStoreProtocol
    private let telegramService: TelegramServiceProtocol
    private let notificationService: NotificationServiceProtocol

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
        await telegramService.shutdown()
    }

    func openHome() {
        if channelsViewModel.selectedChannelID == nil {
            channelsViewModel.selectedChannelID = channelsViewModel.channels.first?.chatID
            persistState()
        }
        showWindow?()
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
        persistState()
        Task {
            await refreshSelectedChannel()
        }
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
        channelsViewModel.removeSelectedChannel()
        feedViewModel.reset()
        persistState()
        Task {
            await syncWatchedChannels()
        }
    }

    func refreshSelectedChannel() async {
        guard let channel = channelsViewModel.selectedChannel else {
            feedViewModel.reset()
            return
        }

        feedViewModel.isLoading = true
        feedViewModel.errorMessage = nil
        do {
            let syncedChannel = try await synchronizeChannel(channel)
            let posts = try await telegramService.fetchUnreadPosts(for: syncedChannel, limit: 20)
            feedViewModel.setPosts(posts)
        } catch {
            feedViewModel.errorMessage = error.localizedDescription
        }
        feedViewModel.isLoading = false
    }

    func openPost(_ post: UnreadPost) {
        viewerPresentedPost = post
        viewerViewModel.present(post: post, telegramService: telegramService)
    }

    func closeViewer() {
        let postToMark = viewerPresentedPost
        viewerPresentedPost = nil
        viewerViewModel.dismiss()

        guard let postToMark else {
            return
        }

        markPostAsRead(postToMark)
    }

    private func markPostAsRead(_ post: UnreadPost) {
        channelsViewModel.markAsRead(chatID: post.chatID, messageID: post.messageID)
        notificationService.removeNotification(chatID: post.chatID, messageID: post.messageID)
        persistState()

        Task {
            do {
                try await telegramService.markPostAsRead(post)
            } catch {
                await MainActor.run {
                    self.feedViewModel.errorMessage = error.localizedDescription
                }
            }
            await refreshSelectedChannel()
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

    func openChannel(chatID: Int64) {
        channelsViewModel.selectedChannelID = chatID
        persistState()
        showWindow?()
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
            persistState()

            if channelsViewModel.selectedChannelID == chatID {
                feedViewModel.unreadPosts.removeAll { $0.messageID <= lastReadInboxMessageID }
            }

        case .unreadPost(let post):
            guard var watchedChannel = channelsViewModel.registerIncoming(post) else {
                return
            }
            persistState()

            let hydratedPost = post.channelTitle.isEmpty ? post.updatingChannelTitle(watchedChannel.title) : post
            let shouldNotify = hydratedPost.messageID > (watchedChannel.lastNotifiedMessageID ?? 0)

            if shouldNotify {
                channelsViewModel.markAsNotified(chatID: hydratedPost.chatID, messageID: hydratedPost.messageID)
                persistState()
                Task {
                    await notificationService.postNotification(for: hydratedPost)
                }
            }

            watchedChannel = channelsViewModel.channel(for: hydratedPost.chatID) ?? watchedChannel
            if channelsViewModel.selectedChannelID == hydratedPost.chatID {
                feedViewModel.prepend(hydratedPost.updatingChannelTitle(watchedChannel.title))
            }

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

    private func persistState() {
        do {
            try stateStore.save(PersistedAppState(
                settings: settings,
                watchedChannels: channelsViewModel.channels,
                selectedChannelID: channelsViewModel.selectedChannelID
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
