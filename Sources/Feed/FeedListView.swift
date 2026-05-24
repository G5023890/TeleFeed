import SwiftUI

struct FeedListView: View {
    @ObservedObject var viewModel: FeedViewModel
    let settings: AppSettings
    @Binding var selectedPostID: UnreadPostIdentity?
    let onSelectionChange: (UnreadPostIdentity?) -> Void
    let onTopVisiblePostChange: (UnreadPost) -> Void
    let onRefresh: () async -> Void
    @Environment(\.colorScheme) private var colorScheme
    @State private var previousVisiblePosts: [UnreadPost] = []
    @State private var suppressSelectionCallback = false
    @State private var userHasScrolled = false

    var body: some View {
        let visiblePosts = viewModel.visiblePosts

        VStack(alignment: .leading, spacing: 12) {
            if viewModel.isLoading {
                Color.clear
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if visiblePosts.isEmpty {
                emptyState
            } else {
                header
                GeometryReader { viewportProxy in
                    ScrollViewReader { proxy in
                        ScrollView {
                            LazyVStack(spacing: 10) {
                                ForEach(visiblePosts, id: \.id) { post in
                                    row(post)
                                        .id(post.id)
                                        .contentShape(Rectangle())
                                        .background(
                                            visibilityReader(
                                                for: post,
                                                viewport: CGRect(origin: .zero, size: viewportProxy.size)
                                            )
                                        )
                                        .onTapGesture {
                                            selectedPostID = post.id
                                            onSelectionChange(post.id)
                                        }
                                }
                            }
                            .padding(.vertical, 2)
                        }
                        .coordinateSpace(name: "feedListScroll")
                        .refreshable {
                            await onRefresh()
                        }
                        .focusable()
                        .focusEffectDisabled()
                        .scrollIndicators(.hidden)
                        .background(Color.clear)
                        .simultaneousGesture(
                            DragGesture(minimumDistance: 8)
                                .onChanged { _ in
                                    userHasScrolled = true
                                }
                        )
                        .onScrollPhaseChange { _, newPhase in
                            switch newPhase {
                            case .tracking, .interacting, .decelerating:
                                userHasScrolled = true
                            default:
                                break
                            }
                        }
                        .onMoveCommand { direction in
                            moveSelection(direction, proxy: proxy)
                        }
                        .onAppear {
                            syncSelection(in: proxy, visiblePosts: visiblePosts)
                        }
                        .onChange(of: viewModel.viewedPostID) { _, _ in
                            syncSelection(in: proxy, visiblePosts: viewModel.visiblePosts)
                        }
                        .onPreferenceChange(VisibleFeedRowsPreferenceKey.self) { visibleRows in
                            handleVisibleRowsChange(visibleRows)
                        }
                    }
                }
            }

            if let errorMessage = viewModel.errorMessage {
                Text(errorMessage)
                    .font(.system(size: CGFloat(settings.typography.feedBody), weight: .regular, design: .rounded))
                    .foregroundStyle(.red)
            }
        }
        .padding(8)
    }

    private var emptyState: some View {
        VStack(alignment: .leading, spacing: 8) {
            header
            Text(L10n.tr("feed.empty"))
                .font(.system(size: CGFloat(settings.typography.feedBody), weight: .regular, design: .rounded))
                .foregroundStyle(.secondary)
                .padding(.top, 8)
            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }

    private var header: some View {
        HStack(alignment: .top, spacing: 10) {
            VStack(alignment: .leading, spacing: 8) {
                Text(L10n.tr("feed.title"))
                    .font(.system(size: CGFloat(settings.typography.feedHeaderTitle), weight: .semibold, design: .rounded))
                newerCounter
            }

            Spacer()
        }
    }

    private var newerCounter: some View {
        Text(badgeLabel(for: viewModel.newerThanViewedCount))
            .font(.system(size: CGFloat(settings.typography.feedFilter), weight: .semibold, design: .rounded))
            .foregroundStyle(.primary)
            .frame(minWidth: 56, minHeight: 24)
            .padding(.horizontal, 12)
            .padding(.vertical, 3)
            .background(AppTheme.toolbarPillFill(for: colorScheme), in: Capsule(style: .continuous))
            .overlay(
                Capsule(style: .continuous)
                    .strokeBorder(AppTheme.toolbarPillStroke(for: colorScheme), lineWidth: 1)
            )
    }

    private func badgeLabel(for count: Int) -> String {
        count > 99 ? "99+" : "\(count)"
    }

    private func visibilityReader(for post: UnreadPost, viewport: CGRect) -> some View {
        GeometryReader { rowProxy in
            let rowFrame = rowProxy.frame(in: .named("feedListScroll"))
            let isVisible = rowFrame.intersects(viewport) && rowFrame.height > 0
            Color.clear.preference(
                key: VisibleFeedRowsPreferenceKey.self,
                value: isVisible ? [VisibleFeedRow(id: post.id, minY: rowFrame.minY)] : []
            )
        }
    }

    private func handleVisibleRowsChange(_ visibleRows: [VisibleFeedRow]) {
        guard userHasScrolled,
              let focusedVisibleID = topVisiblePostID(in: visibleRows),
              let post = viewModel.visiblePosts.first(where: { $0.id == focusedVisibleID })
        else {
            return
        }

        onTopVisiblePostChange(post)
    }

    private func topVisiblePostID(in visibleRows: [VisibleFeedRow]) -> UnreadPostIdentity? {
        let sortedRows = visibleRows.sorted { lhs, rhs in
            lhs.minY < rhs.minY
        }
        return sortedRows.first(where: { $0.minY >= 0 })?.id ?? sortedRows.first?.id
    }

    @ViewBuilder
    private func row(_ post: UnreadPost) -> some View {
        let isSelected = selectedPostID == post.id
        let parts = cardParts(for: post)

        VStack(alignment: .leading, spacing: parts.body == nil ? 4 : 5) {
            Text(parts.title)
                .font(.system(size: CGFloat(settings.typography.feedTitle), weight: .semibold, design: .rounded))
                .foregroundStyle(.primary)
                .lineLimit(2)
                .multilineTextAlignment(.leading)
                .frame(maxWidth: .infinity, alignment: .leading)

            Text(parts.source)
                .font(.system(size: CGFloat(settings.typography.feedSource), weight: .regular, design: .rounded))
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .multilineTextAlignment(.leading)

            if let body = parts.body {
                Text(body)
                    .font(.system(size: CGFloat(settings.typography.feedBody), weight: .regular, design: .rounded))
                    .foregroundStyle(.primary)
                    .multilineTextAlignment(.leading)
                    .lineLimit(3)
            }

            Text(post.date.formatted(date: .abbreviated, time: .shortened))
                .font(.system(size: CGFloat(settings.typography.feedDate), weight: .regular, design: .rounded))
                .foregroundStyle(.secondary)
                .padding(.top, 1)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 7)
        .padding(.vertical, 7)
        .background(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(AppTheme.rowFill(for: colorScheme, selected: isSelected, unread: false))
        )
        .overlay(
            Group {
                if isSelected || colorScheme == .dark {
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .strokeBorder(AppTheme.rowStroke(for: colorScheme, selected: isSelected, unread: false), lineWidth: 1)
                }
            }
        )
        .shadow(color: AppTheme.rowShadow(for: colorScheme, selected: isSelected, unread: false), radius: 7, x: 0, y: 3)
    }

    private func cardParts(for post: UnreadPost) -> (title: String, source: String, body: String?) {
        let source = post.author?.isEmpty == false ? post.author! : post.channelTitle
        let rawText = post.summary.trimmingCharacters(in: .whitespacesAndNewlines)
        let lines = rawText
            .components(separatedBy: .newlines)
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { $0.isEmpty == false }

        let title = lines.first ?? source
        let bodyText = lines.dropFirst().joined(separator: " ")
        let normalizedTitle = title.trimmingCharacters(in: .whitespacesAndNewlines)
        let normalizedBody = bodyText.trimmingCharacters(in: .whitespacesAndNewlines)
        let body: String?
        if normalizedBody.isEmpty {
            body = nil
        } else if normalizedBody.caseInsensitiveCompare(normalizedTitle) == .orderedSame {
            body = nil
        } else {
            body = bodyText
        }
        return (
            title: title,
            source: source,
            body: body
        )
    }

    private func moveSelection(_ direction: MoveCommandDirection, proxy: ScrollViewProxy) {
        let posts = viewModel.visiblePosts
        guard posts.isEmpty == false else {
            return
        }

        let currentIndex = selectedPostID.flatMap { id in
            posts.firstIndex(where: { $0.id == id })
        }

        let nextIndex: Int?
        switch direction {
        case .down:
            nextIndex = min((currentIndex ?? -1) + 1, posts.count - 1)
        case .up:
            nextIndex = max((currentIndex ?? posts.count) - 1, 0)
        default:
            return
        }

        guard let nextIndex else {
            return
        }

        let nextPostID = posts[nextIndex].id
        selectedPostID = nextPostID
        onSelectionChange(nextPostID)

        DispatchQueue.main.async {
            withAnimation(.snappy(duration: 0.2)) {
                proxy.scrollTo(nextPostID, anchor: .top)
            }
        }
    }

    private func syncSelection(in proxy: ScrollViewProxy, visiblePosts: [UnreadPost]) {
        guard visiblePosts.isEmpty == false else {
            updateSelectedPostID(nil, notifySelectionChange: true)
            previousVisiblePosts = visiblePosts
            return
        }

        if let currentSelectedPostID = selectedPostID,
           visiblePosts.contains(where: { $0.id == currentSelectedPostID }) {
            scrollToPost(currentSelectedPostID, in: proxy)
            previousVisiblePosts = visiblePosts
            return
        }

        if let currentSelectedPostID = selectedPostID,
           let previousIndex = previousVisiblePosts.firstIndex(where: { $0.id == currentSelectedPostID }) {
            let fallbackIndex = min(previousIndex, visiblePosts.count - 1)
            let fallbackPost = visiblePosts[fallbackIndex]
            updateSelectedPostID(fallbackPost.id, notifySelectionChange: false)
            scrollToPost(fallbackPost.id, in: proxy)
            previousVisiblePosts = visiblePosts
            return
        }

        if let preferredPost = preferredInitialPostID(in: visiblePosts) {
            updateSelectedPostID(preferredPost.id, notifySelectionChange: false)
            scrollToPost(preferredPost.id, in: proxy)
        }

        previousVisiblePosts = visiblePosts
    }

    private func updateSelectedPostID(_ postID: UnreadPostIdentity?, notifySelectionChange: Bool) {
        if notifySelectionChange == false {
            suppressSelectionCallback = true
        }
        selectedPostID = postID
        if notifySelectionChange == false {
            DispatchQueue.main.async {
                suppressSelectionCallback = false
            }
        }
    }

    private func preferredInitialPostID(in posts: [UnreadPost]) -> UnreadPost? {
        viewModel.viewedPostID.flatMap { viewedID in
            posts.first(where: { $0.id == viewedID })
        } ?? posts.last
    }

    private func scrollToPost(_ postID: UnreadPostIdentity, in proxy: ScrollViewProxy) {
        userHasScrolled = false
        DispatchQueue.main.async {
            withAnimation(.snappy(duration: 0.2)) {
                proxy.scrollTo(postID, anchor: .top)
            }
        }
    }

}

private struct VisibleFeedRow: Equatable {
    let id: UnreadPostIdentity
    let minY: CGFloat
}

private struct VisibleFeedRowsPreferenceKey: PreferenceKey {
    static let defaultValue: [VisibleFeedRow] = []

    static func reduce(value: inout [VisibleFeedRow], nextValue: () -> [VisibleFeedRow]) {
        value.append(contentsOf: nextValue())
    }
}
