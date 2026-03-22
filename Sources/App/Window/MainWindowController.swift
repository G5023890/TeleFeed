import AppKit
import SwiftUI

@MainActor
final class MainWindowController: NSWindowController {
    private static let autosaveName = "MainWindow"

    init<Content: View>(rootView: Content) {
        let hostingController = NSHostingController(rootView: rootView)
        let window = NSWindow(contentViewController: hostingController)
        window.title = L10n.tr("app.title")
        window.setContentSize(NSSize(width: 1180, height: 760))
        window.styleMask = [.titled, .closable, .miniaturizable, .resizable, .fullSizeContentView]
        window.titleVisibility = .hidden
        window.titlebarAppearsTransparent = true
        window.isReleasedWhenClosed = false
        window.setFrameAutosaveName(Self.autosaveName)
        if window.setFrameUsingName(Self.autosaveName) == false {
            window.center()
        }
        super.init(window: window)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    func showWindowAndActivate() {
        guard let window else {
            return
        }

        NSApp.activate(ignoringOtherApps: true)
        window.makeKeyAndOrderFront(nil)
    }

    func saveWindowFrame() {
        guard let window else {
            return
        }

        window.saveFrame(usingName: Self.autosaveName)
    }
}
