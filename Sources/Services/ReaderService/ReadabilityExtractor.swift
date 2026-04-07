import Foundation
import OSLog
import WebKit

struct ReadabilityExtractionResult {
    let title: String?
    let excerpt: String?
    let canonicalURL: URL?
    let imageURL: URL?
    let contentHTML: String
}

private struct ReadabilityPayload: Decodable {
    struct Article: Decodable {
        let title: String?
        let excerpt: String?
        let contentHTML: String?

        private enum CodingKeys: String, CodingKey {
            case title
            case excerpt
            case contentHTML = "contentHTML"
        }
    }

    let article: Article?
    let title: String?
    let excerpt: String?
    let canonicalURL: String?
    let imageURL: String?
    let error: String?
}

enum ReadabilityExtractorError: LocalizedError {
    case invalidPayload
    case emptyArticle
    case extractionFailed(String)

    var errorDescription: String? {
        switch self {
        case .invalidPayload:
            return "Invalid article payload."
        case .emptyArticle:
            return "The article does not contain readable content."
        case .extractionFailed(let message):
            return message
        }
    }
}

final class ReadabilityExtractor: NSObject {
    private static let logger = Logger(subsystem: "com.codex.TeleFeed", category: "ReadabilityExtractor")

    private let userAgent: String
    private var continuation: CheckedContinuation<ReadabilityExtractionResult, Error>?
    private var webView: WKWebView?
    private var didInjectReadability = false

    init(userAgent: String) {
        self.userAgent = userAgent
    }

    @MainActor
    func extract(from url: URL) async throws -> ReadabilityExtractionResult {
        try await withCheckedThrowingContinuation { continuation in
            self.continuation = continuation
            self.didInjectReadability = false

            let configuration = WKWebViewConfiguration()
            let webView = WKWebView(frame: .zero, configuration: configuration)
            webView.navigationDelegate = self
            webView.uiDelegate = self
            webView.customUserAgent = userAgent
            webView.alphaValue = 0.01
            webView.setValue(false, forKey: "drawsBackground")
            webView.enclosingScrollView?.drawsBackground = false
            webView.enclosingScrollView?.backgroundColor = .clear
            self.webView = webView

            webView.load(URLRequest(url: url))
        }
    }

    @MainActor
    private func finish(with result: Result<ReadabilityExtractionResult, Error>) {
        guard let continuation else {
            cleanup()
            return
        }

        self.continuation = nil
        cleanup()
        switch result {
        case .success(let payload):
            continuation.resume(returning: payload)
        case .failure(let error):
            continuation.resume(throwing: error)
        }
    }

    @MainActor
    private func cleanup() {
        webView?.navigationDelegate = nil
        webView?.uiDelegate = nil
        webView?.stopLoading()
        webView = nil
    }

    @MainActor
    private func injectReadabilityIfNeeded(in webView: WKWebView) async throws {
        guard didInjectReadability == false else {
            return
        }

        try await webView.evaluateJavaScript(ReadabilitySource.script)
        didInjectReadability = true
    }

