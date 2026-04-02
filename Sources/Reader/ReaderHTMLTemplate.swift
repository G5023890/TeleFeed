import Foundation

enum ReaderAppearance {
    case light
    case dark
}

enum ReaderHTMLTemplate {
    static func makeHTML(
        for article: ReaderArticle,
        settings: AppSettings,
        appearance: ReaderAppearance
    ) -> String {
        let colors = ReaderColors(appearance: appearance)
        let bodyHTML = bodyHTML(for: article, settings: settings)
        let imageHTML = article.imageURL.map { renderImageHTML(for: $0) } ?? ""
        let excerptHTML = article.excerpt.flatMap { excerpt in
            let trimmed = excerpt.trimmingCharacters(in: .whitespacesAndNewlines)
            return trimmed.isEmpty ? nil : "<p class=\"lede\">" + escapeHTML(trimmed).replacingOccurrences(of: "\n", with: "<br>") + "</p>"
        } ?? ""

        return """
        <!doctype html>
        <html lang="en">
        <head>
            <meta charset="utf-8">
            <meta name="viewport" content="width=device-width, initial-scale=1, viewport-fit=cover">
            <meta name="color-scheme" content="\((appearance == .dark) ? "dark" : "light")">
            <style>
                :root {
                    color-scheme: \((appearance == .dark) ? "dark" : "light");
                    --bg-top: \(colors.backgroundTop);
                    --bg-bottom: \(colors.backgroundBottom);
                    --surface: \(colors.surface);
                    --surface-strong: \(colors.surfaceStrong);
                    --surface-soft: \(colors.surfaceSoft);
                    --border: \(colors.border);
                    --shadow: \(colors.shadow);
                    --text: \(colors.text);
                    --muted: \(colors.muted);
                    --accent: \(colors.accent);
                    --code-bg: \(colors.codeBackground);
                    --code-border: \(colors.codeBorder);
                    --blockquote-border: \(colors.blockquoteBorder);
                    --selection: \(colors.selection);
                    --body-size: \(settings.typography.readerBody)px;
                    --quote-size: \(settings.typography.readerQuote)px;
                    --meta-size: \(settings.typography.readerMeta)px;
                    --code-size: \(settings.typography.readerCode)px;
                    --bullet-size: \(settings.typography.readerListBullet)px;
                    --h1-size: \(settings.typography.readerHeading1)px;
                    --h2-size: \(settings.typography.readerHeading2)px;
                    --h3-size: \(settings.typography.readerHeading3)px;
                    --h4-size: \(settings.typography.readerHeading4)px;
                    --h5-size: \(settings.typography.readerHeading5)px;
                    --h6-size: \(settings.typography.readerHeading6)px;
                }

                html {
                    background:
                        radial-gradient(circle at top left, rgba(255, 255, 255, 0.20), transparent 36%),
                        radial-gradient(circle at top right, rgba(120, 120, 255, 0.12), transparent 28%),
                        linear-gradient(180deg, var(--bg-top), var(--bg-bottom));
                }

                body {
                    margin: 0;
                    min-height: 100vh;
                    color: var(--text);
                    font-family: -apple-system, BlinkMacSystemFont, "SF Pro Display", "SF Pro Text", system-ui, sans-serif;
                    -webkit-font-smoothing: antialiased;
                    text-rendering: optimizeLegibility;
                    background:
                        radial-gradient(circle at top left, rgba(255, 255, 255, 0.16), transparent 38%),
                        linear-gradient(180deg, var(--bg-top), var(--bg-bottom));
                }

                .page {
                    max-width: 920px;
                    margin: 0 auto;
                    padding: 24px 20px 40px;
                }

                .card {
                    position: relative;
                    overflow: hidden;
                    padding: 28px 28px 36px;
                    border-radius: 30px;
                    border: 1px solid var(--border);
                    background:
                        linear-gradient(180deg, var(--surface), var(--surface-soft));
                    box-shadow: 0 18px 60px var(--shadow);
                    backdrop-filter: blur(24px) saturate(180%);
                    -webkit-backdrop-filter: blur(24px) saturate(180%);
                }

                .card::before {
                    content: "";
                    position: absolute;
                    inset: 0;
                    border-radius: 30px;
                    padding: 1px;
                    background: linear-gradient(135deg, rgba(255, 255, 255, 0.22), transparent 40%, rgba(255, 255, 255, 0.08));
                    -webkit-mask:
                        linear-gradient(#fff 0 0) content-box,
                        linear-gradient(#fff 0 0);
                    -webkit-mask-composite: xor;
                            mask-composite: exclude;
                    pointer-events: none;
                }

                .hero {
                    margin-bottom: 22px;
                }

                .hero img {
                    display: block;
                    width: 100%;
                    max-height: 420px;
                    object-fit: cover;
                    border-radius: 24px;
                    border: 1px solid var(--border);
                    box-shadow: 0 12px 32px rgba(0, 0, 0, 0.12);
                }

                .lede {
                    margin: 0 0 22px;
                    font-size: calc(var(--body-size) + 1px);
                    line-height: 1.65;
                    color: var(--muted);
                }

                .content {
                    font-size: var(--body-size);
                    line-height: 1.72;
                    letter-spacing: 0.01em;
                }

                .content > :first-child {
                    margin-top: 0;
                }

                .content > :last-child {
                    margin-bottom: 0;
                }

                p, ul, ol, blockquote, pre, table, figure {
                    margin: 0 0 1.08em;
                }

                h1, h2, h3, h4, h5, h6 {
                    margin: 1.45em 0 0.55em;
                    color: var(--text);
                    line-height: 1.16;
                    letter-spacing: -0.02em;
                }

                h1 { font-size: var(--h1-size); }
                h2 { font-size: var(--h2-size); }
                h3 { font-size: var(--h3-size); }
                h4 { font-size: var(--h4-size); }
                h5 { font-size: var(--h5-size); }
                h6 { font-size: var(--h6-size); }

                p {
                    overflow-wrap: anywhere;
                }

                blockquote {
                    padding: 14px 18px;
                    border-left: 4px solid var(--blockquote-border);
                    border-radius: 16px;
                    background: rgba(255, 255, 255, 0.02);
                    color: var(--muted);
                }

                blockquote p:last-child {
                    margin-bottom: 0;
                }

                pre {
                    overflow-x: auto;
                    padding: 16px 18px;
                    border: 1px solid var(--code-border);
                    border-radius: 18px;
                    background: var(--code-bg);
                    font-size: var(--code-size);
                    line-height: 1.55;
                }

                code {
                    font-family: "SFMono-Regular", "SF Mono", ui-monospace, Menlo, monospace;
                }

                pre code {
                    white-space: pre-wrap;
                }

                ul, ol {
                    padding-left: 1.35em;
                }

                li + li {
                    margin-top: 0.4em;
                }

                hr {
                    border: 0;
                    height: 1px;
                    margin: 1.4em 0;
                    background: linear-gradient(90deg, transparent, var(--border), transparent);
                }

                a {
                    color: var(--accent);
                    text-decoration-thickness: 1.2px;
                    text-underline-offset: 0.16em;
                }

                ::selection {
                    background: var(--selection);
                }

                @media (max-width: 700px) {
                    .page {
                        padding: 16px 14px 28px;
                    }

                    .card {
                        padding: 22px 18px 28px;
                        border-radius: 24px;
                    }
                }
            </style>
        </head>
        <body>
            <main class="page">
                <article class="card">
                    \(imageHTML.isEmpty ? "" : "<div class=\"hero\">" + imageHTML + "</div>")
                    \(excerptHTML)
                    <div class="content">
                        \(bodyHTML)
                    </div>
                </article>
            </main>
        </body>
        </html>
        """
    }

