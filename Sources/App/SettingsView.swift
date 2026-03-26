import SwiftUI

struct SettingsView: View {
    @ObservedObject var authViewModel: AuthViewModel
    @Binding var launchAtLoginEnabled: Bool
    let onSaveCredentials: () -> Void
    let onLogout: () -> Void
    let onClose: () -> Void
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            Text(L10n.tr("settings.title"))
                .font(.system(size: 24, weight: .semibold, design: .rounded))

            VStack(alignment: .leading, spacing: 12) {
                TextField(L10n.tr("auth.apiId"), text: $authViewModel.apiID)
                    .textFieldStyle(.roundedBorder)

                SecureField(L10n.tr("auth.apiHash"), text: $authViewModel.apiHash)
                    .textFieldStyle(.roundedBorder)

                Toggle(L10n.tr("settings.launchAtLogin"), isOn: $launchAtLoginEnabled)

                Text(L10n.tr("settings.storageNote"))
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }

            if let errorMessage = authViewModel.errorMessage {
                Text(errorMessage)
                    .font(.callout)
                    .foregroundStyle(.red)
            }

            HStack {
                Button(L10n.tr("general.save"), action: onSaveCredentials)
                    .buttonStyle(.borderedProminent)

                Button(L10n.tr("settings.logout"), role: .destructive, action: onLogout)
                    .buttonStyle(.bordered)

                Spacer()

                Button(L10n.tr("settings.close"), action: onClose)
                    .buttonStyle(.bordered)
            }
        }
        .padding(28)
        .frame(width: 520)
        .background(AppTheme.surfaceFill(for: colorScheme))
    }
}
