import SwiftUI

struct FeedListView: View {
    @ObservedObject var viewModel: FeedViewModel
    @Binding var selectedPostID: UnreadPostIdentity?
    let onSelectionChange: (UnreadPostIdentity?) -> Void
    let onSwipeRight: (UnreadPost) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            if viewModel.isLoading || viewModel.posts.isEmpty {
                Color.clear
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                header
                ScrollViewReader { proxy in
                    ScrollView {
                        LazyVStack(spacing: 10) {
                            ForEach(viewModel.posts, id: \.id) { post in
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
                            proxy.scrollTo(newValue, anchor: .center)
                        }
                    }
                    .onMoveCommand(perform: moveSelection)
                    .onAppear {
                        if selectedPostID == nil, let firstPost = viewModel.posts.first {
                            selectedPostID = firstPost.id
                            onSelectionChange(firstPost.id)
                        }
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

    private var header: some View {
        HStack(alignment: .top, spacing: 14) {
            VStack(alignment: .leading, spacing: 6) {
                Text(L10n.tr("feed.title"))
                    .font(.system(size: 21, weight: .semibold, design: .rounded))
                Text(L10n.tr("feed.subtitle"))
                    .font(.system(size: 12.5, weight: .semibold, design: .rounded))
                    .foregroundStyle(.primary)
                    .lineLimit(1)
                HStack(spacing: 8) {
                    Text(L10n.tr("feed.allSources"))
                        .font(.caption)
                        .foregroundStyle(.secondary)

                    Text("\(viewModel.posts.count)")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.secondary)
                        .padding(.horizontal, 9)
                        .padding(.vertical, 5)
                        .background(Color.white.opacity(0.88), in: Capsule(style: .continuous))
                        .overlay(
                            Capsule(style: .continuous)
                                .strokeBorder(Color.black.opacity(0.05), lineWidth: 1)
                        )
                }
            }

            Spacer()
        }
    }

    @ViewBuilder
    private func row(_ post: UnreadPost) -> some View {
        let isSelected = selectedPostID == post.id
        let isUnread = viewModel.isUnread(post)
        let parts = cardParts(for: post)

        VStack(alignment: .leading, spacing: 5) {
            Text(parts.title)
                .font(.system(size: 12, weight: isUnread ? .bold : .semibold, design: .rounded))
                .foregroundStyle(.primary)
                .lineLimit(2)
                .multilineTextAlignment(.leading)
                .frame(maxWidth: .infinity, alignment: .leading)

            Text(parts.source)
                .font(.system(size: 10, weight: .regular, design: .rounded))
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .multilineTextAlignment(.leading)

            Text(parts.body)
                .font(.system(size: 12, weight: .regular, design: .rounded))
                .foregroundStyle(.primary)
                .multilineTextAlignment(.leading)
                .lineLimit(3)

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
                .fill(isSelected ? Color(red: 0.88, green: 0.86, blue: 0.82) : Color.clear)
        )
        .overlay(
            Group {
                if isSelected {
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .strokeBorder(Color.black.opacity(0.06), lineWidth: 1)
                }
            }
        )
        .shadow(color: isSelected ? .black.opacity(0.04) : .clear, radius: 7, x: 0, y: 3)
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

    private func cardParts(for post: UnreadPost) -> (title: String, source: String, body: String) {
        let source = post.author?.isEmpty == false ? post.author! : post.channelTitle
        let rawText = post.summary.trimmingCharacters(in: .whitespacesAndNewlines)
        let lines = rawText
            .components(separatedBy: .newlines)
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { $0.isEmpty == false }

        let title = lines.first ?? source
        let body = lines.dropFirst().joined(separator: " ")
        return (
            title: title,
            source: source,
            body: body.isEmpty ? rawText : body
        )
    }

    private func moveSelection(_ direction: MoveCommandDirection) {
        guard viewModel.posts.isEmpty == false else {
            return
        }

        let posts = viewModel.posts
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

}
