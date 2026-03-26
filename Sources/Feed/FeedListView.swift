import SwiftUI

struct FeedListView: View {
    @ObservedObject var viewModel: FeedViewModel
    @Binding var selectedPostID: UnreadPostIdentity?
    let onSelectionChange: (UnreadPostIdentity?) -> Void
    let onSwipeRight: (UnreadPost) -> Void
    @Environment(\.colorScheme) private var colorScheme

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
                ScrollViewReader { proxy in
                    ScrollView {
                        LazyVStack(spacing: 10) {
                            ForEach(visiblePosts, id: \.id) { post in
                                row(post)
                                    .id(post.id)
                                    .contentShape(Rectangle())
                                    .onTapGesture {
                                        selectedPostID = post.id
                                        onSelectionChange(post.id)
                                    }
                                    .simultaneousGesture(swipeRightGesture(for: post))
                            }
                        }
                        .padding(.vertical, 2)
                    }
                    .focusable()
                    .focusEffectDisabled()
                    .scrollIndicators(.hidden)
                    .background(Color.clear)
                    .onChange(of: selectedPostID) { _, newValue in
                        onSelectionChange(newValue)
                        guard let newValue else {
                            return
                        }
                        withAnimation(.snappy(duration: 0.2)) {
                            proxy.scrollTo(newValue, anchor: .top)
                        }
                    }
                    .onMoveCommand(perform: moveSelection)
                    .onAppear {
                        syncSelection(in: proxy, visiblePosts: visiblePosts)
                    }
                    .onChange(of: viewModel.displayMode) { _, _ in
                        syncSelection(in: proxy, visiblePosts: viewModel.visiblePosts)
                    }
                    .onChange(of: viewModel.readPostIDs) { _, _ in
                        syncSelection(in: proxy, visiblePosts: viewModel.visiblePosts)
                    }
                }
            }

            if let errorMessage = viewModel.errorMessage {
                Text(errorMessage)
                    .font(.callout)
                    .foregroundStyle(.red)
            }
        }
        .padding(8)
    }

    private var emptyState: some View {
        VStack(alignment: .leading, spacing: 8) {
            header
            Text(viewModel.displayMode == .unread ? L10n.tr("feed.emptyUnread") : L10n.tr("feed.empty"))
                .font(.system(size: 13, weight: .regular, design: .rounded))
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
                    .font(.system(size: 19, weight: .semibold, design: .rounded))
                filterControl
            }

            Spacer()
        }
    }

    private var filterControl: some View {
        let unreadCount = viewModel.unreadCount
        let segmentHeight: CGFloat = 24
        let controlWidth: CGFloat = 188
        let segmentWidth = (controlWidth - 1) / 2

        return HStack(spacing: 0) {
            filterSegment(
                title: L10n.tr("feed.filterAll"),
                isSelected: viewModel.displayMode == .all,
                width: segmentWidth,
                height: segmentHeight
            ) {
                withAnimation(.snappy(duration: 0.15)) {
                    viewModel.displayMode = .all
                }
            }

            Rectangle()
                .fill(AppTheme.separatorColor(for: colorScheme).opacity(0.75))
                .frame(width: 1)

            filterSegment(
                title: L10n.tr("feed.filterUnread"),
                badge: unreadCount,
                isSelected: viewModel.displayMode == .unread,
                width: segmentWidth,
                height: segmentHeight
            ) {
                withAnimation(.snappy(duration: 0.15)) {
                    viewModel.displayMode = .unread
                }
            }
        }
        .padding(3)
        .fixedSize()
        .background(AppTheme.toolbarPillFill(for: colorScheme), in: Capsule(style: .continuous))
        .overlay(
            Capsule(style: .continuous)
                .strokeBorder(AppTheme.toolbarPillStroke(for: colorScheme), lineWidth: 1)
        )
    }

    private func filterSegment(
        title: String,
        badge: Int? = nil,
        isSelected: Bool,
        width: CGFloat,
        height: CGFloat,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            HStack(spacing: 8) {
                Text(title)
                    .font(.system(size: 12.5, weight: .semibold, design: .rounded))
                    .lineLimit(1)
                    .minimumScaleFactor(0.85)

                if let badge {
                    Text(badgeLabel(for: badge))
                        .font(.system(size: 11, weight: .semibold, design: .rounded))
                        .foregroundStyle(.secondary)
                        .padding(.horizontal, 7)
                        .padding(.vertical, 3)
                        .background(AppTheme.chipFill(for: colorScheme), in: Capsule(style: .continuous))
                        .overlay(
                            Capsule(style: .continuous)
                                .strokeBorder(AppTheme.chipStroke(for: colorScheme), lineWidth: 1)
                        )
                }
            }
            .frame(width: width, height: height)
            .padding(.horizontal, 8)
            .foregroundStyle(isSelected ? .primary : .secondary)
            .background(
                Capsule(style: .continuous)
                    .fill(isSelected ? AppTheme.surfaceFill(for: colorScheme) : Color.clear)
            )
        }
        .buttonStyle(.plain)
        .contentShape(Rectangle())
    }

    private func badgeLabel(for count: Int) -> String {
        count > 99 ? "99+" : "\(count)"
    }

    @ViewBuilder
    private func row(_ post: UnreadPost) -> some View {
        let isSelected = selectedPostID == post.id
        let isUnread = viewModel.isUnread(post)
        let parts = cardParts(for: post)

        VStack(alignment: .leading, spacing: parts.body == nil ? 4 : 5) {
            Text(parts.title)
                .font(.system(size: 12, weight: isUnread ? .bold : .semibold, design: .rounded))
                .foregroundStyle(isUnread ? .primary : .secondary)
                .lineLimit(2)
                .multilineTextAlignment(.leading)
                .frame(maxWidth: .infinity, alignment: .leading)

            Text(parts.source)
                .font(.system(size: 10, weight: .regular, design: .rounded))
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .multilineTextAlignment(.leading)

            if let body = parts.body {
                Text(body)
                    .font(.system(size: 12, weight: .regular, design: .rounded))
                    .foregroundStyle(.primary)
                    .multilineTextAlignment(.leading)
                    .lineLimit(3)
            }

            Text(post.date.formatted(date: .abbreviated, time: .shortened))
                .font(.system(size: 10, weight: .regular, design: .rounded))
                .foregroundStyle(.secondary)
                .padding(.top, 1)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 7)
        .padding(.vertical, 7)
        .background(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(AppTheme.rowFill(for: colorScheme, selected: isSelected, unread: isUnread))
        )
        .overlay(
            Group {
                if isSelected || colorScheme == .dark {
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .strokeBorder(AppTheme.rowStroke(for: colorScheme, selected: isSelected, unread: isUnread), lineWidth: 1)
                }
            }
        )
        .shadow(color: AppTheme.rowShadow(for: colorScheme, selected: isSelected, unread: isUnread), radius: 7, x: 0, y: 3)
    }

    private func swipeRightGesture(for post: UnreadPost) -> some Gesture {
        DragGesture(minimumDistance: 18, coordinateSpace: .local)
            .onEnded { value in
                guard value.translation.width > 60 else {
                    return
                }
                guard abs(value.translation.width) > abs(value.translation.height) else {
                    return
                }
                onSwipeRight(post)
            }
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

    private func moveSelection(_ direction: MoveCommandDirection) {
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

        selectedPostID = posts[nextIndex].id
    }

    private func syncSelection(in proxy: ScrollViewProxy, visiblePosts: [UnreadPost]) {
        guard visiblePosts.isEmpty == false else {
            selectedPostID = nil
            onSelectionChange(nil)
            return
        }

        if let selectedPostID,
           visiblePosts.contains(where: { $0.id == selectedPostID }) {
            DispatchQueue.main.async {
                proxy.scrollTo(selectedPostID, anchor: .top)
            }
            return
        }

        if let preferredPost = preferredInitialPostID(in: visiblePosts) {
            selectedPostID = preferredPost.id
            onSelectionChange(preferredPost.id)
            DispatchQueue.main.async {
                proxy.scrollTo(preferredPost.id, anchor: .top)
            }
        }
    }

    private func preferredInitialPostID(in posts: [UnreadPost]) -> UnreadPost? {
        if let preferredRSSPost = posts.reversed().first(where: { $0.sourceKind == .rss && viewModel.isUnread($0) }) {
            return preferredRSSPost
        }
        if let firstUnreadPost = posts.first(where: { viewModel.isUnread($0) }) {
            return firstUnreadPost
        }
        return posts.first
    }

}