    private static func bodyHTML(for article: ReaderArticle, settings: AppSettings) -> String {
        let blocks = article.blocks.isEmpty ? [.paragraph(article.body)] : article.blocks
        return blocks.map { blockHTML(for: $0, settings: settings) }.joined(separator: "\n")
    }

    private static func blockHTML(for block: ReaderArticle.Block, settings: AppSettings) -> String {
        switch block {
        case .heading(let text, let level):
            let tag = "h\(min(max(level, 1), 6))"
            return "<\(tag)>\(escapedParagraph(text))</\(tag)>"
        case .paragraph(let text):
            return "<p>\(escapedParagraph(text))</p>"
        case .quote(let text):
            return "<blockquote><p>\(escapedParagraph(text))</p></blockquote>"
        case .list(let items, let ordered):
            let tag = ordered ? "ol" : "ul"
            let rendered = items.map { "<li>\(escapedParagraph($0))</li>" }.joined()
            return "<\(tag)>\(rendered)</\(tag)>"
        case .code(let text):
            return "<pre><code>\(escapeHTML(text))</code></pre>"
        case .separator:
            return "<hr>"
        }
    }

    private static func renderImageHTML(for url: URL) -> String {
        let escapedURL = escapeAttribute(url.absoluteString)
        return "<img src=\"\(escapedURL)\" alt=\"\" loading=\"eager\" decoding=\"async\">"
    }

