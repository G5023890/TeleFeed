import Foundation
import OSLog

enum ReaderServiceError: LocalizedError, Equatable {
    case invalidURL
    case invalidArticle
    case emptyArticle
    case unsupportedEncoding

    var errorDescription: String? {
        switch self {
        case .invalidURL:
            return L10n.tr("reader.invalidURL")
        case .invalidArticle:
            return L10n.tr("reader.invalidArticle")
        case .emptyArticle:
            return L10n.tr("reader.emptyArticle")
        case .unsupportedEncoding:
            return L10n.tr("reader.unsupportedEncoding")
        }
    }
}

final class ReaderService: ReaderServiceProtocol, @unchecked Sendable {
    private static let logger = Logger(subsystem: "com.codex.Telega", category: "ReaderService")
    private let session: URLSession
    private let userAgent = "Mozilla/5.0 (Macintosh; Intel Mac OS X 15_0) AppleWebKit/605.1.15 (KHTML, like Gecko) TeleFeed/1.0 Safari/605.1.15"
    private let fallbackPolicy = ReaderFallbackPolicy()

    init(session: URLSession = .shared) {
        self.session = session
    }

    func loadArticle(from url: URL, fallbackTitle: String) async throws -> ReaderArticle {
        guard ["http", "https"].contains(url.scheme?.lowercased() ?? "") else {
            throw ReaderServiceError.invalidURL
        }

        do {
            return try await loadArticleViaReadability(from: url, fallbackTitle: fallbackTitle)
        } catch {
            guard fallbackPolicy.action(for: error) == .retryWithLegacyParser else {
                throw error
            }

            Self.logger.debug("Readability extraction failed, falling back to legacy parser for \(url.absoluteString, privacy: .public)")
            return try await loadArticleViaLegacyParser(from: url, fallbackTitle: fallbackTitle)
        }
    }

    private func loadArticleViaReadability(from url: URL, fallbackTitle: String) async throws -> ReaderArticle {
        let extractor = ReadabilityExtractor(userAgent: userAgent)
        let result = try await extractor.extract(from: url)
        let blocks = Self.extractBlocks(from: result.contentHTML)
        let body = blocks.isEmpty ? Self.renderText(from: result.contentHTML) : Self.composePlainText(from: blocks)
        let normalizedBody = body.trimmingCharacters(in: .whitespacesAndNewlines)
        guard normalizedBody.isEmpty == false else {
            throw ReaderServiceError.emptyArticle
        }

        return ReaderArticle(
            sourceURL: url,
            canonicalURL: result.canonicalURL ?? url,
            title: result.title ?? fallbackTitle,
            body: normalizedBody,
            blocks: blocks.isEmpty ? [.paragraph(normalizedBody)] : blocks,
            excerpt: result.excerpt,
            imageURL: result.imageURL
        )
    }

    private func loadArticleViaLegacyParser(from url: URL, fallbackTitle: String) async throws -> ReaderArticle {
        var request = URLRequest(url: url)
        request.setValue(userAgent, forHTTPHeaderField: "User-Agent")
        request.setValue("text/html,application/xhtml+xml,application/xml;q=0.9,*/*;q=0.8", forHTTPHeaderField: "Accept")
        request.setValue("en-US,en;q=0.9", forHTTPHeaderField: "Accept-Language")

        let (data, response) = try await session.data(for: request)
        if let httpResponse = response as? HTTPURLResponse {
            Self.logger.debug("Reader response \(url.absoluteString, privacy: .public) status=\(httpResponse.statusCode, privacy: .public)")
            guard (200..<400).contains(httpResponse.statusCode) else {
                throw ReaderServiceError.invalidArticle
            }
        }

        guard let html = String(data: data, encoding: .utf8) ?? String(data: data, encoding: .isoLatin1) else {
            throw ReaderServiceError.unsupportedEncoding
        }

        let metadata = Self.extractMetadata(from: html)
        let sourceHTML = Self.extractPrimaryHTML(from: html) ?? html
        let blocks = Self.extractBlocks(from: sourceHTML)
        let body = blocks.isEmpty ? Self.renderText(from: sourceHTML) : Self.composePlainText(from: blocks)
        let normalizedBody = body.trimmingCharacters(in: .whitespacesAndNewlines)
        guard normalizedBody.isEmpty == false else {
            throw ReaderServiceError.emptyArticle
        }

        return ReaderArticle(
            sourceURL: url,
            canonicalURL: metadata.canonicalURL ?? url,
            title: metadata.title ?? fallbackTitle,
            body: normalizedBody,
            blocks: blocks.isEmpty ? [.paragraph(normalizedBody)] : blocks,
            excerpt: metadata.description,
            imageURL: metadata.imageURL
        )
    }

