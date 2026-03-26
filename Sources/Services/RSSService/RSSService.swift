import Foundation
import OSLog

final class RSSService: RSSServiceProtocol, @unchecked Sendable {
    private static let logger = Logger(subsystem: "com.codex.Telega", category: "RSSService")
    private let session: URLSession
    private let userAgent = "Mozilla/5.0 (Macintosh; Intel Mac OS X 15_0) AppleWebKit/605.1.15 (KHTML, like Gecko) Telega/1.0 Safari/605.1.15"

    init(session: URLSession = .shared) {
        self.session = session
    }

    func resolveFeed(from input: String) async throws -> RSSFeedSource {
        let url = try normalizedFeedURL(from: input)
        let response = try await fetchAndParse(from: url)
        Self.logger.debug("Resolved RSS feed \(url.absoluteString, privacy: .public) with \(response.items.count, privacy: .public) items")
        return RSSFeedSource(
            urlString: url.absoluteString,
            title: response.title ?? defaultTitle(for: url),
            lastItemIdentifier: nil
        )
    }

    func refreshFeed(_ source: RSSFeedSource, limit: Int) async throws -> RSSFeedRefreshResult {
        guard let url = source.feedURL else {
            throw RSSServiceError.invalidURL
        }

        let response = try await fetchAndParse(from: url)
        let title = response.title ?? source.title
        let items = Self.sortedItems(response.items)
        let newPosts = Self.makePosts(
            feed: RSSFeedSource(
                urlString: url.absoluteString,
                title: title,
                lastItemIdentifier: source.lastItemIdentifier
            ),
            items: items,
            limit: limit
        )

        let updatedSource = RSSFeedSource(
            urlString: url.absoluteString,
            title: title,
            lastItemIdentifier: items.first?.identifier ?? source.lastItemIdentifier
        )
        Self.logger.debug("Refreshed RSS feed \(url.absoluteString, privacy: .public) -> \(newPosts.count, privacy: .public) new posts, lastItem=\(updatedSource.lastItemIdentifier ?? "nil", privacy: .public)")
        return RSSFeedRefreshResult(source: updatedSource, posts: newPosts)
    }

    private func fetchAndParse(from url: URL) async throws -> RSSParseResult {
        var request = URLRequest(url: url)
        request.setValue(userAgent, forHTTPHeaderField: "User-Agent")
        request.setValue("application/rss+xml, application/xml, text/xml, */*;q=0.8", forHTTPHeaderField: "Accept")
        request.setValue("en-US,en;q=0.9", forHTTPHeaderField: "Accept-Language")
        let (data, response) = try await session.data(for: request)
        if let httpResponse = response as? HTTPURLResponse {
            Self.logger.debug("RSS response \(url.absoluteString, privacy: .public) status=\(httpResponse.statusCode, privacy: .public)")
        }
        guard data.isEmpty == false else {
            throw RSSServiceError.invalidFeed
        }

        return try RSSXMLParser().parse(data: data)
    }

    private func normalizedFeedURL(from input: String) throws -> URL {
        let trimmed = input.trimmingCharacters(in: .whitespacesAndNewlines)
        guard
            let url = URL(string: trimmed),
            let scheme = url.scheme?.lowercased(),
            ["http", "https"].contains(scheme)
        else {
            throw RSSServiceError.invalidURL
        }
        return url
    }

    private func defaultTitle(for url: URL) -> String {
        url.host?.replacingOccurrences(of: "www.", with: "") ?? url.absoluteString
    }

