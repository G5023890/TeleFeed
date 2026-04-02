import AppKit
import SwiftUI
import OSLog

@MainActor
final class MainWindowController: NSWindowController {
    fileprivate static let logger = Logger(subsystem: "com.codex.TeleFeed", category: "MainWindowController")

    var onPersistWindowFrame: ((WindowFrameState?) -> Void)?

    init<Content: View>(rootView: Content, initialFrame: WindowFrameState? = nil) {
        let hostingController = NSHostingController(rootView: rootView)
        let window = TeleFeedWindow(contentViewController: hostingController)
        window.title = L10n.tr("app.title")
        window.setContentSize(NSSize(width: 1480, height: 920))
        window.minSize = NSSize(width: 1180, height: 760)
        window.styleMask = [.titled, .closable, .miniaturizable, .resizable, .fullSizeContentView]
        window.titleVisibility = .hidden
        window.titlebarAppearsTransparent = true
        window.backgroundColor = .windowBackgroundColor
        window.isReleasedWhenClosed = false
        super.init(window: window)
        window.delegate = self

        if let initialFrame {
            Self.logger.debug("Restoring window frame from app state: \(initialFrame.rect.debugDescription, privacy: .public)")
            window.setFrame(initialFrame.rect, display: false)
        } else {
            Self.logger.debug("No saved window frame found, centering window")
            window.center()
        }
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    func showWindowAndActivate() {
        guard let window else {
            return
        }

        Self.logger.debug("Showing window at frame: \(window.frame.debugDescription, privacy: .public)")
        NSApp.activate(ignoringOtherApps: true)
        window.makeKeyAndOrderFront(nil)
    }

    func saveWindowFrame() {
        guard let window else {
            return
        }

        Self.logger.debug("Saving window frame: \(window.frame.debugDescription, privacy: .public)")
        onPersistWindowFrame?(WindowFrameState(window.frame))
    }
}

private final class TeleFeedWindow: NSWindow {
    override func performKeyEquivalent(with event: NSEvent) -> Bool {
        guard event.modifierFlags.contains(.command) else {
            return super.performKeyEquivalent(with: event)
        }

        let handled: Bool
        switch event.charactersIgnoringModifiers?.lowercased() {
        case "c":
            handled = NSApp.sendAction(#selector(NSText.copy(_:)), to: nil, from: nil)
        case "v":
            handled = NSApp.sendAction(#selector(NSText.paste(_:)), to: nil, from: nil)
        case "x":
            handled = NSApp.sendAction(#selector(NSText.cut(_:)), to: nil, from: nil)
        case "a":
            handled = NSApp.sendAction(#selector(NSText.selectAll(_:)), to: nil, from: nil)
        default:
            handled = false
        }

        if handled {
            return true
        }

        return super.performKeyEquivalent(with: event)
    }
}

extension MainWindowController: NSWindowDelegate {
    func windowWillClose(_ notification: Notification) {
        Self.logger.debug("Window will close")
        saveWindowFrame()
    }

    func windowDidEndLiveResize(_ notification: Notification) {
        Self.logger.debug("Window did end live resize")
        saveWindowFrame()
    }

    func windowDidResize(_ notification: Notification) {
        Self.logger.debug("Window did resize")
        saveWindowFrame()
    }

    func windowDidMove(_ notification: Notification) {
        Self.logger.debug("Window did move")
        saveWindowFrame()
    }
}