    private static func extractMetadata(from html: String) -> ReaderMetadata {
        ReaderMetadata(
            title: firstMatch(in: html, pattern: #"<meta\b[^>]*(?:property|name)=["'](?:og:title|twitter:title)["'][^>]*content=["']([^"']+)["'][^>]*>"#)
                ?? firstMatch(in: html, pattern: #"<title[^>]*>(.*?)</title>"#).map { stripHTML(from: $0) },
            description: firstMatch(in: html, pattern: #"<meta\b[^>]*(?:property|name)=["'](?:og:description|description|twitter:description)["'][^>]*content=["']([^"']+)["'][^>]*>"#),
            imageURL: firstMatch(in: html, pattern: #"<meta\b[^>]*(?:property|name)=["'](?:og:image|twitter:image)["'][^>]*content=["']([^"']+)["'][^>]*>"#)
                .flatMap { normalizedURL(from: $0) },
            canonicalURL: firstMatch(in: html, pattern: #"<link\b[^>]*rel=["']canonical["'][^>]*href=["']([^"']+)["'][^>]*>"#)
                .flatMap { normalizedURL(from: $0) }
        )
    }

    private static func extractPrimaryHTML(from html: String) -> String? {
        let candidates = candidateHTMLFragments(in: html)
        guard candidates.isEmpty == false else {
            return nil
        }

        return candidates.max(by: { articleScore(for: $0) < articleScore(for: $1) })
    }

    private static func renderText(from html: String) -> String {
        let sanitized = sanitizeArticleHTML(html)

        if let data = sanitized.data(using: .utf8),
           let attributed = try? NSAttributedString(
            data: data,
            options: [
                .documentType: NSAttributedString.DocumentType.html,
                .characterEncoding: String.Encoding.utf8.rawValue
            ],
            documentAttributes: nil
           ) {
            return normalizeText(attributed.string)
        }

        return normalizeText(stripHTML(from: sanitized))
    }

    private static func extractBlocks(from html: String) -> [ReaderArticle.Block] {
        let workingHTML = prepareHTMLForExtraction(pruneBoilerplateSections(html))
        let patterns: [(String, ReaderArticle.Block)] = [
            (#"<h1\b[^>]*>(.*?)</h1>"#, .heading("", level: 1)),
            (#"<h2\b[^>]*>(.*?)</h2>"#, .heading("", level: 2)),
            (#"<h3\b[^>]*>(.*?)</h3>"#, .heading("", level: 3)),
            (#"<h4\b[^>]*>(.*?)</h4>"#, .heading("", level: 4)),
            (#"<h5\b[^>]*>(.*?)</h5>"#, .heading("", level: 5)),
            (#"<h6\b[^>]*>(.*?)</h6>"#, .heading("", level: 6)),
            (#"<blockquote\b[^>]*>(.*?)</blockquote>"#, .quote("")),
            (#"<pre\b[^>]*>(.*?)</pre>"#, .code("")),
            (#"<ol\b[^>]*>(.*?)</ol>"#, .list(items: [], ordered: true)),
            (#"<ul\b[^>]*>(.*?)</ul>"#, .list(items: [], ordered: false)),
            (#"<p\b[^>]*>(.*?)</p>"#, .paragraph("")),
            (#"<figure\b[^>]*>(.*?)</figure>"#, .separator)
        ]

        let matches = orderedMatches(in: workingHTML, patterns: patterns)
        let blocks = matches.compactMap { match -> ReaderArticle.Block? in
            switch match.template {
            case .heading(_, let level):
                let text = normalizeText(stripHTML(from: match.content))
                return text.isEmpty ? nil : .heading(text, level: level)
            case .paragraph:
                let text = normalizeParagraphText(from: match.content)
                guard text.isEmpty == false else { return nil }
                return isBoilerplateParagraph(text) ? nil : .paragraph(text)
            case .quote:
                let text = normalizeParagraphText(from: match.content)
                guard text.isEmpty == false else { return nil }
                return isBoilerplateParagraph(text) ? nil : .quote(text)
            case .code:
                let text = normalizeCodeText(from: match.content)
                return text.isEmpty ? nil : .code(text)
            case .list(_, let ordered):
                let items = extractListItems(from: match.content)
                let filteredItems = items.filter { isBoilerplateParagraph($0) == false }
                return filteredItems.isEmpty ? nil : .list(items: filteredItems, ordered: ordered)
            case .separator:
                return .separator
            }
        }

        return trimTrailingBoilerplateBlocks(coalesceBlocks(blocks))
    }

    private static func composePlainText(from blocks: [ReaderArticle.Block]) -> String {
        var lines: [String] = []
        for block in blocks {
            switch block {
            case .heading(let text, _):
                lines.append(text)
                lines.append("")
            case .paragraph(let text):
                lines.append(text)
                lines.append("")
            case .quote(let text):
                lines.append(text)
                lines.append("")
            case .list(let items, let ordered):
                for (index, item) in items.enumerated() {
                    let prefix = ordered ? "\(index + 1)." : "•"
                    lines.append("\(prefix) \(item)")
                }
                lines.append("")
            case .code(let text):
                lines.append(text)
                lines.append("")
            case .separator:
                lines.append("")
            }
        }
        return normalizeText(lines.joined(separator: "\n"))
    }

    private static func sanitizeArticleHTML(_ html: String) -> String {
        html
            .replacingOccurrences(of: #"(?is)<!--.*?-->"#, with: "", options: .regularExpression)
            .replacingOccurrences(of: #"(?is)<script\b[^>]*>.*?</script>"#, with: "", options: .regularExpression)
            .replacingOccurrences(of: #"(?is)<style\b[^>]*>.*?</style>"#, with: "", options: .regularExpression)
            .replacingOccurrences(of: #"(?is)<noscript\b[^>]*>.*?</noscript>"#, with: "", options: .regularExpression)
            .replacingOccurrences(of: #"(?is)<(header|nav|aside|footer|form|svg|template|iframe|canvas|script)\b[^>]*>.*?</\1>"#, with: "", options: .regularExpression)
            .replacingOccurrences(of: #"(?is)<(header|nav|aside|footer|form|svg|template|iframe|canvas|script)\b[^>]*/>"#, with: "", options: .regularExpression)
            .replacingOccurrences(of: #"(?is)<(div|section|article|main|p|li|blockquote|pre|table|tr|td|th|h[1-6])\b[^>]*>"#, with: "\n<$1>", options: .regularExpression)
            .replacingOccurrences(of: #"(?is)</(div|section|article|main|p|li|blockquote|pre|table|tr|td|th|h[1-6])>"#, with: "</$1>\n", options: .regularExpression)
            .replacingOccurrences(of: #"(?is)<br\s*/?>"#, with: "\n", options: .regularExpression)
            .replacingOccurrences(of: #"(?is)</?(span|strong|em|b|i|u|small|sup|sub|mark|code|kbd|s|a|img|figure|figcaption)\b[^>]*>"#, with: "", options: .regularExpression)
            .replacingOccurrences(of: #"(?is)<[^>]+>"#, with: " ", options: .regularExpression)
            .replacingOccurrences(of: #"(?m)^[ \t]+|[ \t]+$"#, with: "", options: .regularExpression)
            .replacingOccurrences(of: #"\n{3,}"#, with: "\n\n", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private static func pruneBoilerplateSections(_ html: String) -> String {
        let patterns = [
            #"<(aside|div|section|nav)\b[^>]*(?:class|id|data-testid)=["'][^"']*(?:subscribe|subscription|newsletter|related|recommended|share|social|comments?|promo|advert|ad[-_]|cookie|follow|breadcrumb|sidebar|post[-_ ]?nav|more[-_ ]from|you[-_ ]may[-_ ]also[-_ ]like|read[-_ ]more)[^"']*["'][^>]*>.*?</\1>"#,
            #"<(div|section)\b[^>]*(?:class|id|data-testid)=["'][^"']*(?:subscribe|subscription|newsletter|related|recommended|share|social|comments?|promo|advert|ad[-_]|cookie|follow|breadcrumb|sidebar|post[-_ ]?nav|more[-_ ]from|you[-_ ]may[-_ ]also[-_ ]like|read[-_ ]more)[^"']*["'][^>]*>.*?</\1>"#,
            #"<div\b[^>]*role=["'](?:navigation|complementary|contentinfo)["'][^>]*>.*?</div>"#,
            #"<section\b[^>]*role=["'](?:navigation|complementary|contentinfo)["'][^>]*>.*?</section>"#,
            #"<footer\b[^>]*>.*?</footer>"#,
            #"<header\b[^>]*>.*?</header>"#
        ]

        var result = html
        for pattern in patterns {
            result = result.replacingOccurrences(of: pattern, with: "", options: .regularExpression)
        }
        return result
    }

    private static func prepareHTMLForExtraction(_ html: String) -> String {
        html
            .replacingOccurrences(of: #"(?is)<!--.*?-->"#, with: "", options: .regularExpression)
            .replacingOccurrences(of: #"(?is)<script\b[^>]*>.*?</script>"#, with: "", options: .regularExpression)
            .replacingOccurrences(of: #"(?is)<style\b[^>]*>.*?</style>"#, with: "", options: .regularExpression)
            .replacingOccurrences(of: #"(?is)<noscript\b[^>]*>.*?</noscript>"#, with: "", options: .regularExpression)
            .replacingOccurrences(of: #"(?is)<(header|nav|aside|footer|form|svg|template|iframe|canvas)\b[^>]*>.*?</\1>"#, with: "", options: .regularExpression)
            .replacingOccurrences(of: #"(?is)<(header|nav|aside|footer|form|svg|template|iframe|canvas)\b[^>]*/>"#, with: "", options: .regularExpression)
            .replacingOccurrences(of: #"(?is)<(br)\b[^>]*>"#, with: "<br>", options: .regularExpression)
    }

    private static func normalizeParagraphText(from htmlFragment: String) -> String {
        let text = stripHTML(from: htmlFragment)
        return normalizeText(text)
    }

    private static func normalizeCodeText(from htmlFragment: String) -> String {
        let text = htmlFragment
            .replacingOccurrences(of: #"(?is)<br\s*/?>"#, with: "\n", options: .regularExpression)
            .replacingOccurrences(of: #"(?is)<[^>]+>"#, with: "", options: .regularExpression)
        return text
            .replacingOccurrences(of: "\u{00a0}", with: " ")
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private static func extractListItems(from htmlFragment: String) -> [String] {
        let patterns = [#"<li\b[^>]*>(.*?)</li>"#]
        var items: [String] = []
        for pattern in patterns {
            items.append(contentsOf: allMatches(in: htmlFragment, pattern: pattern).map { normalizeParagraphText(from: $0) })
        }
        return items.filter { $0.isEmpty == false }
    }

    private struct BlockMatch {
        let range: Range<String.Index>
        let content: String
        let template: ReaderArticle.Block
    }

    private static func orderedMatches(
        in html: String,
        patterns: [(String, ReaderArticle.Block)]
    ) -> [BlockMatch] {
        var matches: [BlockMatch] = []
        for (pattern, template) in patterns {
            guard let regex = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive, .dotMatchesLineSeparators]) else {
                continue
            }
            let range = NSRange(html.startIndex..<html.endIndex, in: html)
            for match in regex.matches(in: html, options: [], range: range) {
                guard match.numberOfRanges > 1 else { continue }
                let captureRange = match.range(at: 1)
                guard captureRange.location != NSNotFound, let swiftRange = Range(captureRange, in: html) else {
                    continue
                }
                matches.append(
                    BlockMatch(
                        range: swiftRange,
                        content: String(html[swiftRange]),
                        template: template
                    )
                )
            }
        }

        return matches.sorted { lhs, rhs in lhs.range.lowerBound < rhs.range.lowerBound }
    }

    private static func coalesceBlocks(_ blocks: [ReaderArticle.Block]) -> [ReaderArticle.Block] {
        var result: [ReaderArticle.Block] = []
        for block in blocks {
            if case .separator = block {
                if result.last != Optional(ReaderArticle.Block.separator) {
                    result.append(.separator)
                }
            } else {
                result.append(block)
            }
        }
        while result.first == Optional(ReaderArticle.Block.separator) {
            result.removeFirst()
        }
        while result.last == Optional(ReaderArticle.Block.separator) {
            result.removeLast()
        }
        return result
    }

    private static func trimTrailingBoilerplateBlocks(_ blocks: [ReaderArticle.Block]) -> [ReaderArticle.Block] {
        var trimmed: [ReaderArticle.Block] = []
        for block in blocks {
            if shouldStopAtBoilerplate(block) {
                break
            }
            trimmed.append(block)
        }
        return trimmed
    }

    private static func shouldStopAtBoilerplate(_ block: ReaderArticle.Block) -> Bool {
        switch block {
        case .heading(let text, _):
            return isBoilerplateHeading(text)
        case .paragraph(let text), .quote(let text), .code(let text):
            return isBoilerplateParagraph(text) && text.split { $0.isWhitespace }.count <= 30
        case .list(let items, _):
            let joined = items.joined(separator: " ")
            return isBoilerplateParagraph(joined)
        case .separator:
            return false
        }
    }

    private static func isBoilerplateHeading(_ text: String) -> Bool {
        let lowercased = text.lowercased()
        let signals = [
            "related", "recommended", "more from", "you may also like",
            "subscribe", "sign up", "newsletter", "share", "sharing",
            "comments", "continue reading", "read more", "follow us",
            "подпис", "поделиться", "похожие", "рекомендуем", "читайте также",
            "комментар", "подпиш"
        ]
        return signals.contains { lowercased.contains($0) }
    }

    private static func isBoilerplateParagraph(_ text: String) -> Bool {
        let lowercased = text.lowercased()
        let wordCount = text.split { $0.isWhitespace }.count
        let signals = [
            "subscribe", "subscription", "newsletter", "sign up", "share", "sharing",
            "related", "recommended", "comments", "cookie", "privacy policy",
            "more from", "you may also like", "follow us", "read more",
            "подпис", "поделиться", "рекоменд", "похожие", "комментар",
            "читайте также", "смотреть также", "реклама", "спонсор", "подпиш"
        ]

        if signals.contains(where: { lowercased.contains($0) }) {
            return true
        }

        if wordCount <= 4 {
            let shortPrompts = [
                "share", "subscribe", "related", "recommended", "more", "follow",
                "подпис", "поделиться", "похожие", "рекоменд", "читайте"
            ]
            return shortPrompts.contains { lowercased.contains($0) }
        }

        return false
    }

    private static func stripHTML(from htmlFragment: String) -> String {
        let stripped = htmlFragment.replacingOccurrences(of: #"(?is)<[^>]+>"#, with: " ", options: .regularExpression)
        return normalizeText(stripped)
    }

    private static func normalizeText(_ string: String) -> String {
        string
            .replacingOccurrences(of: "\u{00a0}", with: " ")
            .replacingOccurrences(of: #"(?m)[ \t]+"#, with: " ", options: .regularExpression)
            .replacingOccurrences(of: #"(?m)\n[ \t]+"#, with: "\n", options: .regularExpression)
            .replacingOccurrences(of: #"\n{3,}"#, with: "\n\n", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private static func firstMatch(in html: String, pattern: String, captureGroup: Int = 1) -> String? {
        guard let regex = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive, .dotMatchesLineSeparators]) else {
            return nil
        }
        let range = NSRange(html.startIndex..<html.endIndex, in: html)
        guard
            let match = regex.firstMatch(in: html, options: [], range: range),
            match.numberOfRanges > captureGroup
        else {
            return nil
        }
        let captureRange = match.range(at: captureGroup)
        guard captureRange.location != NSNotFound, let swiftRange = Range(captureRange, in: html) else {
            return nil
        }
        return String(html[swiftRange]).trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private static func candidateHTMLFragments(in html: String) -> [String] {
        let patterns = [
            #"<article\b[^>]*>(.*?)</article>"#,
            #"<main\b[^>]*>(.*?)</main>"#,
            #"<div\b(?=[^>]*(?:class|id|role|itemprop)=["'][^"']*(?:article|article-body|articlebody|article-content|entry-content|post-content|content-body|content|post|story|entry|reader|body|main|markdown-body|text-body|rich-text)[^"']*["'])[^>]*>(.*?)</div>"#,
            #"<section\b(?=[^>]*(?:class|id|role|itemprop)=["'][^"']*(?:article|article-body|articlebody|article-content|entry-content|post-content|content-body|content|post|story|entry|reader|body|main|markdown-body|text-body|rich-text)[^"']*["'])[^>]*>(.*?)</section>"#,
            #"<body\b[^>]*>(.*?)</body>"#
        ]

        var fragments: [String] = []
        for pattern in patterns {
            fragments.append(contentsOf: allMatches(in: html, pattern: pattern))
        }

        if fragments.isEmpty == false {
            return fragments
        }

        return [html]
    }

    private static func allMatches(in html: String, pattern: String, captureGroup: Int = 1) -> [String] {
        guard let regex = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive, .dotMatchesLineSeparators]) else {
            return []
        }

        let range = NSRange(html.startIndex..<html.endIndex, in: html)
        return regex.matches(in: html, options: [], range: range).compactMap { match in
            guard match.numberOfRanges > captureGroup else {
                return nil
            }
            let captureRange = match.range(at: captureGroup)
            guard captureRange.location != NSNotFound, let swiftRange = Range(captureRange, in: html) else {
                return nil
            }
            return String(html[swiftRange]).trimmingCharacters(in: .whitespacesAndNewlines)
        }
    }

    private static func articleScore(for html: String) -> Int {
        let cleanedHTML = pruneBoilerplateSections(sanitizeForScoring(html))
        let text = normalizeText(stripHTML(from: cleanedHTML))
        guard text.isEmpty == false else {
            return 0
        }

        let wordCount = text.split { $0.isWhitespace }.count
        let paragraphCount = cleanedHTML.components(separatedBy: #"<p\b"#).count - 1
        let headingCount = cleanedHTML.components(separatedBy: #"<h[1-6]\b"#).count - 1
        let listCount = cleanedHTML.components(separatedBy: #"<li\b"#).count - 1
        let imageCount = cleanedHTML.components(separatedBy: #"<img\b"#).count - 1
        let linkCount = cleanedHTML.components(separatedBy: #"<a\b"#).count - 1
        let lineBreakCount = text.components(separatedBy: .newlines).count - 1
        let blockBonus = paragraphCount * 35 + headingCount * 18 + listCount * 10 + imageCount * 8 + max(lineBreakCount, 0) * 8
        let punctuationBonus = text.filter { ".!?".contains($0) }.count * 2
        let boilerplatePenalty = boilerplatePenalty(for: text) + linkCount * 8
        let shortArticlePenalty = wordCount < 80 ? (80 - wordCount) * 6 : 0
        return wordCount * 10 + blockBonus + punctuationBonus - boilerplatePenalty - shortArticlePenalty
    }

    private static func sanitizeForScoring(_ html: String) -> String {
        html
            .replacingOccurrences(of: #"(?is)<!--.*?-->"#, with: "", options: .regularExpression)
            .replacingOccurrences(of: #"(?is)<(script|style|noscript|nav|aside|footer|form|svg|template|iframe|canvas)\b[^>]*>.*?</\1>"#, with: "", options: .regularExpression)
            .replacingOccurrences(of: #"(?is)<(header|footer|nav|aside)\b[^>]*/>"#, with: "", options: .regularExpression)
    }

    private static func boilerplatePenalty(for text: String) -> Int {
        let lowercased = text.lowercased()
        let signals: [(String, Int)] = [
            ("cookie", 150),
            ("subscribe", 100),
            ("sign up", 80),
            ("newsletter", 80),
            ("advertis", 120),
            ("sponsor", 90),
            ("related", 70),
            ("recommended", 70),
            ("comments", 80),
            ("share", 40),
            ("privacy policy", 120),
            ("terms of service", 120),
            ("all rights reserved", 120),
            ("follow us", 90),
            ("подпис", 100),
            ("поделиться", 80),
            ("рекоменд", 70),
            ("похожие", 70),
            ("читайте также", 90),
            ("смотрите также", 90),
            ("комментар", 80),
            ("реклама", 120),
            ("спонсор", 90),
            ("подпиш", 100),
            ("share this", 80),
            ("related articles", 90),
            ("more stories", 90),
            ("recommended reading", 90)
        ]

        return signals.reduce(0) { partial, signal in
            lowercased.contains(signal.0) ? partial + signal.1 : partial
        }
    }

    private static func normalizedURL(from string: String) -> URL? {
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
}

private struct ReaderMetadata {
    let title: String?
    let description: String?
    let imageURL: URL?
    let canonicalURL: URL?
}
