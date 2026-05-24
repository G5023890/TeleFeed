import Foundation
import OSLog
#if os(iOS)
import UIKit
#endif

enum TelegramServiceError: LocalizedError {
    case missingCredentials
    case invalidCredentialsFormat
    case invalidChannel
    case mediaUnavailable
    case tdlibUnavailable

    var errorDescription: String? {
        switch self {
        case .missingCredentials:
            return "Telegram api_id / api_hash are missing."
        case .invalidCredentialsFormat:
            return "Invalid Telegram API credentials."
        case .invalidChannel:
            return L10n.tr("channels.invalid")
        case .mediaUnavailable:
            return L10n.tr("viewer.mediaUnavailable")
        case .tdlibUnavailable:
            return "TDLib client is unavailable."
        }
    }
}

@MainActor
final class TelegramService: TelegramServiceProtocol {
    var onEvent: ((TelegramEvent) -> Void)?

    private enum StorageDirectoryName {
        static let current = "TeleFeed"
        static let legacy = "Telega"
    }

    private enum SecureStorageKey {
        static let apiID = "telegram.api-id"
        static let apiHash = "telegram.api-hash"
        static let databaseEncryptionKey = "telegram.database-encryption-key"
    }

    private let secureStorage: SecureStorageProtocol
    private let fileManager: FileManager
    private let logger = Logger(subsystem: "com.codex.TeleFeed", category: "TelegramService")
    private var client: TDLibClient?
    private var clientGeneration = 0
    private var currentCredentials: TelegramCredentials?
    private var currentAuthState: TelegramAuthState = .missingCredentials
    private var pendingFileDownloads: [Int32: CheckedContinuation<URL, Error>] = [:]
    private var openedWatchedChatIDs: Set<Int64> = []

    init(
        secureStorage: SecureStorageProtocol,
        fileManager: FileManager = .default
    ) {
        self.secureStorage = secureStorage
        self.fileManager = fileManager
    }

    func start() async {
        guard client == nil else {
            emitDebug("Skipped start because TDLib client already exists")
            return
        }

        guard let credentials = await storedCredentials() else {
            currentAuthState = .missingCredentials
            onEvent?(.authChanged(.missingCredentials))
            emitDebug("Missing api_id/api_hash")
            return
        }

        currentCredentials = credentials
        cleanTemporaryMediaCache()

        let client = TDLibClient()
        clientGeneration += 1
        let generation = clientGeneration
        self.client = client
        await client.setUpdateHandler { [weak self] updateString in
            Task { @MainActor [weak self] in
                guard
                    let self,
                    generation == self.clientGeneration,
                    let update = self.deserialize(updateString)
                else {
                    return
                }
                await self.handle(update: update)
            }
        }
        await client.start()
        currentAuthState = .initializing
        onEvent?(.authChanged(.initializing))
        emitDebug("TDLib client started")
    }

    func shutdown() async {
        guard let client else {
            return
        }
        clientGeneration += 1
        _ = try? await sendRequest(["@type": "close"])
        await client.stop()
        pendingFileDownloads.removeAll()
        openedWatchedChatIDs.removeAll()
        self.client = nil
        currentAuthState = .closed
    }

    func saveCredentials(apiIDText: String, apiHash: String) async throws {
        guard let apiID = Int32(apiIDText), apiHash.isEmpty == false else {
            throw TelegramServiceError.invalidCredentialsFormat
        }

        try secureStorage.save(String(apiID), for: SecureStorageKey.apiID)
        try secureStorage.save(apiHash, for: SecureStorageKey.apiHash)
        if try secureStorage.loadValue(for: SecureStorageKey.databaseEncryptionKey) == nil {
            try secureStorage.save(UUID().uuidString.replacingOccurrences(of: "-", with: ""), for: SecureStorageKey.databaseEncryptionKey)
        }

        currentCredentials = TelegramCredentials(apiID: apiID, apiHash: apiHash)

        if client != nil {
            await shutdown()
        }
        await start()
    }

