import SwiftUI
import AppKit

struct MainContentView: View {
    @ObservedObject var viewModel: MainViewModel

    var body: some View {
        GeometryReader { proxy in
            let sidebarWidth = min(max(proxy.size.width * 0.34, 300), 420)

            ZStack(alignment: .leading) {
                LinearGradient(
                    colors: [
                        Color(nsColor: .windowBackgroundColor),
                        Color.blue.opacity(0.15),
                        Color.cyan.opacity(0.12),
                    ],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
                .ignoresSafeArea()

                detailContent

                if canShowSidebar, viewModel.isSidebarPresented {
                    Color.black.opacity(0.22)
                        .ignoresSafeArea()
                        .transition(.opacity)
                        .onTapGesture {
                            closeSidebar()
                        }

                    sidebarDrawer(width: sidebarWidth)
                        .padding(.leading, 12)
                        .padding(.vertical, 12)
                        .transition(.move(edge: .leading).combined(with: .opacity))
                        .zIndex(1)
                }
            }
            .animation(.spring(response: 0.34, dampingFraction: 0.88), value: viewModel.isSidebarPresented)
            .toolbar {
                ToolbarItem(placement: .navigation) {
                    Button(action: toggleSidebar) {
                        Image(systemName: "sidebar.leading")
                    }
                    .help(canShowSidebar ? L10n.tr("sidebar.channels") : L10n.tr("sidebar.empty"))
                    .disabled(canShowSidebar == false)
                    .opacity(canShowSidebar ? 1 : 0.4)
                }

                ToolbarItemGroup(placement: .automatic) {
                    Text(viewModel.connectionLabel)
                        .font(.caption)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 6)
                        .background(.thinMaterial, in: Capsule())

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

    private var canShowSidebar: Bool {
        if case .ready = viewModel.authViewModel.state {
            return true
        }
        return false
    }

    @ViewBuilder
    private var detailContent: some View {
        Group {
            if case .ready = viewModel.authViewModel.state {
                if let channel = viewModel.channelsViewModel.selectedChannel {
                    if let post = viewModel.viewerPresentedPost {
                        PostViewerView(
                            post: post,
                            viewModel: viewModel.viewerViewModel,
                            onClose: viewModel.closeViewer
                        )
                    } else {
                        FeedListView(
                            channel: channel,
                            viewModel: viewModel.feedViewModel,
                            onRefresh: {
                                Task {
                                    await viewModel.refreshSelectedChannel()
                                }
                            },
                            onOpen: viewModel.openPost
                        )
                    }
                } else {
                    ContentUnavailableView(L10n.tr("sidebar.empty"), systemImage: "dot.radiowaves.left.and.right")
                }
            } else {
                AuthView(
                    viewModel: viewModel.authViewModel,
                    onSaveCredentials: viewModel.saveCredentials,
                    onRefreshQR: viewModel.refreshQRCode,
                    onSubmitPassword: viewModel.submitPassword
                )
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(.clear)
    }

    @ViewBuilder
    private func sidebarDrawer(width: CGFloat) -> some View {
        ChannelsManagementView(
            viewModel: viewModel.channelsViewModel,
            onAdd: viewModel.addChannel,
            onRemove: viewModel.removeSelectedChannel,
            onSelect: { chatID in
                viewModel.selectChannel(chatID)
                if chatID != nil {
                    closeSidebar()
                }
            },
            onClose: {
                closeSidebar()
            }
        )
        .frame(width: width, alignment: .leading)
        .shadow(color: .black.opacity(0.18), radius: 30, x: 0, y: 18)
    }

    private func toggleSidebar() {
        guard canShowSidebar else {
            return
        }

        withAnimation {
            viewModel.toggleSidebar()
        }
    }

    private func closeSidebar() {
        guard viewModel.isSidebarPresented else {
            return
        }

        _ = withAnimation {
            viewModel.closeSidebar()
        }
    }
}
