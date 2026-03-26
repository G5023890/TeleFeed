import SwiftUI

struct AuthView: View {
    @ObservedObject var viewModel: AuthViewModel
    let onSaveCredentials: () -> Void
    let onRefreshQR: () -> Void
    let onSubmitPassword: () -> Void
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                header

                switch viewModel.state {
                case .missingCredentials:
                    credentialsCard
                case .waitingForQRCode:
                    qrCard
                case .waitingPassword:
                    passwordCard
                case .ready:
                    statusCard(text: L10n.tr("auth.authorized"))
                case .initializing:
                    statusCard(text: L10n.tr("auth.loggingIn"))
                case .waitingPhoneNumber:
                    statusCard(text: L10n.tr("auth.waiting"))
                case .loggingOut:
                    statusCard(text: L10n.tr("auth.loggingIn"))
                case .closed:
                    statusCard(text: L10n.tr("auth.waiting"))
                case .failed(let message):
                    statusCard(text: message)
                }

                if let errorMessage = viewModel.errorMessage {
                    Text(errorMessage)
                        .font(.callout)
                        .foregroundStyle(.red)
                }

                if viewModel.hasDebugMessage {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("TDLib Debug")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(.secondary)

                        Text(viewModel.debugMessage)
                            .font(.caption.monospaced())
                            .textSelection(.enabled)
                            .foregroundStyle(.secondary)
                    }
                    .padding(16)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(AppTheme.surfaceFill(for: colorScheme), in: RoundedRectangle(cornerRadius: 18, style: .continuous))
                    .overlay(
                        RoundedRectangle(cornerRadius: 18, style: .continuous)
                            .strokeBorder(AppTheme.surfaceStroke(for: colorScheme), lineWidth: 1)
                    )
                }

                Text(L10n.tr("auth.currentState", viewModel.stateDebugLabel))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .padding(28)
        }
        .background(.clear)
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(L10n.tr("auth.title"))
                .font(.system(size: 28, weight: .semibold, design: .rounded))

            Text(L10n.tr("settings.storageNote"))
                .font(.callout)
                .foregroundStyle(.secondary)
        }
    }

    private var credentialsCard: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text(L10n.tr("auth.credentialsTitle"))
                .font(.headline)

            TextField(L10n.tr("auth.apiId"), text: $viewModel.apiID)
                .textFieldStyle(.roundedBorder)

            SecureField(L10n.tr("auth.apiHash"), text: $viewModel.apiHash)
                .textFieldStyle(.roundedBorder)

            Button(L10n.tr("auth.saveCredentials"), action: onSaveCredentials)
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
                .disabled(viewModel.apiID.isEmpty || viewModel.apiHash.isEmpty || viewModel.isBusy)
        }
        .padding(24)
        .background(AppTheme.surfaceFill(for: colorScheme), in: RoundedRectangle(cornerRadius: 24, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 24, style: .continuous)
                .strokeBorder(AppTheme.surfaceStroke(for: colorScheme), lineWidth: 1)
        )
    }

    private var qrCard: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text(L10n.tr("auth.qrTitle"))
                .font(.headline)

            if let qrImage = viewModel.qrImage {
                Image(nsImage: qrImage)
                    .interpolation(.none)
                    .resizable()
                    .scaledToFit()
                    .frame(width: 240, height: 240)
                    .padding(16)
                    .background(Color.white, in: RoundedRectangle(cornerRadius: 28, style: .continuous))
            }

            Text(L10n.tr("auth.trustedDevice"))
                .font(.callout)
                .foregroundStyle(.secondary)

            if let qrLink = viewModel.qrLink {
                Text(qrLink)
                    .font(.footnote.monospaced())
                    .textSelection(.enabled)
                    .foregroundStyle(.secondary)
            }

            Button(L10n.tr("auth.regenerateQR"), action: onRefreshQR)
                .buttonStyle(.borderedProminent)
                .disabled(viewModel.isBusy)
        }
        .padding(24)
        .background(AppTheme.surfaceFill(for: colorScheme), in: RoundedRectangle(cornerRadius: 24, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 24, style: .continuous)
                .strokeBorder(AppTheme.surfaceStroke(for: colorScheme), lineWidth: 1)
        )
    }

    private var passwordCard: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text(L10n.tr("auth.passwordTitle"))
                .font(.headline)

            if viewModel.passwordHint.isEmpty == false {
                Text(viewModel.passwordHint)
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }

            SecureField(L10n.tr("auth.passwordPlaceholder"), text: $viewModel.password)
                .textFieldStyle(.roundedBorder)

            Button(L10n.tr("auth.submitPassword"), action: onSubmitPassword)
                .buttonStyle(.borderedProminent)
                .disabled(viewModel.password.isEmpty || viewModel.isBusy)
        }
        .padding(24)
        .background(AppTheme.surfaceFill(for: colorScheme), in: RoundedRectangle(cornerRadius: 24, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 24, style: .continuous)
                .strokeBorder(AppTheme.surfaceStroke(for: colorScheme), lineWidth: 1)
        )
    }

    private func statusCard(text: String) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(text)
                .font(.headline)

            if case .waitingPhoneNumber = viewModel.state {
                Button(L10n.tr("auth.generateQR"), action: onRefreshQR)
                    .buttonStyle(.borderedProminent)
            } else if case .initializing = viewModel.state {
                Text(L10n.tr("auth.notLoggedIn"))
                    .font(.callout)
                    .foregroundStyle(.secondary)

                Button(L10n.tr("auth.retryLogin"), action: onRefreshQR)
                    .buttonStyle(.borderedProminent)
            }
        }
        .padding(24)
        .background(AppTheme.surfaceFill(for: colorScheme), in: RoundedRectangle(cornerRadius: 24, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 24, style: .continuous)
                .strokeBorder(AppTheme.surfaceStroke(for: colorScheme), lineWidth: 1)
        )
    }
}
