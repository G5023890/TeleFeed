import Foundation

enum TelegramMediaKind: String, Hashable, Codable {
    case photo
    case video
}

struct TelegramMediaDescriptor: Hashable {
    let fileID: Int32
    let kind: TelegramMediaKind
}

struct UnreadPostIdentity: Hashable, Codable {
    let chatID: Int64
    let messageID: Int64
}

enum TelegramPostContent: Hashable {
    case text(body: String)
    case photo(caption: String, media: TelegramMediaDescriptor)
    case video(caption: String, media: TelegramMediaDescriptor, duration: Int)
    case unsupported(summary: String)
}

struct UnreadPost: Hashable, Identifiable {
    let chatID: Int64
    let messageID: Int64
    let channelTitle: String
    let author: String?
    let date: Date
    let content: TelegramPostContent

    var id: UnreadPostIdentity { UnreadPostIdentity(chatID: chatID, messageID: messageID) }
    var globalID: UnreadPostIdentity { id }

    var summary: String {
        switch content {
        case .text(let body):
            return body
        case .photo(let caption, _):
            return caption.isEmpty ? "Photo" : caption
        case .video(let caption, _, _):
            return caption.isEmpty ? "Video" : caption
        case .unsupported(let summary):
            return summary
        }
    }

    var mediaDescriptor: TelegramMediaDescriptor? {
        switch content {
        case .photo(_, let media):
            return media
        case .video(_, let media, _):
            return media
        case .text, .unsupported:
            return nil
        }
    }

    func updatingChannelTitle(_ title: String) -> UnreadPost {
        UnreadPost(
            chatID: chatID,
            messageID: messageID,
            channelTitle: title,
            author: author,
            date: date,
            content: content
        )
    }
}
