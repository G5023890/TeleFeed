import SwiftUI
import AppKit

struct MainContentView: View {
    @ObservedObject var viewModel: MainViewModel
    @Environment(\.colorScheme) private var colorScheme

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
        LinearGradient(
            colors: AppTheme.windowGradientColors(for: colorScheme),
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
        .ignoresSafeArea()
    }

    @ViewBuilder
    private var content: some View {
        if case .ready = viewModel.authViewModel.state {
            VStack(spacing: 10) {
                AppSplitView(
                    initialLeadingWidth: viewModel.unreadColumnWidth,
                    leadingMinWidth: 240,
                    onLeadingWidthChange: viewModel.updateUnreadColumnWidth,
                    leadingContent: unreadColumn,
                    trailingMinWidth: 520,
                    trailingContent: detailColumn
                )
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
                rssViewModel: viewModel.rssFeedsViewModel,
                onAdd: {
                    viewModel.addChannel()
                },
                onRemove: {
                    viewModel.removeSelectedChannel()
                },
                onSelect: { chatID in
                    viewModel.selectChannel(chatID)
                },
                onAddRSS: {
                    viewModel.addRSSFeed()
                },
                onRemoveRSS: {
                    viewModel.removeSelectedRSSFeed()
                },
                onSelectRSS: { feedID in
                    viewModel.selectRSSFeed(feedID)
                },
                onClose: {
                    withAnimation(.snappy(duration: 0.25)) {
                        viewModel.isSidebarPresented = false
                    }
                }
            )
            .frame(width: 362, alignment: .topLeading)
            .background(AppTheme.drawerFill(for: colorScheme))
            .overlay(
                RoundedRectangle(cornerRadius: 30, style: .continuous)
                    .strokeBorder(AppTheme.drawerStroke(for: colorScheme), lineWidth: 1)
            )
            .clipShape(RoundedRectangle(cornerRadius: 30, style: .continuous))
            .shadow(color: AppTheme.drawerShadow(for: colorScheme), radius: 26, x: 8, y: 18)
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
    }

    @ViewBuilder
    private var detailColumn: some View {
        if viewModel.detailPresentation == .reader {
            ReaderView(
                viewModel: viewModel.readerViewModel,
                onBack: viewModel.closeReader
            )
        } else if let post = viewModel.viewerPresentedPost {
            PostViewerView(
                post: post,
                viewModel: viewModel.viewerViewModel,
                onClose: viewModel.closeViewer,
                onOpenReader: { viewModel.openReader(for: post) }
            )
        } else {
            Color.clear
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }
}

private struct AppSplitView<Leading: View, Trailing: View>: NSViewControllerRepresentable {
    let initialLeadingWidth: CGFloat
    let leadingMinWidth: CGFloat
    let onLeadingWidthChange: (CGFloat) -> Void
    let leadingContent: Leading
    let trailingMinWidth: CGFloat
    let trailingContent: Trailing

    func makeNSViewController(context: Context) -> SplitViewController<Leading, Trailing> {
        let controller = SplitViewController(
            leadingContent: leadingContent,
            trailingContent: trailingContent
        )
        controller.leadingMinWidth = leadingMinWidth
        controller.trailingMinWidth = trailingMinWidth
        controller.onLeadingWidthChange = { width in
            let normalized = max(leadingMinWidth, width.rounded())
            onLeadingWidthChange(normalized)
        }
        controller.desiredLeadingWidth = initialLeadingWidth
        return controller
    }

    func updateNSViewController(_ nsViewController: SplitViewController<Leading, Trailing>, context: Context) {
        nsViewController.leadingMinWidth = leadingMinWidth
        nsViewController.trailingMinWidth = trailingMinWidth
        nsViewController.leadingHostingController.rootView = leadingContent
        nsViewController.trailingHostingController.rootView = trailingContent
        nsViewController.updateDesiredLeadingWidth(initialLeadingWidth)
        nsViewController.applyDesiredWidthIfNeeded()
    }
}

    private final class SplitViewController<Leading: View, Trailing: View>: NSSplitViewController {
    let leadingHostingController: NSHostingController<Leading>
    let trailingHostingController: NSHostingController<Trailing>

    var leadingMinWidth: CGFloat = 240 {
        didSet {
            splitViewItems.first?.minimumThickness = leadingMinWidth
        }
    }

    var trailingMinWidth: CGFloat = 520 {
        didSet {
            splitViewItems.last?.minimumThickness = trailingMinWidth
        }
    }

    var desiredLeadingWidth: CGFloat = 300
    var onLeadingWidthChange: ((CGFloat) -> Void)?
    private var didApplyInitialWidth = false
    private var isAcceptingWidthPersistence = false
    private var lastReportedLeadingWidth: CGFloat?

    init(leadingContent: Leading, trailingContent: Trailing) {
        self.leadingHostingController = NSHostingController(rootView: leadingContent)
        self.trailingHostingController = NSHostingController(rootView: trailingContent)
        super.init(nibName: nil, bundle: nil)
        splitView.isVertical = true
        splitView.dividerStyle = .thin
        splitView.delegate = self
        addSplitViewItem(NSSplitViewItem(viewController: leadingHostingController))
        addSplitViewItem(NSSplitViewItem(viewController: trailingHostingController))
        splitViewItems.first?.canCollapse = false
        splitViewItems.last?.canCollapse = false
        splitViewItems.first?.minimumThickness = leadingMinWidth
        splitViewItems.last?.minimumThickness = trailingMinWidth
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func viewDidAppear() {
        super.viewDidAppear()
        applyDesiredWidthIfNeeded()
    }

    override func viewDidLayout() {
        super.viewDidLayout()
        applyDesiredWidthIfNeeded()
    }

    func applyDesiredWidthIfNeeded() {
        guard view.bounds.width > 0 else {
            return
        }

        guard didApplyInitialWidth == false else {
            return
        }

        let maxLeadingWidth = max(leadingMinWidth, view.bounds.width - trailingMinWidth - splitView.dividerThickness)
        let clampedWidth = max(leadingMinWidth, min(desiredLeadingWidth, maxLeadingWidth))
        splitView.setPosition(clampedWidth, ofDividerAt: 0)
        didApplyInitialWidth = true
        if isAcceptingWidthPersistence == false {
            DispatchQueue.main.async { [weak self] in
                self?.isAcceptingWidthPersistence = true
            }
        }
    }

    func updateDesiredLeadingWidth(_ width: CGFloat) {
        guard didApplyInitialWidth == false else {
            return
        }

        desiredLeadingWidth = width
    }

    override func splitViewDidResizeSubviews(_ notification: Notification) {
        guard didApplyInitialWidth else {
            return
        }

        reportLeadingWidthIfNeeded(force: false)
    }

    @objc func splitViewDidEndLiveResize(_ notification: Notification) {
        guard didApplyInitialWidth else {
            return
        }

        reportLeadingWidthIfNeeded(force: true)
    }

    private func reportLeadingWidthIfNeeded(force: Bool) {
        guard isAcceptingWidthPersistence || force == false else {
            return
        }

        view.layoutSubtreeIfNeeded()
        let width = splitView.subviews.first?.frame.width ?? desiredLeadingWidth
        let normalized = max(leadingMinWidth, width.rounded())
        guard force || lastReportedLeadingWidth.map({ abs($0 - normalized) > 1 }) ?? true else {
            return
        }

        lastReportedLeadingWidth = normalized
        onLeadingWidthChange?(normalized)
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
