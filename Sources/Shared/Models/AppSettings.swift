import Foundation

enum MenuBarIconStyle: String, Codable, CaseIterable, Equatable {
    case current
    case telegramRSS
    case telegramRSS2
}

struct TypographySettings: Codable, Equatable {
    var feedHeaderTitle: Double = 19
    var feedTitle: Double = 14
    var feedSource: Double = 11
    var feedBody: Double = 13
    var feedDate: Double = 11
    var feedFilter: Double = 12.5

    var viewerChannelTitle: Double = 16
    var viewerTitle: Double = 22
    var viewerMeta: Double = 13
    var viewerBody: Double = 18
    var viewerCaption: Double = 15

    var readerChannelTitle: Double = 16
    var readerTitle: Double = 22
    var readerMeta: Double = 13
    var readerBody: Double = 18
    var readerQuote: Double = 17
    var readerListBullet: Double = 17
    var readerCode: Double = 15
    var readerHeading1: Double = 28
    var readerHeading2: Double = 24
    var readerHeading3: Double = 21
    var readerHeading4: Double = 19
    var readerHeading5: Double = 17
    var readerHeading6: Double = 17

    private enum CodingKeys: String, CodingKey {
        case feedHeaderTitle
        case feedTitle
        case feedSource
        case feedBody
        case feedDate
        case feedFilter
        case viewerChannelTitle
        case viewerTitle
        case viewerMeta
        case viewerBody
        case viewerCaption
        case readerChannelTitle
        case readerTitle
        case readerMeta
        case readerBody
        case readerQuote
        case readerListBullet
        case readerCode
        case readerHeading1
        case readerHeading2
        case readerHeading3
        case readerHeading4
        case readerHeading5
        case readerHeading6
    }

    init() {}

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        feedHeaderTitle = try container.decodeIfPresent(Double.self, forKey: .feedHeaderTitle) ?? 19
        feedTitle = try container.decodeIfPresent(Double.self, forKey: .feedTitle) ?? 14
        feedSource = try container.decodeIfPresent(Double.self, forKey: .feedSource) ?? 11
        feedBody = try container.decodeIfPresent(Double.self, forKey: .feedBody) ?? 13
        feedDate = try container.decodeIfPresent(Double.self, forKey: .feedDate) ?? 11
        feedFilter = try container.decodeIfPresent(Double.self, forKey: .feedFilter) ?? 12.5

        viewerChannelTitle = try container.decodeIfPresent(Double.self, forKey: .viewerChannelTitle) ?? 16
        viewerTitle = try container.decodeIfPresent(Double.self, forKey: .viewerTitle) ?? 22
        viewerMeta = try container.decodeIfPresent(Double.self, forKey: .viewerMeta) ?? 13
        viewerBody = try container.decodeIfPresent(Double.self, forKey: .viewerBody) ?? 18
        viewerCaption = try container.decodeIfPresent(Double.self, forKey: .viewerCaption) ?? 15

        readerChannelTitle = try container.decodeIfPresent(Double.self, forKey: .readerChannelTitle) ?? 16
        readerTitle = try container.decodeIfPresent(Double.self, forKey: .readerTitle) ?? 22
        readerMeta = try container.decodeIfPresent(Double.self, forKey: .readerMeta) ?? 13
        readerBody = try container.decodeIfPresent(Double.self, forKey: .readerBody) ?? 18
        readerQuote = try container.decodeIfPresent(Double.self, forKey: .readerQuote) ?? 17
        readerListBullet = try container.decodeIfPresent(Double.self, forKey: .readerListBullet) ?? 17
        readerCode = try container.decodeIfPresent(Double.self, forKey: .readerCode) ?? 15
        readerHeading1 = try container.decodeIfPresent(Double.self, forKey: .readerHeading1) ?? 28
        readerHeading2 = try container.decodeIfPresent(Double.self, forKey: .readerHeading2) ?? 24
        readerHeading3 = try container.decodeIfPresent(Double.self, forKey: .readerHeading3) ?? 21
        readerHeading4 = try container.decodeIfPresent(Double.self, forKey: .readerHeading4) ?? 19
        readerHeading5 = try container.decodeIfPresent(Double.self, forKey: .readerHeading5) ?? 17
        readerHeading6 = try container.decodeIfPresent(Double.self, forKey: .readerHeading6) ?? 17
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(feedHeaderTitle, forKey: .feedHeaderTitle)
        try container.encode(feedTitle, forKey: .feedTitle)
        try container.encode(feedSource, forKey: .feedSource)
        try container.encode(feedBody, forKey: .feedBody)
        try container.encode(feedDate, forKey: .feedDate)
        try container.encode(feedFilter, forKey: .feedFilter)
        try container.encode(viewerChannelTitle, forKey: .viewerChannelTitle)
        try container.encode(viewerTitle, forKey: .viewerTitle)
        try container.encode(viewerMeta, forKey: .viewerMeta)
        try container.encode(viewerBody, forKey: .viewerBody)
        try container.encode(viewerCaption, forKey: .viewerCaption)
        try container.encode(readerChannelTitle, forKey: .readerChannelTitle)
        try container.encode(readerTitle, forKey: .readerTitle)
        try container.encode(readerMeta, forKey: .readerMeta)
        try container.encode(readerBody, forKey: .readerBody)
        try container.encode(readerQuote, forKey: .readerQuote)
        try container.encode(readerListBullet, forKey: .readerListBullet)
        try container.encode(readerCode, forKey: .readerCode)
        try container.encode(readerHeading1, forKey: .readerHeading1)
        try container.encode(readerHeading2, forKey: .readerHeading2)
        try container.encode(readerHeading3, forKey: .readerHeading3)
        try container.encode(readerHeading4, forKey: .readerHeading4)
        try container.encode(readerHeading5, forKey: .readerHeading5)
        try container.encode(readerHeading6, forKey: .readerHeading6)
    }
}

struct AppSettings: Codable, Equatable {
    var launchAtLoginEnabled: Bool = true
    var typography: TypographySettings = TypographySettings()
    var menuBarIconStyle: MenuBarIconStyle = .current

    private enum CodingKeys: String, CodingKey {
        case launchAtLoginEnabled
        case typography
        case menuBarIconStyle
    }

    init() {}

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        launchAtLoginEnabled = try container.decodeIfPresent(Bool.self, forKey: .launchAtLoginEnabled) ?? true
        typography = try container.decodeIfPresent(TypographySettings.self, forKey: .typography) ?? TypographySettings()
        menuBarIconStyle = try container.decodeIfPresent(MenuBarIconStyle.self, forKey: .menuBarIconStyle) ?? .current
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(launchAtLoginEnabled, forKey: .launchAtLoginEnabled)
        try container.encode(typography, forKey: .typography)
        try container.encode(menuBarIconStyle, forKey: .menuBarIconStyle)
    }
}

struct TelegramCredentials: Equatable {
    let apiID: Int32
    let apiHash: String
}
