import AppKit
import SwiftUI

@MainActor
final class SettingsWindowController: NSWindowController {
    init(viewModel: MainViewModel) {
        let rootView = SettingsView(
            authViewModel: viewModel.authViewModel,
            launchAtLoginEnabled: Binding(
                get: { viewModel.settings.launchAtLoginEnabled },
                set: { viewModel.updateLaunchAtLogin($0) }
            ),
            showDockIcon: Binding(
                get: { viewModel.settings.showDockIcon },
                set: { viewModel.updateShowDockIcon($0) }
            ),
            showMenuBarIcon: Binding(
                get: { viewModel.settings.showMenuBarIcon },
                set: { viewModel.updateShowMenuBarIcon($0) }
            ),
            typography: Binding(
                get: { viewModel.settings.typography },
                set: { viewModel.updateTypography($0) }
            ),
            menuBarIconStyle: Binding(
                get: { viewModel.settings.menuBarIconStyle },
                set: { viewModel.updateMenuBarIconStyle($0) }
            ),
            onSaveCredentials: viewModel.saveCredentials,
            onLogout: viewModel.logout,
            onClose: {
                viewModel.closeSettings()
                NSApp.keyWindow?.performClose(nil)
            }
        )

        let hostingController = NSHostingController(rootView: rootView)
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 560, height: 720),
            styleMask: [.titled, .closable, .miniaturizable, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )
        window.contentViewController = hostingController
        window.title = L10n.tr("settings.title")
        window.titleVisibility = .hidden
        window.titlebarAppearsTransparent = true
        window.isReleasedWhenClosed = false
        window.center()

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
}
