import SwiftUI
import AppKit

@main
struct TelegaApp: App {
    @NSApplicationDelegateAdaptor(TelegaAppDelegate.self) private var appDelegate

    var body: some Scene {
        Settings {
            EmptyView()
        }
    }
}