    private static func escapedParagraph(_ text: String) -> String {
        escapeHTML(text).replacingOccurrences(of: "\n", with: "<br>")
    }

    private static func escapeHTML(_ string: String) -> String {
        string
            .replacingOccurrences(of: "&", with: "&amp;")
            .replacingOccurrences(of: "<", with: "&lt;")
            .replacingOccurrences(of: ">", with: "&gt;")
            .replacingOccurrences(of: "\"", with: "&quot;")
            .replacingOccurrences(of: "'", with: "&#39;")
    }

    private static func escapeAttribute(_ string: String) -> String {
        escapeHTML(string)
    }
}

private struct ReaderColors {
    let backgroundTop: String
    let backgroundBottom: String
    let surface: String
    let surfaceStrong: String
    let surfaceSoft: String
    let border: String
    let shadow: String
    let text: String
    let muted: String
    let accent: String
    let codeBackground: String
    let codeBorder: String
    let blockquoteBorder: String
    let selection: String

    init(appearance: ReaderAppearance) {
        switch appearance {
        case .light:
            backgroundTop = "#f8f6f2"
            backgroundBottom = "#efede8"
            surface = "rgba(255, 255, 255, 0.72)"
            surfaceStrong = "rgba(255, 255, 255, 0.88)"
            surfaceSoft = "rgba(255, 255, 255, 0.62)"
            border = "rgba(31, 31, 31, 0.08)"
            shadow = "rgba(19, 19, 19, 0.12)"
            text = "#171717"
            muted = "#4d4d4d"
            accent = "#0066cc"
            codeBackground = "rgba(20, 20, 20, 0.04)"
            codeBorder = "rgba(20, 20, 20, 0.08)"
            blockquoteBorder = "rgba(0, 102, 204, 0.38)"
            selection = "rgba(0, 102, 204, 0.18)"
        case .dark:
            backgroundTop = "#101114"
            backgroundBottom = "#08090b"
            surface = "rgba(26, 26, 28, 0.78)"
            surfaceStrong = "rgba(36, 36, 40, 0.90)"
            surfaceSoft = "rgba(18, 18, 21, 0.68)"
            border = "rgba(255, 255, 255, 0.10)"
            shadow = "rgba(0, 0, 0, 0.42)"
            text = "#f4f4f5"
            muted = "#b5b5bb"
            accent = "#6cb6ff"
            codeBackground = "rgba(255, 255, 255, 0.04)"
            codeBorder = "rgba(255, 255, 255, 0.08)"
            blockquoteBorder = "rgba(108, 182, 255, 0.42)"
            selection = "rgba(108, 182, 255, 0.22)"
        }
    }
}
