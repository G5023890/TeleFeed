import Foundation

enum UnreadPostSourceKind: String, Codable, Hashable {
    case telegram
    case rss
}

enum TelegramMediaKind: String, Hashable, Codable {
    case photo
    case video
}

struct TelegramMediaDescriptor: Hashable, Codable {
    let fileID: Int32
    let kind: TelegramMediaKind
    let chatID: Int64?
    let messageID: Int64?

    init(fileID: Int32, kind: TelegramMediaKind, chatID: Int64? = nil, messageID: Int64? = nil) {
        self.fileID = fileID
        self.kind = kind
        self.chatID = chatID
        self.messageID = messageID
    }

    private enum CodingKeys: String, CodingKey {
        case fileID
        case kind
        case chatID
        case messageID
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        fileID = try container.decode(Int32.self, forKey: .fileID)
        kind = try container.decode(TelegramMediaKind.self, forKey: .kind)
        chatID = try container.decodeIfPresent(Int64.self, forKey: .chatID)
        messageID = try container.decodeIfPresent(Int64.self, forKey: .messageID)
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(fileID, forKey: .fileID)
        try container.encode(kind, forKey: .kind)
        try container.encodeIfPresent(chatID, forKey: .chatID)
        try container.encodeIfPresent(messageID, forKey: .messageID)
    }
}

struct UnreadPostIdentity: Hashable, Codable {
    let sourceKind: UnreadPostSourceKind
    let sourceIdentifier: String
    let messageID: Int64

    init(sourceKind: UnreadPostSourceKind, sourceIdentifier: String, messageID: Int64) {
        self.sourceKind = sourceKind
        self.sourceIdentifier = sourceIdentifier
        self.messageID = messageID
    }

    private enum CodingKeys: String, CodingKey {
        case sourceKind
        case sourceIdentifier
        case chatID
        case messageID
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)

        if let sourceKind = try container.decodeIfPresent(UnreadPostSourceKind.self, forKey: .sourceKind),
           let sourceIdentifier = try container.decodeIfPresent(String.self, forKey: .sourceIdentifier) {
            self.sourceKind = sourceKind
            self.sourceIdentifier = sourceIdentifier
            self.messageID = try container.decode(Int64.self, forKey: .messageID)
            return
        }

        let chatID = try container.decode(Int64.self, forKey: .chatID)
        self.sourceKind = .telegram
        self.sourceIdentifier = String(chatID)
        self.messageID = try container.decode(Int64.self, forKey: .messageID)
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(sourceKind, forKey: .sourceKind)
        try container.encode(sourceIdentifier, forKey: .sourceIdentifier)
        try container.encode(messageID, forKey: .messageID)
        if sourceKind == .telegram, let chatID = Int64(sourceIdentifier) {
            try container.encode(chatID, forKey: .chatID)
        }
    }
}

enum TelegramPostContent: Hashable, Codable {
    case text(body: String)
    case photo(caption: String, media: TelegramMediaDescriptor)
    case video(caption: String, media: TelegramMediaDescriptor, duration: Int)
    case unsupported(summary: String)

    private enum CodingKeys: String, CodingKey {
        case kind
        case body
        case caption
        case media
        case duration
        case summary
    }

    private enum Kind: String, Codable {
        case text
        case photo
        case video
        case unsupported
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        switch try container.decode(Kind.self, forKey: .kind) {
        case .text:
            self = .text(body: try container.decode(String.self, forKey: .body))
        case .photo:
            self = .photo(
                caption: try container.decode(String.self, forKey: .caption),
                media: try container.decode(TelegramMediaDescriptor.self, forKey: .media)
            )
        case .video:
            self = .video(
                caption: try container.decode(String.self, forKey: .caption),
                media: try container.decode(TelegramMediaDescriptor.self, forKey: .media),
                duration: try container.decode(Int.self, forKey: .duration)
            )
        case .unsupported:
            self = .unsupported(summary: try container.decode(String.self, forKey: .summary))
        }
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        switch self {
        case .text(let body):
            try container.encode(Kind.text, forKey: .kind)
            try container.encode(body, forKey: .body)
        case .photo(let caption, let media):
            try container.encode(Kind.photo, forKey: .kind)
            try container.encode(caption, forKey: .caption)
            try container.encode(media, forKey: .media)
        case .video(let caption, let media, let duration):
            try container.encode(Kind.video, forKey: .kind)
            try container.encode(caption, forKey: .caption)
            try container.encode(media, forKey: .media)
            try container.encode(duration, forKey: .duration)
        case .unsupported(let summary):
            try container.encode(Kind.unsupported, forKey: .kind)
            try container.encode(summary, forKey: .summary)
        }
    }
}

