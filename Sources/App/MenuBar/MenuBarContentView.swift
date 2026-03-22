import SwiftUI

struct MenuBarContentView: View {
    @ObservedObject var runtime: AppRuntime

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            VStack(alignment: .leading, spacing: 4) {
                Text(L10n.tr("app.title"))
                    .font(.headline)

                Text(runtime.mainViewModel.connectionLabel)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Divider()

            Button(L10n.tr("menu.open")) {
                runtime.openHome()
            }

            Button(L10n.tr("menu.settings")) {
                runtime.openSettings()
            }
            .keyboardShortcut(",")

            Divider()

            Button(L10n.tr("menu.quit")) {
                runtime.quit()
            }
            .keyboardShortcut("q")
        }
        .padding(12)
        .frame(width: 220)
    }
}