    func loadSavedCredentials() async -> (apiID: String, apiHash: String)? {
        let apiID = try? secureStorage.loadValue(for: SecureStorageKey.apiID)
        let apiHash = try? secureStorage.loadValue(for: SecureStorageKey.apiHash)
        guard let apiID, let apiHash else {
            return nil
        }
        return (apiID, apiHash)
    }

    func requestQRCodeAuthentication() async throws {
        guard client != nil else {
            throw TelegramServiceError.tdlibUnavailable
        }
        try await sendRequestWithoutWaiting([
            "@type": "requestQrCodeAuthentication",
            "other_user_ids": [],
        ])
        scheduleAuthorizationStateRefresh(reason: "requestQrCodeAuthentication")
    }

    func submitPassword(_ password: String) async throws {
        guard client != nil else {
            throw TelegramServiceError.tdlibUnavailable
        }
        guard case .waitingPassword = currentAuthState else {
            throw TDLibError(
                code: 400,
                message: "Telegram is not waiting for the two-step verification password. Start the QR login flow again."
            )
        }
        _ = try await sendRequest([
            "@type": "checkAuthenticationPassword",
            "password": password,
        ])
        scheduleAuthorizationStateRefresh(reason: "checkAuthenticationPassword")
    }

    func logout() async throws {
        try await resetAuthorization(preserveCredentials: true)
    }

    func resetAuthorization(preserveCredentials: Bool) async throws {
        emitDebug("Resetting authorization preserveCredentials=\(preserveCredentials)")
        if let client {
            clientGeneration += 1
            await client.stop()
            self.client = nil
        }

        pendingFileDownloads.removeAll()
        openedWatchedChatIDs.removeAll()
        cleanTDLibState()
        cleanTemporaryMediaCache()

        if preserveCredentials {
            currentCredentials = await storedCredentials()
            try secureStorage.save(UUID().uuidString.replacingOccurrences(of: "-", with: ""), for: SecureStorageKey.databaseEncryptionKey)
            currentAuthState = .initializing
            onEvent?(.authChanged(.initializing))
            await start()
        } else {
            try secureStorage.deleteValue(for: SecureStorageKey.apiID)
            try secureStorage.deleteValue(for: SecureStorageKey.apiHash)
            try secureStorage.deleteValue(for: SecureStorageKey.databaseEncryptionKey)
            currentCredentials = nil
            currentAuthState = .missingCredentials
            onEvent?(.authChanged(.missingCredentials))
        }
    }

    func refreshAuthorizationState() async {
        guard client != nil else {
            emitDebug("Refresh requested without active TDLib client")
            return
        }

        do {
            let response = try await sendRequest(["@type": "getAuthorizationState"])
            let object = response.dictionary("authorization_state") ?? response
            let state = TelegramParsing.parseAuthorizationState(from: object)
            currentAuthState = state
            onEvent?(.authChanged(state))
            emitDebug("Synced authorization state: \(describeAuthState(state))")
        } catch {
            emitDebug("Failed to sync authorization state: \(error.localizedDescription)")
        }
    }

    func resolveChannel(from input: String) async throws -> WatchedChannel {
        guard let username = normalizeChannelIdentifier(input) else {
            throw TelegramServiceError.invalidChannel
        }
        return try await resolveChannel(username: username)
    }

    func refreshChannel(_ channel: WatchedChannel) async throws -> WatchedChannel {
        let fallbackUsername = normalizedStoredUsername(channel.username)

        if let resolvedByChatID = try? await loadChannel(chatID: channel.chatID, fallbackUsername: fallbackUsername) {
            return channel.mergedIdentity(with: resolvedByChatID)
        }

        if let supergroupID = channel.supergroupID,
           let resolvedBySupergroupID = try? await loadChannel(supergroupID: supergroupID, fallbackUsername: fallbackUsername) {
            return channel.mergedIdentity(with: resolvedBySupergroupID)
        }

        if let resolvedByTitle = try? await searchChannel(title: channel.title, fallbackUsername: fallbackUsername) {
            return channel.mergedIdentity(with: resolvedByTitle)
        }

        guard let username = fallbackUsername else {
            throw TDLibError(code: 400, message: "Chat not found")
        }

        let resolved = try await resolveChannel(username: username)
        return channel.mergedIdentity(with: resolved)
    }

