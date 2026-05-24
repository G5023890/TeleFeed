import SwiftUI
import CoreImage.CIFilterBuiltins

struct NewsSourcesDrawerView: View {
    @ObservedObject var viewModel: IOSNewsFlowViewModel
    @Environment(\.colorScheme) private var colorScheme
    private let qrContext = CIContext()

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 22) {
                header
                filterSection
                telegramAuthSection
                telegramSection
                rssSection

                if let errorMessage = viewModel.errorMessage {
                    Text(errorMessage)
                        .font(.footnote.weight(.semibold))
                        .foregroundStyle(.red)
                }

                if let statusMessage = viewModel.statusMessage {
                    Text(statusMessage)
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
            }
            .padding(20)
        }
        .scrollIndicators(.hidden)
        .frame(maxWidth: 390, maxHeight: .infinity)
        .background(drawerBackground, in: RoundedRectangle(cornerRadius: 34, style: .continuous))
        .glassEffect(.regular, in: RoundedRectangle(cornerRadius: 34, style: .continuous))
        .padding(.horizontal, 18)
        .padding(.vertical, 18)
    }

    private var header: some View {
        HStack(alignment: .top, spacing: 12) {
            VStack(alignment: .leading, spacing: 4) {
                Text("Watched Channels")
                    .font(.system(size: 30, weight: .bold, design: .rounded))
                    .lineLimit(2)
                Text("Telegram channels and RSS feeds")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }

            Spacer(minLength: 0)

            Text("\(viewModel.watchedChannels.count + viewModel.rssFeeds.count)")
                .font(.headline.weight(.bold))
                .frame(minWidth: 48, minHeight: 42)
                .background(.thinMaterial, in: Capsule(style: .continuous))

            Button {
                viewModel.dismissSourcesDrawer()
            } label: {
                Image(systemName: "xmark")
                    .font(.title3.weight(.bold))
                    .frame(width: 42, height: 42)
            }
            .buttonStyle(.glass)
        }
    }

    @ViewBuilder
    private var telegramAuthSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            sectionTitle(
                title: "Telegram Authorization",
                subtitle: telegramAuthSubtitle,
                count: telegramAuthBadge
            )

            switch viewModel.authState {
            case .missingCredentials, .closed, .failed:
                telegramCredentialsForm
            case .initializing, .loggingOut:
                telegramStatusRow("Telegram подключается")
            case .waitingPhoneNumber:
                telegramStatusRow("Войдите через QR-код с доверенного устройства")
                Button {
                    viewModel.refreshQRCode()
                } label: {
                    Label("Войти по QR", systemImage: "qrcode")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.glassProminent)
                .disabled(viewModel.isBusy)
            case .waitingForQRCode(let link):
                telegramQRCode(link: link)
            case .waitingPassword(let hint):
                telegramPasswordForm(hint: hint)
            case .ready:
                telegramStatusRow("Telegram авторизован")
            }
        }
    }

    private var telegramCredentialsForm: some View {
        VStack(alignment: .leading, spacing: 10) {
            TextField("API ID", text: $viewModel.apiID)
                .keyboardType(.numberPad)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
                .padding(.horizontal, 12)
                .padding(.vertical, 11)
                .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 18, style: .continuous))

            SecureField("API Hash", text: $viewModel.apiHash)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
                .padding(.horizontal, 12)
                .padding(.vertical, 11)
                .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 18, style: .continuous))

            Button {
                viewModel.saveCredentials()
            } label: {
                Label("Сохранить и подключить", systemImage: "key")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.glassProminent)
            .disabled(viewModel.apiID.isEmpty || viewModel.apiHash.isEmpty || viewModel.isBusy)
        }
    }

    @ViewBuilder
    private func telegramQRCode(link: String?) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            if let link, let image = qrImage(from: link) {
                Image(uiImage: image)
                    .interpolation(.none)
                    .resizable()
                    .scaledToFit()
                    .frame(width: 220, height: 220)
                    .padding(14)
                    .background(Color.white, in: RoundedRectangle(cornerRadius: 26, style: .continuous))
                    .frame(maxWidth: .infinity)
            }

            if let link {
                Text(link)
                    .font(.footnote.monospaced())
                    .foregroundStyle(.secondary)
                    .textSelection(.enabled)
            }

            Button {
                viewModel.refreshQRCode()
            } label: {
                Label("Обновить QR", systemImage: "arrow.clockwise")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.glass)
            .disabled(viewModel.isBusy)
        }
    }

    private func telegramPasswordForm(hint: String) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            if hint.isEmpty == false {
                Text(hint)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }

            SecureField("Пароль 2FA", text: $viewModel.password)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
                .padding(.horizontal, 12)
                .padding(.vertical, 11)
                .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 18, style: .continuous))

            Button {
                viewModel.submitPassword()
            } label: {
                Label("Отправить пароль", systemImage: "lock.open")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.glassProminent)
            .disabled(viewModel.password.isEmpty || viewModel.isBusy)
        }
    }

    private func telegramStatusRow(_ text: String) -> some View {
        Text(text)
            .font(.subheadline)
            .foregroundStyle(.secondary)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(16)
            .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 22, style: .continuous))
    }

    private var filterSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            Picker("Источник", selection: $viewModel.draftFilter.source) {
                ForEach(NewsSourceFilter.allCases) { filter in
                    Text(filter.title).tag(filter)
                }
            }
            .pickerStyle(.segmented)

            TextField("Поиск", text: $viewModel.draftFilter.query)
                .textInputAutocapitalization(.sentences)
                .submitLabel(.search)
                .padding(.horizontal, 12)
                .padding(.vertical, 11)
                .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 18, style: .continuous))

            Button {
                viewModel.applyDrawerFilters()
            } label: {
                Label("Apply", systemImage: "line.3.horizontal.decrease.circle")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.glassProminent)
        }
    }

    private var telegramSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            sectionTitle(
                title: "Telegram Feed",
                subtitle: telegramSubtitle,
                count: viewModel.watchedChannels.count
            )

            HStack(spacing: 10) {
                TextField("@channel or https://t.me/channel", text: $viewModel.telegramInput)
                    .keyboardType(.URL)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    .padding(.horizontal, 12)
                    .padding(.vertical, 11)
                    .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 18, style: .continuous))

                Button {
                    viewModel.addTelegramChannel()
                } label: {
                    Text("Add")
                        .font(.headline)
                }
                .buttonStyle(.glass)
                .disabled(viewModel.isBusy || viewModel.telegramInput.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }

            if viewModel.watchedChannels.isEmpty {
                emptySourceRow("Telegram подключится после авторизации")
            } else {
                ForEach(viewModel.watchedChannels) { channel in
                    sourceRow(
                        title: channel.displayTitle,
                        subtitle: channel.username.isEmpty ? "Telegram" : "@\(channel.username)",
                        initial: String(channel.displayTitle.prefix(1)),
                        isSelected: viewModel.selectedChannelID == channel.chatID
                    ) {
                        viewModel.selectedChannelID = channel.chatID
                    }
                }
            }

            Button {
                viewModel.removeSelectedChannel()
            } label: {
                Text("Remove")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.glass)
            .disabled(viewModel.selectedChannelID == nil)
        }
    }

    private var rssSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            sectionTitle(
                title: "RSS Feeds",
                subtitle: "Add public RSS or Atom feeds",
                count: viewModel.rssFeeds.count
            )

            HStack(spacing: 10) {
                TextField("https://example.com/feed.xml", text: $viewModel.rssInput)
                    .keyboardType(.URL)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    .padding(.horizontal, 12)
                    .padding(.vertical, 11)
                    .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 18, style: .continuous))

                Button {
                    viewModel.addRSSFeed()
                } label: {
                    Text("Add RSS")
                        .font(.headline)
                }
                .buttonStyle(.glass)
                .disabled(viewModel.isBusy)
            }

            ForEach(viewModel.rssFeeds) { feed in
                sourceRow(
                    title: feed.title,
                    subtitle: feed.feedURL?.host()?.replacingOccurrences(of: "www.", with: "") ?? feed.urlString,
                    initial: String(feed.title.prefix(1)),
                    isSelected: viewModel.selectedRSSFeedID == feed.id
                ) {
                    viewModel.selectedRSSFeedID = feed.id
                }
            }

            Button {
                viewModel.removeSelectedRSSFeed()
            } label: {
                Text("Remove")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.glass)
            .disabled(viewModel.selectedRSSFeedID == nil)
        }
    }

    private func sectionTitle(title: String, subtitle: String, count: Int) -> some View {
        HStack(alignment: .firstTextBaseline) {
            VStack(alignment: .leading, spacing: 3) {
                Text(title)
                    .font(.system(size: 24, weight: .bold, design: .rounded))
                Text(subtitle)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }

            Spacer(minLength: 0)

            Text("\(count)")
                .font(.headline.weight(.bold))
                .frame(minWidth: 48, minHeight: 42)
                .background(.thinMaterial, in: Capsule(style: .continuous))
        }
    }

    private func sourceRow(
        title: String,
        subtitle: String,
        initial: String,
        isSelected: Bool,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            HStack(spacing: 14) {
                Text(initial.uppercased())
                    .font(.headline.weight(.bold))
                    .foregroundStyle(.secondary)
                    .frame(width: 54, height: 54)
                    .background(.thinMaterial, in: Circle())

                VStack(alignment: .leading, spacing: 4) {
                    Text(title)
                        .font(.headline.weight(.bold))
                        .foregroundStyle(.primary)
                        .lineLimit(1)
                    Text(subtitle)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }

                Spacer(minLength: 0)
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 12)
            .background(
                sourceFill(isSelected: isSelected),
                in: RoundedRectangle(cornerRadius: 24, style: .continuous)
            )
            .glassEffect(.clear.interactive(), in: RoundedRectangle(cornerRadius: 24, style: .continuous))
        }
        .buttonStyle(.plain)
    }

    private func emptySourceRow(_ text: String) -> some View {
        Text(text)
            .font(.subheadline)
            .foregroundStyle(.secondary)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(16)
            .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 22, style: .continuous))
    }

    private var telegramSubtitle: String {
        switch viewModel.authState {
        case .ready:
            return "Default and added Telegram channels"
        default:
            return "Waiting for Telegram authorization"
        }
    }

    private var telegramAuthSubtitle: String {
        switch viewModel.authState {
        case .ready:
            return "Telegram готов к загрузке каналов"
        case .missingCredentials:
            return "Введите API ID и API Hash"
        case .waitingForQRCode:
            return "Сканируйте QR в Telegram"
        case .waitingPassword:
            return "Введите пароль двухфакторной защиты"
        case .failed(let message):
            return message
        default:
            return "Подключение аккаунта Telegram"
        }
    }

    private var telegramAuthBadge: Int {
        viewModel.authState == .ready ? 1 : 0
    }

    private var drawerBackground: Color {
        colorScheme == .dark ? Color.black.opacity(0.28) : Color.white.opacity(0.72)
    }

    private func sourceFill(isSelected: Bool) -> Color {
        if colorScheme == .dark {
            return Color.white.opacity(isSelected ? 0.12 : 0.05)
        }
        return Color.white.opacity(isSelected ? 0.84 : 0.56)
    }

    private func qrImage(from link: String) -> UIImage? {
        let filter = CIFilter.qrCodeGenerator()
        filter.message = Data(link.utf8)
        filter.correctionLevel = "M"

        guard let outputImage = filter.outputImage?.transformed(by: CGAffineTransform(scaleX: 12, y: 12)),
              let cgImage = qrContext.createCGImage(outputImage, from: outputImage.extent)
        else {
            return nil
        }

        return UIImage(cgImage: cgImage)
    }
}
