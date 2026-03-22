import Foundation

typealias TDLibObject = [String: Any]

extension Dictionary where Key == String, Value == Any {
    var tdType: String? { self["@type"] as? String }

    func string(_ key: String) -> String? {
        self[key] as? String
    }

    func bool(_ key: String) -> Bool? {
        self[key] as? Bool
    }

    func int64(_ key: String) -> Int64? {
        switch self[key] {
        case let value as Int64:
            return value
        case let value as Int:
            return Int64(value)
        case let value as Double:
            return Int64(value)
        case let value as NSNumber:
            return value.int64Value
        default:
            return nil
        }
    }

    func int32(_ key: String) -> Int32? {
        switch self[key] {
        case let value as Int32:
            return value
        case let value as Int:
            return Int32(value)
        case let value as Double:
            return Int32(value)
        case let value as NSNumber:
            return value.int32Value
        default:
            return nil
        }
    }

    func dictionary(_ key: String) -> TDLibObject? {
        self[key] as? TDLibObject
    }

    func array(_ key: String) -> [Any]? {
        self[key] as? [Any]
    }
}

enum TelegramParsing {
    static func parseChannel(from object: TDLibObject, fallbackUsername: String? = nil) throws -> WatchedChannel {
        guard
            let chatID = object.int64("id"),
            let title = object.string("title"),
            let type = object.dictionary("type"),
            type.tdType == "chatTypeSupergroup",
            type.bool("is_channel") == true
        else {
            throw TelegramServiceError.invalidChannel
        }

        let usernames = object.dictionary("usernames")
        let username = usernames?.string("editable_username")
            ?? usernames?.array("active_usernames")?.compactMap { $0 as? String }.first
            ?? object.string("username")
            ?? fallbackUsername
            ?? ""

        return WatchedChannel(
            chatID: chatID,
            supergroupID: type.int64("supergroup_id"),
            title: title,
            username: username,
            unreadCount: Int(object.int32("unread_count") ?? 0),
            lastReadInboxMessageID: object.int64("last_read_inbox_message_id") ?? 0,
            lastNotifiedMessageID: nil
        )
    }

    static func parseUnreadPost(from object: TDLibObject, fallbackChannelTitle: String) -> UnreadPost? {
        guard
            let chatID = object.int64("chat_id"),
            let messageID = object.int64("id"),
            let timestamp = object.int64("date"),
            let content = object.dictionary("content")
        else {
            return nil
        }

        let author = object.string("author_signature")
        let channelTitle = object.string("chat_title") ?? fallbackChannelTitle
        let parsedContent = parseContent(from: content)

        return UnreadPost(
            chatID: chatID,
            messageID: messageID,
            channelTitle: channelTitle,
            author: author?.isEmpty == true ? nil : author,
            date: Date(timeIntervalSince1970: TimeInterval(timestamp)),
            content: parsedContent
        )
    }

    static func parseConnectionStatus(from object: TDLibObject) -> TelegramConnectionStatus {
        switch object.tdType {
        case "connectionStateReady":
            return .ready
        case "connectionStateUpdating":
            return .updating
        case "connectionStateWaitingForNetwork":
            return .waitingForNetwork
        case "connectionStateConnecting", "connectionStateConnectingToProxy":
            return .connecting
        default:
            return .offline
        }
    }

    static func parseAuthorizationState(from object: TDLibObject) -> TelegramAuthState {
        switch object.tdType {
        case "authorizationStateWaitPhoneNumber":
            return .waitingPhoneNumber
        case "authorizationStateWaitOtherDeviceConfirmation":
            return .waitingForQRCode(link: object.string("link"))
        case "authorizationStateWaitPassword":
            return .waitingPassword(hint: object.string("password_hint") ?? "")
        case "authorizationStateReady":
            return .ready
        case "authorizationStateLoggingOut", "authorizationStateClosing":
            return .loggingOut
        case "authorizationStateClosed":
            return .closed
        default:
            return .initializing
        }
    }

    static func extractDownloadedFileURL(from object: TDLibObject) -> URL? {
        guard
            let local = object.dictionary("local"),
            local.bool("is_downloading_completed") == true,
            let path = local.string("path"),
            path.isEmpty == false
        else {
            return nil
        }

        return URL(fileURLWithPath: path)
    }

    private static func parseContent(from object: TDLibObject) -> TelegramPostContent {
        switch object.tdType {
        case "messageText":
            let body = object.dictionary("text")?.string("text") ?? ""
            return .text(body: body)

        case "messagePhoto":
            let caption = object.dictionary("caption")?.string("text") ?? ""
            if let photo = object.dictionary("photo") {
                let sizeObjects = photo.array("sizes")?.compactMap { $0 as? TDLibObject } ?? []
                let fileID = sizeObjects.reversed().compactMap { size -> Int32? in
                    if let file = size.dictionary("photo"), let id = file.int32("id") {
                        return id
                    }
                    if let id = size.int32("photo") {
                        return id
                    }
                    if let file = size.dictionary("file"), let id = file.int32("id") {
                        return id
                    }
                    return nil
                }.first

                if let fileID {
                    return .photo(caption: caption, media: TelegramMediaDescriptor(fileID: fileID, kind: .photo))
                }
            }
            return .unsupported(summary: caption.isEmpty ? L10n.tr("feed.unsupported") : caption)

        case "messageVideo":
            let caption = object.dictionary("caption")?.string("text") ?? ""
            if
                let video = object.dictionary("video"),
                let file = video.dictionary("video"),
                let fileID = file.int32("id")
            {
                return .video(
                    caption: caption,
                    media: TelegramMediaDescriptor(fileID: fileID, kind: .video),
                    duration: Int(video.int32("duration") ?? 0)
                )
            }
            return .unsupported(summary: caption.isEmpty ? L10n.tr("feed.unsupported") : caption)

        default:
            return .unsupported(summary: L10n.tr("feed.unsupported"))
        }
    }
}