    func syncWatchedChannels(_ channels: [WatchedChannel]) async {
        guard client != nil, currentAuthState == .ready else {
            return
        }

        let desiredChatIDs = Set(channels.map(\.chatID))
        let chatsToOpen = desiredChatIDs.subtracting(openedWatchedChatIDs)
        let chatsToClose = openedWatchedChatIDs.subtracting(desiredChatIDs)

        for chatID in chatsToClose {
            do {
                _ = try await sendRequest([
                    "@type": "closeChat",
                    "chat_id": chatID,
                ])
                openedWatchedChatIDs.remove(chatID)
            } catch {
                emitDebug("closeChat failed for \(chatID): \(error.localizedDescription)")
            }
        }

        for chatID in chatsToOpen {
            do {
                _ = try await sendRequest([
                    "@type": "openChat",
                    "chat_id": chatID,
                ])
                openedWatchedChatIDs.insert(chatID)
            } catch {
                emitDebug("openChat failed for \(chatID): \(error.localizedDescription)")
            }
        }
    }

    func fetchRecentPosts(for channel: WatchedChannel, limit: Int) async throws -> [UnreadPost] {
        guard client != nil else {
            throw TelegramServiceError.tdlibUnavailable
        }

        let historyChannel = try await refreshChannel(channel)
        let targetCount = max(0, limit)
        guard targetCount > 0 else {
            return []
        }

        let pageSize = min(100, max(limit * 2, 20))
        var posts: [UnreadPost] = []
        var seenMessageIDs = Set<Int64>()
        var fromMessageID: Int64 = 0

        for _ in 0..<6 {
            let response = try await sendRequest([
                "@type": "getChatHistory",
                "chat_id": historyChannel.chatID,
                "from_message_id": fromMessageID,
                "offset": 0,
                "limit": pageSize,
                "only_local": false,
            ])

            let messages = (response.array("messages") as? [TDLibObject]) ?? []
            guard messages.isEmpty == false else {
                break
            }

            for message in messages {
                guard let messageID = message.int64("id") else {
                    continue
                }

                if seenMessageIDs.insert(messageID).inserted == false {
                    continue
                }

                guard let post = TelegramParsing.parseUnreadPost(from: message, fallbackChannelTitle: historyChannel.title) else {
                    continue
                }

                posts.append(post)
            }

            if posts.count >= targetCount {
                break
            }

            guard let oldestMessageID = messages.compactMap({ $0.int64("id") }).last, oldestMessageID != fromMessageID else {
                break
            }
            fromMessageID = oldestMessageID
        }

        return Array(posts.sorted { lhs, rhs in
            if lhs.date == rhs.date {
                return lhs.messageID > rhs.messageID
            }
            return lhs.date > rhs.date
        }.prefix(limit))
    }

    func markPostAsRead(_ post: UnreadPost) async throws {
        guard client != nil else {
            throw TelegramServiceError.tdlibUnavailable
        }

        _ = try await sendRequest([
            "@type": "viewMessages",
            "chat_id": post.chatID,
            "message_ids": [post.messageID],
            "source": ["@type": "messageSourceChatHistory"],
            "force_read": true,
        ])

        _ = try? await sendRequest([
            "@type": "openMessageContent",
            "chat_id": post.chatID,
            "message_id": post.messageID,
        ])
    }

    func downloadMedia(
        for descriptor: TelegramMediaDescriptor,
        chatID: Int64?,
        messageID: Int64?
    ) async throws -> URL {
        guard client != nil else {
            throw TelegramServiceError.tdlibUnavailable
        }

        let chatID = descriptor.chatID ?? chatID
        let messageID = descriptor.messageID ?? messageID

        do {
            return try await downloadMediaFile(with: descriptor.fileID)
        } catch {
            guard let refreshedDescriptor = try? await refreshMediaDescriptor(
                for: descriptor,
                chatID: chatID,
                messageID: messageID
            ) else {
                throw error
            }
            return try await downloadMediaFile(with: refreshedDescriptor.fileID)
        }
    }

