import SwiftUI
import AppKit

struct MainContentView: View {
    @ObservedObject var viewModel: MainViewModel

    var body: some View {
        ZStack {
            appBackground

            content
                .padding(.horizontal, 16)
                .padding(.top, -10)
                .padding(.bottom, 16)

            if viewModel.isSidebarPresented {
                drawerBackdrop
                channelDrawer
                    .transition(.move(edge: .leading).combined(with: .opacity))
                    .zIndex(2)
            }
        }
        .animation(.snappy(duration: 0.25), value: viewModel.isSidebarPresented)
        .onExitCommand {
            if viewModel.closeSidebar() == false {
                NSApp.keyWindow?.performClose(nil)
            }
        }
        .toolbar {
            ToolbarItemGroup(placement: .automatic) {
                Button {
                    withAnimation(.snappy(duration: 0.25)) {
                        viewModel.isSidebarPresented = true
                    }
                } label: {
                    Image(systemName: "plus")
                }
                .help(L10n.tr("sidebar.addChannel"))

                Text(viewModel.connectionLabel)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 6)
                    .background(Color.white.opacity(0.72), in: Capsule(style: .continuous))
                    .overlay(
                        Capsule(style: .continuous)
                            .strokeBorder(Color.black.opacity(0.04), lineWidth: 1)
                    )

                Button {
                    Task {
                        await viewModel.refreshSelectedChannel()
                    }
                } label: {
                    Image(systemName: "arrow.clockwise")
                }
                .help(L10n.tr("feed.refresh"))

                Button {
                    viewModel.openSettings()
                } label: {
                    Image(systemName: "gearshape")
                }
                .help(L10n.tr("menu.settings"))
            }
        }
        .sheet(isPresented: $viewModel.showingSettings) {
            SettingsView(
                authViewModel: viewModel.authViewModel,
                launchAtLoginEnabled: Binding(
                    get: { viewModel.settings.launchAtLoginEnabled },
                    set: { viewModel.updateLaunchAtLogin($0) }
                ),
                onSaveCredentials: viewModel.saveCredentials,
                onLogout: viewModel.logout,
                onClose: viewModel.closeSettings
            )
        }
    }

    private var appBackground: some View {
        ZStack {
            LinearGradient(
                colors: [
                    Color(red: 0.97, green: 0.95, blue: 0.92),
                    Color(red: 0.94, green: 0.92, blue: 0.89),
                    Color(red: 0.92, green: 0.90, blue: 0.87),
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )

            RadialGradient(
                colors: [
                    Color.white.opacity(0.72),
                    .clear
                ],
                center: .topTrailing,
                startRadius: 20,
                endRadius: 520
            )
            .blendMode(.screen)
            .offset(x: -180, y: -160)

            RadialGradient(
                colors: [
                    Color(red: 0.98, green: 0.90, blue: 0.80).opacity(0.52),
                    .clear
                ],
                center: .bottomLeading,
                startRadius: 20,
                endRadius: 540
            )
            .blendMode(.screen)
            .offset(x: 180, y: 140)
        }
        .ignoresSafeArea()
    }

    @ViewBuilder
    private var content: some View {
        if case .ready = viewModel.authViewModel.state {
            VStack(spacing: 10) {
                HSplitView {
                    unreadColumn
                        .frame(
                            minWidth: max(260, viewModel.unreadColumnWidth - 45),
                            idealWidth: viewModel.unreadColumnWidth,
                            maxWidth: min(390, viewModel.unreadColumnWidth + 55)
                        )

                    detailColumn
                        .frame(minWidth: 700, idealWidth: 980, maxWidth: .infinity)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        } else {
            AuthView(
                viewModel: viewModel.authViewModel,
                onSaveCredentials: viewModel.saveCredentials,
                onRefreshQR: viewModel.refreshQRCode,
                onSubmitPassword: viewModel.submitPassword
            )
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }

    private var drawerBackdrop: some View {
        Color.black.opacity(0.12)
            .ignoresSafeArea()
            .onTapGesture {
                withAnimation(.snappy(duration: 0.25)) {
                    viewModel.isSidebarPresented = false
                }
            }
    }

    private var channelDrawer: some View {
        HStack(alignment: .top, spacing: 0) {
            ChannelsManagementView(
                viewModel: viewModel.channelsViewModel,
                onAdd: {
                    viewModel.addChannel()
                },
                onRemove: {
                    viewModel.removeSelectedChannel()
                },
                onSelect: { chatID in
                    viewModel.selectChannel(chatID)
                },
                onClose: {
                    withAnimation(.snappy(duration: 0.25)) {
                        viewModel.isSidebarPresented = false
                    }
                }
            )
            .frame(width: 362, alignment: .topLeading)
            .background(Color.white.opacity(0.72))
            .overlay(
                RoundedRectangle(cornerRadius: 30, style: .continuous)
                    .strokeBorder(Color.white.opacity(0.82), lineWidth: 1)
            )
            .clipShape(RoundedRectangle(cornerRadius: 30, style: .continuous))
            .shadow(color: .black.opacity(0.12), radius: 26, x: 8, y: 18)
            .padding(.leading, 18)
            .padding(.top, 12)

            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }

    @ViewBuilder
    private var unreadColumn: some View {
        FeedListView(
            viewModel: viewModel.feedViewModel,
            selectedPostID: Binding(
                get: { viewModel.selectedUnreadPostID },
                set: { viewModel.selectedUnreadPostID = $0 }
            ),
            onSelectionChange: viewModel.selectUnreadPost,
            onSwipeRight: viewModel.toggleReadState
        )
        .background(
            GeometryReader { proxy in
                Color.clear
                    .preference(key: UnreadColumnWidthKey.self, value: proxy.size.width)
            }
        )
        .onPreferenceChange(UnreadColumnWidthKey.self) { width in
            viewModel.updateUnreadColumnWidth(width)
        }
    }

    @ViewBuilder
    private var detailColumn: some View {
        if let post = viewModel.viewerPresentedPost {
            PostViewerView(
                post: post,
                viewModel: viewModel.viewerViewModel,
                onClose: viewModel.closeViewer
            )
        } else {
            Color.clear
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }
}

private struct UnreadColumnWidthKey: PreferenceKey {
    static let defaultValue: CGFloat = 0

    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
        value = nextValue()
    }
}

private struct TopBarButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .foregroundStyle(.primary)
            .background(
                Circle()
                    .fill(Color.white.opacity(configuration.isPressed ? 0.72 : 0.88))
            )
            .overlay(
                Circle()
                    .strokeBorder(Color.black.opacity(0.05), lineWidth: 1)
            )
            .shadow(color: .black.opacity(configuration.isPressed ? 0.03 : 0.08), radius: 10, x: 0, y: 4)
            .scaleEffect(configuration.isPressed ? 0.97 : 1)
    }
}
