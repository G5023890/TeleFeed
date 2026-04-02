import AppKit
import SwiftUI
import WebKit

struct ReaderWebView: NSViewRepresentable {
    let html: String
    let baseURL: URL?
    var onOpenURL: ((URL) -> Void)?

    func makeNSView(context: Context) -> WKWebView {
        let configuration = WKWebViewConfiguration()
        let webView = WKWebView(frame: .zero, configuration: configuration)
        webView.navigationDelegate = context.coordinator
        webView.uiDelegate = context.coordinator
        webView.alphaValue = 1
        webView.allowsBackForwardNavigationGestures = false
        webView.setValue(false, forKey: "drawsBackground")
        webView.enclosingScrollView?.drawsBackground = false
        webView.enclosingScrollView?.backgroundColor = .clear
        webView.customUserAgent = Self.userAgent
        context.coordinator.attach(webView)
        return webView
    }

    func updateNSView(_ webView: WKWebView, context: Context) {
        context.coordinator.onOpenURL = onOpenURL
        context.coordinator.loadIfNeeded(html: html, baseURL: baseURL, into: webView)
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(onOpenURL: onOpenURL)
    }

    private static let userAgent = "Mozilla/5.0 (Macintosh; Intel Mac OS X 15_0) AppleWebKit/605.1.15 (KHTML, like Gecko) TeleFeed/1.0 Safari/605.1.15"

    @MainActor
    final class Coordinator: NSObject, WKNavigationDelegate, WKUIDelegate {
        var onOpenURL: ((URL) -> Void)?

        private weak var webView: WKWebView?
        private var lastLoadedHTML = ""
        private var lastBaseURL: URL?

        init(onOpenURL: ((URL) -> Void)?) {
            self.onOpenURL = onOpenURL
        }

        func attach(_ webView: WKWebView) {
            self.webView = webView
        }

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
            guard navigationAction.navigationType == .linkActivated,
                  let url = navigationAction.request.url
            else {
                decisionHandler(.allow)
                return
            }

            if let onOpenURL {
                onOpenURL(url)
            } else {
                NSWorkspace.shared.open(url)
            }
            decisionHandler(.cancel)
        }
    }
}