    private func downloadMediaFile(with fileID: Int32) async throws -> URL {
        return try await withCheckedThrowingContinuation { continuation in
            pendingFileDownloads[fileID] = continuation
            Task {
                do {
                    let response = try await self.sendRequest([
                        "@type": "downloadFile",
                        "file_id": fileID,
                        "priority": 16,
                        "offset": 0,
                        "limit": 0,
                        "synchronous": false,
                    ])

                    if let url = TelegramParsing.extractDownloadedFileURL(from: response) {
                        await MainActor.run {
                            self.pendingFileDownloads.removeValue(forKey: fileID)
                            continuation.resume(returning: url)
                        }
                    }
                } catch {
                    await MainActor.run {
                        self.pendingFileDownloads.removeValue(forKey: fileID)
                        continuation.resume(throwing: error)
                    }
                }
            }
        }
    }

    private func refreshMediaDescriptor(
        for descriptor: TelegramMediaDescriptor,
        chatID: Int64?,
        messageID: Int64?
    ) async throws -> TelegramMediaDescriptor {
        guard let chatID, let messageID else {
            throw TelegramServiceError.mediaUnavailable
        }

        guard client != nil else {
            throw TelegramServiceError.tdlibUnavailable
        }

        let response = try await sendRequest([
            "@type": "getMessage",
            "chat_id": chatID,
            "message_id": messageID,
        ])

        let message = response.dictionary("message") ?? response
        guard
            let post = TelegramParsing.parseUnreadPost(from: message, fallbackChannelTitle: ""),
            let refreshedDescriptor = post.mediaDescriptor,
            refreshedDescriptor.kind == descriptor.kind
        else {
            throw TelegramServiceError.mediaUnavailable
        }

        return refreshedDescriptor
    }

    private func handle(update: TDLibObject) async {
        switch update.tdType {
        case "updateAuthorizationState":
            emitDebug("Received updateAuthorizationState")
            await handleAuthorizationState(update.dictionary("authorization_state") ?? [:])

        case "updateConnectionState":
            let status = TelegramParsing.parseConnectionStatus(from: update.dictionary("state") ?? [:])
            onEvent?(.connectionChanged(status))
            emitDebug("Received connection state: \(describeConnectionStatus(status))")

        case "updateChatReadInbox":
            guard
                let chatID = update.int64("chat_id"),
                let lastReadInboxMessageID = update.int64("last_read_inbox_message_id"),
                let unreadCount = update.int32("unread_count")
            else {
                return
            }
            onEvent?(.chatUnreadStateChanged(
                chatID: chatID,
                lastReadInboxMessageID: lastReadInboxMessageID,
                unreadCount: Int(unreadCount)
            ))

        case "updateNewMessage":
            guard
                let message = update.dictionary("message"),
                let post = TelegramParsing.parseUnreadPost(from: message, fallbackChannelTitle: "")
            else {
                return
            }
            onEvent?(.unreadPost(post))

        case "updateFile":
            handleFileUpdate(update.dictionary("file") ?? [:])

        default:
            break
        }
    }

    private func handleAuthorizationState(_ object: TDLibObject) async {
        let state = TelegramParsing.parseAuthorizationState(from: object)
        currentAuthState = state
        onEvent?(.authChanged(state))
        emitDebug("Authorization state -> \(describeAuthState(state))")

        switch object.tdType {
        case "authorizationStateWaitTdlibParameters":
            do {
                try await setTDLibParameters()
            } catch {
                emitDebug("setTdlibParameters failed: \(error.localizedDescription)")
                onEvent?(.authChanged(.failed(error.localizedDescription)))
            }

        case "authorizationStateWaitPhoneNumber":
            do {
                try await requestQRCodeAuthentication()
            } catch {
                emitDebug("requestQrCodeAuthentication failed: \(error.localizedDescription)")
                onEvent?(.authChanged(.failed(error.localizedDescription)))
            }

        case "authorizationStateClosed":
            let shouldRestart = currentCredentials != nil
            if let client {
                await client.stop()
                self.client = nil
            }
            if shouldRestart {
                await start()
            }

        default:
            break
        }
    }

