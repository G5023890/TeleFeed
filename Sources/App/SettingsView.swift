import SwiftUI
import AppKit

struct SettingsView: View {
    @ObservedObject var authViewModel: AuthViewModel
    @Binding var launchAtLoginEnabled: Bool
    @Binding var typography: TypographySettings
    @Binding var menuBarIconStyle: MenuBarIconStyle
    let onSaveCredentials: () -> Void
    let onLogout: () -> Void
    let onClose: () -> Void
    @Environment(\.colorScheme) private var colorScheme
    @State private var selectedTab: SettingsTab = .general

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            Text(L10n.tr("settings.title"))
                .font(.system(size: 24, weight: .semibold, design: .rounded))

            Text(selectedTab.helpText)
                .font(.callout)
                .foregroundStyle(.secondary)

            Picker("", selection: $selectedTab) {
                Text(L10n.tr("settings.generalTitle")).tag(SettingsTab.general)
                Text(L10n.tr("settings.typographyTitle")).tag(SettingsTab.typography)
            }
            .pickerStyle(.segmented)

            ScrollView {
            selectedTabContent
                    .padding(.trailing, 4)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)

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
        .frame(width: 560, height: 720, alignment: .leading)
        .background(AppTheme.surfaceFill(for: colorScheme))
    }

    @ViewBuilder
    private var selectedTabContent: some View {
        switch selectedTab {
        case .general:
            generalSection
        case .typography:
            typographySection
        }
    }

    private var generalSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            sectionHeader(L10n.tr("settings.generalTitle"))

            Text(L10n.tr("settings.generalHint"))
                .font(.callout)
                .foregroundStyle(.secondary)

            VStack(alignment: .leading, spacing: 12) {
                menuBarIconPicker

                TextField(L10n.tr("auth.apiId"), text: $authViewModel.apiID)
                    .textFieldStyle(.roundedBorder)

                SecureField(L10n.tr("auth.apiHash"), text: $authViewModel.apiHash)
                    .textFieldStyle(.roundedBorder)

                Toggle(L10n.tr("settings.launchAtLogin"), isOn: $launchAtLoginEnabled)

                Text(L10n.tr("settings.storageNote"))
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
            .padding(16)
            .background(AppTheme.viewerFill(for: colorScheme), in: RoundedRectangle(cornerRadius: 20, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 20, style: .continuous)
                    .strokeBorder(AppTheme.surfaceStroke(for: colorScheme), lineWidth: 1)
            )
        }
    }

    private var menuBarIconPicker: some View {
        VStack(alignment: .leading, spacing: 10) {
            sectionHeader(L10n.tr("settings.menuBarIconTitle"))

            Text(L10n.tr("settings.menuBarIconHint"))
                .font(.callout)
                .foregroundStyle(.secondary)

            HStack(alignment: .center, spacing: 14) {
                menuBarIconOption(
                    style: .current,
                    resourceName: "IconTeleFeed",
                    accessibilityLabel: L10n.tr("settings.menuBarIcon.current")
                )

                menuBarIconOption(
                    style: .telegramRSS,
                    resourceName: "MenuBarIconTelegramRSS",
                    accessibilityLabel: L10n.tr("settings.menuBarIcon.telegramRSS")
                )

                menuBarIconOption(
                    style: .telegramRSS2,
                    resourceName: "MenuBarIconTelegramRSS2",
                    accessibilityLabel: L10n.tr("settings.menuBarIcon.telegramRSS2")
                )
            }
        }
    }

    private func menuBarIconOption(
        style: MenuBarIconStyle,
        resourceName: String,
        accessibilityLabel: String
    ) -> some View {
        Button {
            menuBarIconStyle = style
        } label: {
            iconPreview(resourceName: resourceName)
                .frame(width: 42, height: 42)
                .padding(8)
                .background(
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .fill(style == menuBarIconStyle ? AppTheme.surfaceStroke(for: colorScheme).opacity(0.18) : Color.clear)
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .strokeBorder(
                            style == menuBarIconStyle ? Color.accentColor : AppTheme.surfaceStroke(for: colorScheme),
                            lineWidth: style == menuBarIconStyle ? 2 : 1
                        )
                )
        }
        .buttonStyle(.plain)
        .accessibilityLabel(accessibilityLabel)
    }

    private func iconPreview(resourceName: String) -> some View {
        Group {
            if let url = Bundle.main.url(forResource: resourceName, withExtension: "png", subdirectory: "Assets/Icons"),
               let image = NSImage(contentsOf: url) {
                Image(nsImage: image)
                    .resizable()
                    .scaledToFit()
            } else {
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(Color.secondary.opacity(0.15))
            }
        }
    }

    private var typographySection: some View {
        VStack(alignment: .leading, spacing: 12) {
            sectionHeader(L10n.tr("settings.typographyTitle"))

            Text(L10n.tr("settings.typographyHint"))
                .font(.callout)
                .foregroundStyle(.secondary)

            VStack(alignment: .leading, spacing: 16) {
                TypographyGroup(
                    title: L10n.tr("settings.typography.feed"),
                    rows: [
                        AnyView(typographyRow(L10n.tr("settings.typography.feedHeaderTitle"), value: $typography.feedHeaderTitle, range: 14...26)),
                        AnyView(typographyRow(L10n.tr("settings.typography.feedTitle"), value: $typography.feedTitle, range: 11...20)),
                        AnyView(typographyRow(L10n.tr("settings.typography.feedSource"), value: $typography.feedSource, range: 9...16)),
                        AnyView(typographyRow(L10n.tr("settings.typography.feedBody"), value: $typography.feedBody, range: 10...18)),
                        AnyView(typographyRow(L10n.tr("settings.typography.feedDate"), value: $typography.feedDate, range: 9...15)),
                        AnyView(typographyRow(L10n.tr("settings.typography.feedFilter"), value: $typography.feedFilter, range: 10...16, step: 0.5)),
                    ]
                )

                TypographyGroup(
                    title: L10n.tr("settings.typography.viewer"),
                    rows: [
                        AnyView(typographyRow(L10n.tr("settings.typography.viewerChannelTitle"), value: $typography.viewerChannelTitle, range: 12...22)),
                        AnyView(typographyRow(L10n.tr("settings.typography.viewerTitle"), value: $typography.viewerTitle, range: 18...30)),
                        AnyView(typographyRow(L10n.tr("settings.typography.viewerMeta"), value: $typography.viewerMeta, range: 10...18)),
                        AnyView(typographyRow(L10n.tr("settings.typography.viewerBody"), value: $typography.viewerBody, range: 14...24)),
                        AnyView(typographyRow(L10n.tr("settings.typography.viewerCaption"), value: $typography.viewerCaption, range: 11...20)),
                    ]
                )

                TypographyGroup(
                    title: L10n.tr("settings.typography.reader"),
                    rows: [
                        AnyView(typographyRow(L10n.tr("settings.typography.readerChannelTitle"), value: $typography.readerChannelTitle, range: 12...22)),
                        AnyView(typographyRow(L10n.tr("settings.typography.readerTitle"), value: $typography.readerTitle, range: 18...30)),
                        AnyView(typographyRow(L10n.tr("settings.typography.readerMeta"), value: $typography.readerMeta, range: 10...18)),
                        AnyView(typographyRow(L10n.tr("settings.typography.readerBody"), value: $typography.readerBody, range: 14...24)),
                        AnyView(typographyRow(L10n.tr("settings.typography.readerQuote"), value: $typography.readerQuote, range: 12...22)),
                        AnyView(typographyRow(L10n.tr("settings.typography.readerListBullet"), value: $typography.readerListBullet, range: 12...22)),
                        AnyView(typographyRow(L10n.tr("settings.typography.readerCode"), value: $typography.readerCode, range: 11...20)),
                        AnyView(typographyRow(L10n.tr("settings.typography.readerHeading1"), value: $typography.readerHeading1, range: 20...40)),
                        AnyView(typographyRow(L10n.tr("settings.typography.readerHeading2"), value: $typography.readerHeading2, range: 18...36)),
                        AnyView(typographyRow(L10n.tr("settings.typography.readerHeading3"), value: $typography.readerHeading3, range: 16...32)),
                        AnyView(typographyRow(L10n.tr("settings.typography.readerHeading4"), value: $typography.readerHeading4, range: 14...28)),
                        AnyView(typographyRow(L10n.tr("settings.typography.readerHeading5"), value: $typography.readerHeading5, range: 12...26)),
                        AnyView(typographyRow(L10n.tr("settings.typography.readerHeading6"), value: $typography.readerHeading6, range: 12...26)),
                    ]
                )

                HStack {
                    Button(L10n.tr("settings.typography.reset")) {
                        typography = TypographySettings()
                    }
                    .buttonStyle(.bordered)

                    Spacer()
                }
            }
            .padding(16)
            .background(AppTheme.viewerFill(for: colorScheme), in: RoundedRectangle(cornerRadius: 20, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 20, style: .continuous)
                    .strokeBorder(AppTheme.surfaceStroke(for: colorScheme), lineWidth: 1)
            )
        }
    }

    private func sectionHeader(_ title: String) -> some View {
        Text(title)
            .font(.system(size: 15, weight: .semibold, design: .rounded))
            .foregroundStyle(.secondary)
    }

    private func typographyRow(
        _ title: String,
        value: Binding<Double>,
        range: ClosedRange<Double>,
        step: Double = 1
    ) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(alignment: .firstTextBaseline) {
                Text(title)
                    .font(.callout.weight(.semibold))

                Spacer(minLength: 12)

                Text("\(String(format: "%.1f", value.wrappedValue)) pt")
                    .font(.caption.monospaced())
                    .foregroundStyle(.secondary)
            }

            Slider(value: value, in: range, step: step)
        }
    }
}

private enum SettingsTab: Hashable {
    case general
    case typography

    var helpText: String {
        switch self {
        case .general:
            return L10n.tr("settings.generalHint")
        case .typography:
            return L10n.tr("settings.typographyHint")
        }
    }
}

private struct TypographyGroup: View {
    let title: String
    let rows: [AnyView]

    init(title: String, rows: [AnyView]) {
        self.title = title
        self.rows = rows
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(title)
                .font(.system(size: 13, weight: .semibold, design: .rounded))
                .foregroundStyle(.secondary)

            VStack(alignment: .leading, spacing: 12) {
                ForEach(Array(rows.enumerated()), id: \.offset) { _, row in
                    row
                }
            }
        }
    }
}