    private static func makePosts(feed: RSSFeedSource, items: [RSSParsedItem], limit: Int) -> [UnreadPost] {
        let sourceIdentifier = feed.urlString
        let sourceChatID = stableSignedID("rss-feed:\(sourceIdentifier)")
        var result: [UnreadPost] = []
        for item in items.prefix(limit) {
            if let knownLast = feed.lastItemIdentifier, item.identifier == knownLast {
                break
            }

            let post = UnreadPost(
                sourceKind: .rss,
                sourceIdentifier: sourceIdentifier,
                chatID: sourceChatID,
                messageID: stableSignedID("rss-item:\(sourceIdentifier):\(item.identifier)"),
                channelTitle: feed.title,
                author: item.author.isEmpty ? nil : item.author,
                date: item.date,
                articleURL: item.link,
                content: .text(body: item.body)
            )
            result.append(post)
        }
        return result
    }

    private static func sortedItems(_ items: [RSSParsedItem]) -> [RSSParsedItem] {
        items.sorted { lhs, rhs in
            if lhs.date == rhs.date {
                return lhs.identifier > rhs.identifier
            }
            return lhs.date > rhs.date
        }
    }

    private static func stableSignedID(_ string: String) -> Int64 {
        let hash = stableHash64(string)
        let signed = Int64(bitPattern: hash)
        return signed == 0 ? 1 : signed
    }
}

private struct RSSParseResult {
    let title: String?
    let items: [RSSParsedItem]
}

private struct RSSParsedItem {
    let identifier: String
    let title: String
    let body: String
    let author: String
    let date: Date
    let link: URL?
}

private final class RSSXMLParser: NSObject, XMLParserDelegate {
    private var feedTitle: String?
    private var items: [RSSParsedItem] = []
    private var currentText = ""
    private var currentItem: RSSDraftItem?
    private var currentPath: [String] = []
    private var currentElementName: String?
    private var currentLinkHref: String?
    private var insideLinkElement = false

    func parse(data: Data) throws -> RSSParseResult {
        let parser = XMLParser(data: data)
        parser.delegate = self
        guard parser.parse() else {
            throw RSSServiceError.invalidFeed
        }
        return RSSParseResult(title: feedTitle?.trimmingCharacters(in: .whitespacesAndNewlines), items: items)
    }

    func parser(_ parser: XMLParser, didStartElement elementName: String, namespaceURI: String?, qualifiedName qName: String?, attributes attributeDict: [String : String] = [:]) {
        currentPath.append(elementName)
        currentElementName = elementName
        currentText = ""

        switch normalizedElementName(elementName) {
        case "item", "entry":
            currentItem = RSSDraftItem()
        case "link" where currentItem != nil:
            insideLinkElement = true
            currentLinkHref = attributeDict["href"]
        default:
            break
        }
    }

    func parser(_ parser: XMLParser, foundCharacters string: String) {
        currentText += string
    }

    func parser(_ parser: XMLParser, didEndElement elementName: String, namespaceURI: String?, qualifiedName qName: String?) {
        let text = currentText.trimmingCharacters(in: .whitespacesAndNewlines)

        switch normalizedElementName(elementName) {
        case "title":
            if currentItem == nil {
                feedTitle = feedTitle ?? text
            } else {
                updateCurrentItem { $0.title = $0.title ?? text }
            }
        case "description", "summary", "content":
            updateCurrentItem { $0.body = $0.body ?? sanitizeHTML(text) }
        case "author", "creator":
            updateCurrentItem { $0.author = $0.author ?? text }
        case "name":
            if currentItem != nil {
                updateCurrentItem { $0.author = $0.author ?? text }
            }
        case "guid", "id":
            updateCurrentItem { $0.identifier = $0.identifier ?? text }
        case "pubdate", "published", "updated", "date":
            updateCurrentItem { $0.date = $0.date ?? parseDate(text) }
        case "link":
            if insideLinkElement {
                updateCurrentItem { $0.link = $0.link ?? currentLinkHref ?? text }
                insideLinkElement = false
                currentLinkHref = nil
            } else if currentItem == nil {
                feedTitle = feedTitle ?? text
            }
        case "item", "entry":
            if let item = currentItem?.makeItem() {
                items.append(item)
            }
            currentItem = nil
        default:
            break
        }

        _ = currentPath.popLast()
        currentElementName = currentPath.last
        currentText = ""
    }