    private func setTDLibParameters() async throws {
        let credentials: TelegramCredentials?
        if let currentCredentials {
            credentials = currentCredentials
        } else {
            credentials = await storedCredentials()
        }
        guard let credentials else {
            throw TelegramServiceError.missingCredentials
        }

        let databaseDirectory = try ensureDirectory(named: "TDLibState")
        let mediaDirectory = try ensureDirectory(named: "TDLibTempMedia", inCaches: true)
        let encryptionKey = try secureStorage.loadValue(for: SecureStorageKey.databaseEncryptionKey) ?? ""
        emitDebug("Calling setTdlibParameters")

        try await sendRequestWithoutWaiting([
            "@type": "setTdlibParameters",
            "database_directory": databaseDirectory.path,
            "files_directory": mediaDirectory.path,
            "use_test_dc": false,
            "api_id": credentials.apiID,
            "api_hash": credentials.apiHash,
            "system_language_code": Locale.current.language.languageCode?.identifier ?? "en",
            "device_model": Self.deviceModelName,
            "system_version": ProcessInfo.processInfo.operatingSystemVersionString,
            "application_version": Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "0.8.4",
            "database_encryption_key": encryptionKey,
            "use_file_database": true,
            "use_chat_info_database": true,
            "use_message_database": true,
            "use_secret_chats": false,
            "enable_storage_optimizer": true,
            "ignore_file_names": true,
        ])
        scheduleAuthorizationStateRefresh(reason: "setTdlibParameters")
    }

    private static var deviceModelName: String {
        #if os(macOS)
        return Host.current().localizedName ?? "Mac"
        #elseif os(iOS)
        return UIDevice.current.model
        #else
        return ProcessInfo.processInfo.hostName
        #endif
    }

    private func handleFileUpdate(_ file: TDLibObject) {
        guard let fileID = file.int32("id"), let continuation = pendingFileDownloads[fileID] else {
            return
        }

        guard let url = TelegramParsing.extractDownloadedFileURL(from: file) else {
            return
        }

        pendingFileDownloads.removeValue(forKey: fileID)
        continuation.resume(returning: url)
    }

    private func storedCredentials() async -> TelegramCredentials? {
        guard
            let apiIDValue = try? secureStorage.loadValue(for: SecureStorageKey.apiID),
            let apiHash = try? secureStorage.loadValue(for: SecureStorageKey.apiHash),
            let apiID = Int32(apiIDValue)
        else {
            return nil
        }

        return TelegramCredentials(apiID: apiID, apiHash: apiHash)
    }

    private func normalizeChannelIdentifier(_ input: String) -> String? {
        let trimmed = input.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.isEmpty == false else {
            return nil
        }

        if trimmed.hasPrefix("@") {
            return String(trimmed.dropFirst())
        }

        if let url = URL(string: trimmed), let host = url.host() {
            let pathComponents = url.pathComponents.filter { $0 != "/" }
            guard ["t.me", "telegram.me", "www.t.me"].contains(host), let last = pathComponents.last else {
                return nil
            }
            return last == "s" ? nil : last
        }

        return trimmed.replacingOccurrences(of: "https://", with: "").replacingOccurrences(of: "http://", with: "").contains("/") ? nil : trimmed
    }

    private func resolveChannel(username: String) async throws -> WatchedChannel {
        guard client != nil else {
            throw TelegramServiceError.tdlibUnavailable
        }

        let response = try await sendRequest([
            "@type": "searchPublicChat",
            "username": username,
        ])
        return try TelegramParsing.parseChannel(from: response, fallbackUsername: username)
    }

    private func loadChannel(chatID: Int64, fallbackUsername: String?) async throws -> WatchedChannel {
        guard client != nil else {
            throw TelegramServiceError.tdlibUnavailable
        }

        let response = try await sendRequest([
            "@type": "getChat",
            "chat_id": chatID,
        ])
        return try TelegramParsing.parseChannel(from: response, fallbackUsername: fallbackUsername)
    }

