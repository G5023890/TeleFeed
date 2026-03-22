import Foundation

enum TelegramAuthState: Equatable {
    case missingCredentials
    case initializing
    case waitingPhoneNumber
    case waitingForQRCode(link: String?)
    case waitingPassword(hint: String)
    case ready
    case loggingOut
    case closed
    case failed(String)
}

enum TelegramConnectionStatus: Equatable {
    case offline
    case connecting
    case updating
    case ready
    case waitingForNetwork
}

enum TelegramEvent: Equatable {
    case authChanged(TelegramAuthState)
    case connectionChanged(TelegramConnectionStatus)
    case chatUnreadStateChanged(chatID: Int64, lastReadInboxMessageID: Int64, unreadCount: Int)
    case unreadPost(UnreadPost)
    case debug(String)
}

@MainActor
protocol TelegramServiceProtocol: AnyObject {
    var onEvent: ((TelegramEvent) -> Void)? { get set }

    func start() async
    func shutdown() async
    func saveCredentials(apiIDText: String, apiHash: String) async throws
    func loadSavedCredentials() async -> (apiID: String, apiHash: String)?
    func requestQRCodeAuthentication() async throws
    func submitPassword(_ password: String) async throws
    func logout() async throws
    func resetAuthorization(preserveCredentials: Bool) async throws
    func refreshAuthorizationState() async
    func resolveChannel(from input: String) async throws -> WatchedChannel
    func refreshChannel(_ channel: WatchedChannel) async throws -> WatchedChannel
    func syncWatchedChannels(_ channels: [WatchedChannel]) async
    func fetchUnreadPosts(for channel: WatchedChannel, limit: Int) async throws -> [UnreadPost]
    func markPostAsRead(_ post: UnreadPost) async throws
    func downloadMedia(for descriptor: TelegramMediaDescriptor) async throws -> URL
}
