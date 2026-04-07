import SwiftUI
import AppKit

@main
struct TeleFeedApp: App {
    @NSApplicationDelegateAdaptor(TeleFeedAppDelegate.self) private var appDelegate

    var body: some Scene {
        Settings {
            SettingsRootView(viewModel: appDelegate.runtime.container.mainViewModel)
        }
    }
}

private struct SettingsRootView: View {
    @ObservedObject var viewModel: MainViewModel
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        SettingsView(
            authViewModel: viewModel.authViewModel,
            launchAtLoginEnabled: Binding(
                get: { viewModel.settings.launchAtLoginEnabled },
                set: { viewModel.updateLaunchAtLogin($0) }
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
                dismiss()
            }
        )
        .frame(minWidth: 560, minHeight: 720)
    }
}