    private func loadChannel(supergroupID: Int64, fallbackUsername: String?) async throws -> WatchedChannel {
        guard client != nil else {
            throw TelegramServiceError.tdlibUnavailable
        }

        do {
            let response = try await sendRequest([
                "@type": "createSupergroupChat",
                "supergroup_id": supergroupID,
                "force": false,
            ])
            return try TelegramParsing.parseChannel(from: response, fallbackUsername: fallbackUsername)
        } catch {
            let forcedResponse = try await sendRequest([
                "@type": "createSupergroupChat",
                "supergroup_id": supergroupID,
                "force": true,
            ])
            return try TelegramParsing.parseChannel(from: forcedResponse, fallbackUsername: fallbackUsername)
        }
    }

    private func normalizedStoredUsername(_ username: String?) -> String? {
        guard let username else {
            return nil
        }

        let trimmed = username.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.isEmpty == false else {
            return nil
        }

        let pattern = #"^[A-Za-z0-9_]+$"#
        guard trimmed.range(of: pattern, options: .regularExpression) != nil else {
            return nil
        }

        return trimmed
    }

    private func searchChannel(title: String, fallbackUsername: String?) async throws -> WatchedChannel {
        guard client != nil else {
            throw TelegramServiceError.tdlibUnavailable
        }

        let normalizedTitle = normalizeSearchQuery(title)
        guard normalizedTitle.isEmpty == false else {
            throw TelegramServiceError.invalidChannel
        }

        if let resolved = try await searchChannel(
            request: [
                "@type": "searchChatsOnServer",
                "query": normalizedTitle,
                "limit": 20,
            ],
            matchingTitle: normalizedTitle,
            fallbackUsername: fallbackUsername
        ) {
            return resolved
        }

        if let resolved = try await searchChannel(
            request: [
                "@type": "searchPublicChats",
                "query": normalizedTitle,
            ],
            matchingTitle: normalizedTitle,
            fallbackUsername: fallbackUsername
        ) {
            return resolved
        }

        throw TelegramServiceError.invalidChannel
    }

    private func searchChannel(
        request: TDLibObject,
        matchingTitle title: String,
        fallbackUsername: String?
    ) async throws -> WatchedChannel? {
        let response = try await sendRequest(request)
        let chatIDs = (response.array("chat_ids") ?? []).compactMap { value -> Int64? in
            switch value {
            case let id as Int64:
                return id
            case let id as Int:
                return Int64(id)
            case let id as NSNumber:
                return id.int64Value
            default:
                return nil
            }
        }

        var partialMatch: WatchedChannel?
        for chatID in chatIDs {
            guard let candidate = try? await loadChannel(chatID: chatID, fallbackUsername: fallbackUsername) else {
                continue
            }

            if candidate.title.compare(title, options: [.caseInsensitive, .diacriticInsensitive]) == .orderedSame {
                return candidate
            }

            if partialMatch == nil {
                let normalizedCandidateTitle = normalizeSearchQuery(candidate.title)
                if normalizedCandidateTitle.contains(title) || title.contains(normalizedCandidateTitle) {
                    partialMatch = candidate
                }
            }
        }

        return partialMatch
    }

    private func normalizeSearchQuery(_ value: String) -> String {
        value
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .folding(options: [.caseInsensitive, .diacriticInsensitive], locale: .current)
    }

    private func ensureDirectory(named name: String, inCaches: Bool = false) throws -> URL {
        let baseDirectory = fileManager.urls(for: inCaches ? .cachesDirectory : .applicationSupportDirectory, in: .userDomainMask)[0]
        migrateLegacyBaseDirectoryIfNeeded(inCaches: inCaches)
        let directory = baseDirectory
            .appendingPathComponent(StorageDirectoryName.current, isDirectory: true)
            .appendingPathComponent(name, isDirectory: true)
        try fileManager.createDirectory(at: directory, withIntermediateDirectories: true)
        return directory
    }

    private func cleanTemporaryMediaCache() {
        migrateLegacyBaseDirectoryIfNeeded(inCaches: true)
        guard let caches = fileManager.urls(for: .cachesDirectory, in: .userDomainMask).first else {
            return
        }

        let directory = caches
            .appendingPathComponent(StorageDirectoryName.current, isDirectory: true)
            .appendingPathComponent("TDLibTempMedia", isDirectory: true)
        guard let children = try? fileManager.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil) else {
            return
        }