    @MainActor
    private func extractPayload(from webView: WKWebView) async throws -> ReadabilityExtractionResult {
        try await injectReadabilityIfNeeded(in: webView)

        let script = """
        (() => {
            try {
                const canonical = document.querySelector('link[rel="canonical"]')?.href || location.href;
                const image = document.querySelector('meta[property="og:image"], meta[name="og:image"], meta[property="twitter:image"], meta[name="twitter:image"]')?.content || null;
                const title = document.querySelector('meta[property="og:title"], meta[name="og:title"], meta[property="twitter:title"], meta[name="twitter:title"]')?.content || document.title || '';
                const excerpt = document.querySelector('meta[property="og:description"], meta[name="og:description"], meta[name="description"], meta[property="twitter:description"], meta[name="twitter:description"]')?.content || null;
                const reader = new Readability(document.cloneNode(true), { keepClasses: true });
                const article = reader.parse();

                if (!article || !article.content) {
                    return JSON.stringify({ error: 'emptyArticle' });
                }

                const normalizeLazyMedia = (root) => {
                    const fallbackAttributes = ['data-src', 'data-original', 'data-lazy-src', 'data-url', 'data-actualsrc', 'data-cfsrc'];
                    const fallbackSrcsetAttributes = ['data-srcset', 'data-lazy-srcset'];
                    const fallbackPosterAttributes = ['data-poster', 'data-lazy-poster'];

                    const applyFallbackAttribute = (element, target, attributes) => {
                        if (element.getAttribute(target)) {
                            return;
                        }

                        for (const attribute of attributes) {
                            const value = element.getAttribute(attribute);
                            if (value) {
                                element.setAttribute(target, value);
                                return;
                            }
                        }
                    };

                    root.querySelectorAll('img').forEach((element) => {
                        applyFallbackAttribute(element, 'src', fallbackAttributes);
                        applyFallbackAttribute(element, 'srcset', fallbackSrcsetAttributes);
                        element.removeAttribute('loading');
                    });

                    root.querySelectorAll('source').forEach((element) => {
                        applyFallbackAttribute(element, 'src', fallbackAttributes);
                        applyFallbackAttribute(element, 'srcset', fallbackSrcsetAttributes);
                    });

                    root.querySelectorAll('video, audio, iframe').forEach((element) => {
                        applyFallbackAttribute(element, 'src', fallbackAttributes);
                    });

                    root.querySelectorAll('video').forEach((element) => {
                        applyFallbackAttribute(element, 'poster', fallbackPosterAttributes);
                    });
                };

                const fragment = document.createElement('div');
                fragment.innerHTML = article.content;
                normalizeLazyMedia(fragment);

                return JSON.stringify({
                    article: {
                        title: article.title || title,
                        excerpt: article.excerpt || excerpt,
                        contentHTML: fragment.innerHTML
                    },
                    title: article.title || title,
                    excerpt: article.excerpt || excerpt,
                    canonicalURL: canonical,
                    imageURL: image,
                    error: null
                });
            } catch (error) {
                return JSON.stringify({ error: String(error) });
            }
        })()
        """

        let result = try await webView.evaluateJavaScript(script)
        let jsonString: String
        if let string = result as? String {
            jsonString = string
        } else if let string = result as? NSString {
            jsonString = string as String
        } else {
            throw ReadabilityExtractorError.invalidPayload
        }

        guard let data = jsonString.data(using: .utf8) else {
            throw ReadabilityExtractorError.invalidPayload
        }

        let payload = try JSONDecoder().decode(ReadabilityPayload.self, from: data)

        if let error = payload.error {
            if error == "emptyArticle" {
                throw ReadabilityExtractorError.emptyArticle
            }
            throw ReadabilityExtractorError.extractionFailed(error)
        }

        guard let article = payload.article, let contentHTML = article.contentHTML?.trimmingCharacters(in: .whitespacesAndNewlines), contentHTML.isEmpty == false else {
            throw ReadabilityExtractorError.emptyArticle
        }

        let canonicalURL = payload.canonicalURL.flatMap(URL.init(string:))
        let imageURL = payload.imageURL.flatMap(URL.init(string:))

        return ReadabilityExtractionResult(
            title: article.title ?? payload.title,
            excerpt: article.excerpt ?? payload.excerpt,
            canonicalURL: canonicalURL,
            imageURL: imageURL,
            contentHTML: contentHTML
        )
    }
}

extension ReadabilityExtractor: WKNavigationDelegate {
    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        Task { @MainActor in
            var lastError: Error?
            for attempt in 0..<2 {
                do {
                    let result = try await extractPayload(from: webView)
                    finish(with: .success(result))
                    return
                } catch {
                    lastError = error
                    if attempt == 0 {
                        try? await Task.sleep(nanoseconds: 250_000_000)
                    }
                }
            }

            finish(with: .failure(lastError ?? ReadabilityExtractorError.emptyArticle))
        }
    }

    func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) {
        finish(with: .failure(error))
    }

    func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: Error) {
        finish(with: .failure(error))
    }
}

extension ReadabilityExtractor: WKUIDelegate {}