    private func parseDate(_ string: String) -> Date? {
        if let date = Self.makeRFC822Formatter().date(from: string) {
            return date
        }
        if let date = Self.makeRFC2822Formatter().date(from: string) {
            return date
        }
        if let date = Self.makeISO8601PlainFormatter().date(from: string) {
            return date
        }
        return Self.makeISO8601Formatter().date(from: string)
    }

    private func sanitizeHTML(_ string: String) -> String {
        guard string.contains("<"), let data = string.data(using: .utf8) else {
            return string.trimmingCharacters(in: .whitespacesAndNewlines)
        }

        if let attributed = try? NSAttributedString(
            data: data,
            options: [
                .documentType: NSAttributedString.DocumentType.html,
                .characterEncoding: String.Encoding.utf8.rawValue
            ],
            documentAttributes: nil
        ) {
            return attributed.string.trimmingCharacters(in: .whitespacesAndNewlines)
        }

        return string.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func updateCurrentItem(_ mutate: (inout RSSDraftItem) -> Void) {
        guard var item = currentItem else {
            return
        }
        mutate(&item)
        currentItem = item
    }

    private static func makeRFC822Formatter() -> DateFormatter {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "EEE, dd MMM yyyy HH:mm:ss Z"
        return formatter
    }

    private static func makeRFC2822Formatter() -> DateFormatter {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "EEE, dd MMM yyyy HH:mm:ss zzz"
        return formatter
    }

    private static func makeISO8601Formatter() -> ISO8601DateFormatter {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter
    }

    private static func makeISO8601PlainFormatter() -> ISO8601DateFormatter {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime]
        return formatter
    }

    private func normalizedElementName(_ elementName: String) -> String {
        elementName
            .lowercased()
            .split(separator: ":")
            .last
            .map(String.init) ?? elementName.lowercased()
    }
}

private struct RSSDraftItem {
    var title: String?
    var body: String?
    var author: String?
    var identifier: String?
    var link: String?
    var date: Date?

    func makeItem() -> RSSParsedItem? {
        let title = title?.trimmingCharacters(in: .whitespacesAndNewlines)
        let combinedBody = [title, body?.trimmingCharacters(in: .whitespacesAndNewlines)]
            .compactMap { $0 }
            .filter { $0.isEmpty == false }
            .joined(separator: "\n\n")
        let identifier = identifier?.trimmingCharacters(in: .whitespacesAndNewlines)
            ?? link?.trimmingCharacters(in: .whitespacesAndNewlines)
            ?? title
        // If a feed omits or mangles the timestamp, keep the item visible instead of
        // dropping it immediately via retention pruning.
        let date = date ?? Date()
        guard let identifier, identifier.isEmpty == false else {
            return nil
        }

        return RSSParsedItem(
            identifier: identifier,
            title: title?.isEmpty == false ? title! : identifier,
            body: combinedBody.isEmpty ? identifier : combinedBody,
            author: author?.trimmingCharacters(in: .whitespacesAndNewlines) ?? "",
            date: date,
            link: normalizedURL(from: link)
        )
    }
}

private func stableHash64(_ string: String) -> UInt64 {
    let prime: UInt64 = 1099511628211
    var hash: UInt64 = 14695981039346656037
    for byte in string.utf8 {
        hash ^= UInt64(byte)
        hash &*= prime
    }
    return hash
}

private func normalizedURL(from string: String?) -> URL? {
    guard
        let string
    else {
        return nil
    }

    let trimmed = string.trimmingCharacters(in: .whitespacesAndNewlines)
    guard
        trimmed.isEmpty == false,
        let url = URL(string: trimmed),
        let scheme = url.scheme?.lowercased(),
        ["http", "https"].contains(scheme)
    else {
        return nil
    }

    return url
}