        for child in children {
            try? fileManager.removeItem(at: child)
        }
    }

    private func cleanTDLibState() {
        migrateLegacyBaseDirectoryIfNeeded(inCaches: false)
        guard let appSupport = fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask).first else {
            return
        }

        let directory = appSupport
            .appendingPathComponent(StorageDirectoryName.current, isDirectory: true)
            .appendingPathComponent("TDLibState", isDirectory: true)
        try? fileManager.removeItem(at: directory)
    }

    private func migrateLegacyBaseDirectoryIfNeeded(inCaches: Bool) {
        let baseDirectory = fileManager.urls(for: inCaches ? .cachesDirectory : .applicationSupportDirectory, in: .userDomainMask)[0]
        let currentDirectory = baseDirectory.appendingPathComponent(StorageDirectoryName.current, isDirectory: true)
        let legacyDirectory = baseDirectory.appendingPathComponent(StorageDirectoryName.legacy, isDirectory: true)

        guard
            fileManager.fileExists(atPath: legacyDirectory.path),
            fileManager.fileExists(atPath: currentDirectory.path) == false
        else {
            return
        }

        try? fileManager.moveItem(at: legacyDirectory, to: currentDirectory)
    }

    private func deserialize(_ string: String) -> TDLibObject? {
        guard
            let data = string.data(using: .utf8),
            let json = try? JSONSerialization.jsonObject(with: data) as? TDLibObject
        else {
            return nil
        }
        return json
    }

    private func sendRequest(_ request: TDLibObject) async throws -> TDLibObject {
        guard let client else {
            throw TelegramServiceError.tdlibUnavailable
        }

        let extra = UUID().uuidString
        var payload = request
        payload["@extra"] = extra

        guard
            let data = try? JSONSerialization.data(withJSONObject: payload, options: []),
            let requestString = String(data: data, encoding: .utf8)
        else {
            throw TDLibError(code: -1, message: "Unable to encode TDLib request.")
        }

        let responseString = try await client.send(requestString, extra: extra)
        guard let object = deserialize(responseString) else {
            throw TDLibError(code: -1, message: "Invalid TDLib response.")
        }
        return object
    }

    private func sendRequestWithoutWaiting(_ request: TDLibObject) async throws {
        guard let client else {
            throw TelegramServiceError.tdlibUnavailable
        }

        guard
            let data = try? JSONSerialization.data(withJSONObject: request, options: []),
            let requestString = String(data: data, encoding: .utf8)
        else {
            throw TDLibError(code: -1, message: "Unable to encode TDLib request.")
        }

        try await client.sendWithoutResponse(requestString)
    }

    private func scheduleAuthorizationStateRefresh(reason: String) {
        emitDebug("Scheduling authorization state refresh after \(reason)")

        Task { @MainActor [weak self] in
            guard let self else {
                return
            }

            for attempt in 1...12 {
                try? await Task.sleep(for: .milliseconds(300))
                await self.refreshAuthorizationState()

                if self.isTransientAuthorizationState(self.currentAuthState) == false {
                    self.emitDebug("Authorization state stabilized after \(reason) on attempt \(attempt)")
                    break
                }
            }
        }
    }

    private func isTransientAuthorizationState(_ state: TelegramAuthState) -> Bool {
        switch state {
        case .initializing:
            return true
        default:
            return false
        }
    }

    private func emitDebug(_ message: String) {
        logger.notice("\(message, privacy: .public)")
        print("[TeleFeed] \(message)")
        onEvent?(.debug(message))
    }

    private func describeAuthState(_ state: TelegramAuthState) -> String {
        switch state {
        case .missingCredentials:
            return "missingCredentials"
        case .initializing:
            return "initializing"
        case .waitingPhoneNumber:
            return "waitingPhoneNumber"
        case .waitingForQRCode(let link):
            return "waitingForQRCode(\(link ?? "no-link"))"
        case .waitingPassword(let hint):
            return "waitingPassword(\(hint))"
        case .ready:
            return "ready"
        case .loggingOut:
            return "loggingOut"
        case .closed:
            return "closed"
        case .failed(let message):
            return "failed(\(message))"
        }
    }

    private func describeConnectionStatus(_ status: TelegramConnectionStatus) -> String {
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
}