struct UnreadPost: Hashable, Identifiable, Codable {
    let sourceKind: UnreadPostSourceKind
    let sourceIdentifier: String
    let chatID: Int64
    let messageID: Int64
    let channelTitle: String
    let author: String?
    let date: Date
    let hasPublicationDate: Bool
    let articleURL: URL?
    let content: TelegramPostContent

    private enum CodingKeys: String, CodingKey {
        case sourceKind
        case sourceIdentifier
        case chatID
        case messageID
        case channelTitle
        case author
        case date
        case hasPublicationDate
        case articleURL
        case content
    }

    var id: UnreadPostIdentity {
        UnreadPostIdentity(sourceKind: sourceKind, sourceIdentifier: sourceIdentifier, messageID: messageID)
    }
    var globalID: UnreadPostIdentity { id }
    var isRSS: Bool { sourceKind == .rss }

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

    var titleOrFallback: String {
        switch content {
        case .text(let body):
            return body.split(separator: "\n").first.map(String.init) ?? summary
        case .photo(let caption, _):
            return caption.isEmpty ? summary : caption
        case .video(let caption, _, _):
            return caption.isEmpty ? summary : caption
        case .unsupported(let summary):
            return summary
        }
    }

    init(
        sourceKind: UnreadPostSourceKind,
        sourceIdentifier: String,
        chatID: Int64,
        messageID: Int64,
        channelTitle: String,
        author: String?,
        date: Date,
        hasPublicationDate: Bool = true,
        articleURL: URL? = nil,
        content: TelegramPostContent
    ) {
        self.sourceKind = sourceKind
        self.sourceIdentifier = sourceIdentifier
        self.chatID = chatID
        self.messageID = messageID
        self.channelTitle = channelTitle
        self.author = author
        self.date = date
        self.hasPublicationDate = hasPublicationDate
        self.articleURL = articleURL
        self.content = content
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let chatID = try container.decode(Int64.self, forKey: .chatID)
        let messageID = try container.decode(Int64.self, forKey: .messageID)
        self.sourceKind = try container.decodeIfPresent(UnreadPostSourceKind.self, forKey: .sourceKind) ?? .telegram
        if let sourceIdentifier = try container.decodeIfPresent(String.self, forKey: .sourceIdentifier) {
            self.sourceIdentifier = sourceIdentifier
        } else {
            self.sourceIdentifier = String(chatID)
        }
        self.chatID = chatID
        self.messageID = messageID
        self.channelTitle = try container.decode(String.self, forKey: .channelTitle)
        self.author = try container.decodeIfPresent(String.self, forKey: .author)
        self.date = try container.decode(Date.self, forKey: .date)
        self.hasPublicationDate = try container.decodeIfPresent(Bool.self, forKey: .hasPublicationDate) ?? true
        self.articleURL = try container.decodeIfPresent(URL.self, forKey: .articleURL)
        self.content = try container.decode(TelegramPostContent.self, forKey: .content)
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(sourceKind, forKey: .sourceKind)
        try container.encode(sourceIdentifier, forKey: .sourceIdentifier)
        try container.encode(chatID, forKey: .chatID)
        try container.encode(messageID, forKey: .messageID)
        try container.encode(channelTitle, forKey: .channelTitle)
        try container.encodeIfPresent(author, forKey: .author)
        try container.encode(date, forKey: .date)
        try container.encode(hasPublicationDate, forKey: .hasPublicationDate)
        try container.encodeIfPresent(articleURL, forKey: .articleURL)
        try container.encode(content, forKey: .content)
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
            sourceKind: sourceKind,
            sourceIdentifier: sourceIdentifier,
            chatID: chatID,
            messageID: messageID,
            channelTitle: title,
            author: author,
            date: date,
            hasPublicationDate: hasPublicationDate,
            articleURL: articleURL,
            content: content
        )
    }
}
