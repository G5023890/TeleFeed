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
        VStack(spacing: 10) {
            AppSplitView(
                leadingMinWidth: 240,
                leadingContent: unreadColumn,
                trailingMinWidth: 520,
                trailingContent: detailColumn
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
            .background(sidebarDrawerBackground)
            .overlay(
                RoundedRectangle(cornerRadius: 30, style: .continuous)
                    .strokeBorder(sidebarDrawerStroke, lineWidth: 1)
            )
            .clipShape(RoundedRectangle(cornerRadius: 30, style: .continuous))
            .shadow(color: sidebarDrawerShadow, radius: 26, x: 8, y: 18)
            .padding(.leading, 18)
            .padding(.top, 12)

            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }

    private var sidebarDrawerBackground: some View {
        ZStack {
            if colorScheme == .dark {
                LinearGradient(
                    colors: [
                        Color(red: 0.13, green: 0.14, blue: 0.17).opacity(0.88),
                        Color(red: 0.09, green: 0.10, blue: 0.13).opacity(0.94),
                    ],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )

                LinearGradient(
                    colors: [
                        Color.white.opacity(0.05),
                        Color.black.opacity(0.08),
                    ],
                    startPoint: .top,
                    endPoint: .bottom
                )
                .blendMode(.softLight)
            } else {
                Color.white.opacity(0.76)
            }
        }
    }

    private var sidebarDrawerStroke: Color {
        colorScheme == .dark ? Color.white.opacity(0.10) : Color.white.opacity(0.82)
    }

    private var sidebarDrawerShadow: Color {
        colorScheme == .dark ? Color.black.opacity(0.60) : Color.black.opacity(0.12)
    }

    @ViewBuilder
    private var unreadColumn: some View {
        FeedListView(
            viewModel: viewModel.feedViewModel,
            settings: viewModel.settings,
            selectedPostID: Binding(
                get: { viewModel.selectedUnreadPostID },
                set: { viewModel.selectedUnreadPostID = $0 }
            ),
            onSelectionChange: viewModel.selectUnreadPost,
            onTopVisiblePostChange: viewModel.focusVisiblePost,
            onRefresh: {
                await viewModel.refreshSelectedChannel()
            }
        )
    }

    @ViewBuilder
    private var detailColumn: some View {
        if viewModel.detailPresentation == .reader {
            ReaderView(
                viewModel: viewModel.readerViewModel,
                settings: viewModel.settings,
                onBack: viewModel.closeReader
            )
            .transition(verticalStoryTransition)
        } else if let post = viewModel.viewerPresentedPost {
            PostViewerView(
                post: post,
                viewModel: viewModel.viewerViewModel,
                settings: viewModel.settings,
                onClose: viewModel.closeViewer,
                onOpenReader: { viewModel.openReader(for: post) }
            )
            .transition(verticalStoryTransition)
        } else {
            Color.clear
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .transition(verticalStoryTransition)
        }
    }

    private var verticalStoryTransition: AnyTransition {
        .asymmetric(
            insertion: .move(edge: .top).combined(with: .opacity),
            removal: .move(edge: .bottom).combined(with: .opacity)
        )
    }
}

private struct AppSplitView<Leading: View, Trailing: View>: NSViewControllerRepresentable {
    let leadingMinWidth: CGFloat
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
        return controller
    }

    func updateNSViewController(_ nsViewController: SplitViewController<Leading, Trailing>, context: Context) {
        nsViewController.leadingMinWidth = leadingMinWidth
        nsViewController.trailingMinWidth = trailingMinWidth
        nsViewController.leadingHostingController.rootView = leadingContent
        nsViewController.trailingHostingController.rootView = trailingContent
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

    private var didApplyInitialWidth = false
    private let fixedLeadingWidth: CGFloat = 420

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
        enforceFixedLeadingWidthIfNeeded()
    }

    func applyDesiredWidthIfNeeded() {
        guard view.bounds.width > 0 else {
            return
        }

        guard didApplyInitialWidth == false else {
            return
        }

        let maxLeadingWidth = max(leadingMinWidth, view.bounds.width - trailingMinWidth - splitView.dividerThickness)
        let clampedWidth = max(leadingMinWidth, min(fixedLeadingWidth, maxLeadingWidth))
        splitView.setPosition(clampedWidth, ofDividerAt: 0)
        didApplyInitialWidth = true
    }

    private func enforceFixedLeadingWidthIfNeeded() {
        guard view.bounds.width > 0, didApplyInitialWidth else {
            return
        }

        let maxLeadingWidth = max(leadingMinWidth, view.bounds.width - trailingMinWidth - splitView.dividerThickness)
        let clampedWidth = max(leadingMinWidth, min(fixedLeadingWidth, maxLeadingWidth))
        let currentWidth = splitView.subviews.first?.frame.width ?? clampedWidth
        guard abs(currentWidth - clampedWidth) > 1 else {
            return
        }

        splitView.setPosition(clampedWidth, ofDividerAt: 0)
    }
    
    override func splitView(_ splitView: NSSplitView, constrainSplitPosition proposedPosition: CGFloat, ofSubviewAt dividerIndex: Int) -> CGFloat {
        let maxLeadingWidth = max(leadingMinWidth, splitView.bounds.width - trailingMinWidth - splitView.dividerThickness)
        return max(leadingMinWidth, min(fixedLeadingWidth, maxLeadingWidth))
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
