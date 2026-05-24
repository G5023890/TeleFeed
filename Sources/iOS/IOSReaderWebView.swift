import SwiftUI
import WebKit

struct IOSReaderWebView: UIViewRepresentable {
    let html: String
    let baseURL: URL?

    func makeUIView(context: Context) -> WKWebView {
        let configuration = WKWebViewConfiguration()
        let webView = WKWebView(frame: .zero, configuration: configuration)
        webView.navigationDelegate = context.coordinator
        webView.allowsBackForwardNavigationGestures = false
        webView.isOpaque = false
        webView.backgroundColor = .clear
        webView.scrollView.backgroundColor = .clear
        webView.customUserAgent = Self.userAgent
        return webView
    }

    func updateUIView(_ webView: WKWebView, context: Context) {
        context.coordinator.loadIfNeeded(html: html, baseURL: baseURL, into: webView)
    }

    func makeCoordinator() -> Coordinator {
        Coordinator()
    }

    private static let userAgent = "Mozilla/5.0 (iPhone; CPU iPhone OS 26_0 like Mac OS X) AppleWebKit/605.1.15 (KHTML, like Gecko) TeleFeed/1.0 Mobile/15E148 Safari/604.1"

    @MainActor
    final class Coordinator: NSObject, WKNavigationDelegate {
        private var lastLoadedHTML = ""
        private var lastBaseURL: URL?

        func loadIfNeeded(html: String, baseURL: URL?, into webView: WKWebView) {
            guard html != lastLoadedHTML || baseURL != lastBaseURL else {
                return
            }

            lastLoadedHTML = html
            lastBaseURL = baseURL
            webView.loadHTMLString(html, baseURL: baseURL)
        }

        func webView(
            _ webView: WKWebView,
            decidePolicyFor navigationAction: WKNavigationAction,
            decisionHandler: @escaping @MainActor @Sendable (WKNavigationActionPolicy) -> Void
        ) {
            decisionHandler(.allow)
        }
    }
}
