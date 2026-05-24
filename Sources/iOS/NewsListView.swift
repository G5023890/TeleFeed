import SwiftUI

struct NewsListView: View {
    @ObservedObject var viewModel: IOSNewsFlowViewModel
    @Environment(\.colorScheme) private var colorScheme
    @State private var visiblePostIDs = Set<UnreadPostIdentity>()
    @State private var userHasScrolled = false
    @State private var focusedPostID: UnreadPostIdentity?

    var body: some View {
        ZStack {
            IOSGlassBackground()

            if viewModel.filteredPosts.isEmpty {
                emptyState
            } else {
                GeometryReader { viewportProxy in
                    ScrollViewReader { scrollProxy in
                        ScrollView {
                            LazyVStack(spacing: 12) {
                                ForEach(viewModel.filteredPosts) { post in
                                    Button {
                                        viewModel.open(post)
                                    } label: {
                                        NewsRowView(post: post)
                                    }
                                    .buttonStyle(.plain)
                                    .id(post.id)
                                    .background(
                                        visibilityReader(
                                            for: post,
                                            viewport: CGRect(origin: .zero, size: viewportProxy.size)
                                        )
                                    )
                                }
                            }
                            .padding(.horizontal, 16)
                            .padding(.vertical, 18)
                        }
                        .coordinateSpace(name: "newsListScroll")
                        .scrollIndicators(.hidden)
                        .simultaneousGesture(
                            DragGesture(minimumDistance: 8)
                                .onChanged { _ in
                                    userHasScrolled = true
                                }
                        )
                        .refreshable {
                            await viewModel.refreshAllSources()
                        }
                        .onAppear {
                            focusPreferredPost(in: scrollProxy, force: true)
                        }
                        .onChange(of: viewModel.filteredPosts.map(\.id)) { _, _ in
                            focusPreferredPost(in: scrollProxy, force: true)
                        }
                        .onChange(of: viewModel.focusedPostID) { _, _ in
                            focusPreferredPost(in: scrollProxy)
                        }
                        .onPreferenceChange(VisibleNewsRowsPreferenceKey.self) { visibleRows in
                            handleVisibleRowsChange(visibleRows)
                        }
                    }
                }
            }

            if viewModel.isSourcesDrawerPresented {
                Color.black.opacity(colorScheme == .dark ? 0.30 : 0.16)
                    .ignoresSafeArea()
                    .onTapGesture {
                        viewModel.dismissSourcesDrawer()
                    }

                HStack(alignment: .top) {
                    NewsSourcesDrawerView(viewModel: viewModel)
                    Spacer(minLength: 0)
                }
                .transition(.move(edge: .leading).combined(with: .opacity))
                .zIndex(2)
            }
        }
        .animation(.snappy(duration: 0.25), value: viewModel.isSourcesDrawerPresented)
        .navigationTitle("")
        .navigationBarTitleDisplayMode(.inline)
        .task {
            if viewModel.filteredPosts.isEmpty {
                await viewModel.refreshAllSources()
            }
        }
        .toolbar {
            ToolbarItem(placement: .topBarLeading) {
                Button {
                    viewModel.presentSourcesDrawer()
                } label: {
                    Image(systemName: "slider.horizontal.3")
                }
                .buttonStyle(.glass)
            }

            ToolbarItem(placement: .topBarTrailing) {
                Text(badgeLabel(for: viewModel.feedViewModel.newerThanViewedCount))
                    .font(.headline.weight(.bold))
                    .frame(minWidth: 52, minHeight: 42)
                    .background(.thinMaterial, in: Capsule(style: .continuous))
            }
        }
    }

    private func visibilityReader(for post: UnreadPost, viewport: CGRect) -> some View {
        GeometryReader { rowProxy in
            let rowFrame = rowProxy.frame(in: .named("newsListScroll"))
            let isVisible = rowFrame.intersects(viewport) && rowFrame.height > 0
            Color.clear.preference(
                key: VisibleNewsRowsPreferenceKey.self,
                value: isVisible ? [VisibleNewsRow(id: post.id, minY: rowFrame.minY)] : []
            )
        }
    }

    private func handleVisibleRowsChange(_ visibleRows: [VisibleNewsRow]) {
        let newVisiblePostIDs = Set(visibleRows.map(\.id))
        if userHasScrolled,
           let focusedVisibleID = topVisiblePostID(in: visibleRows),
           let post = viewModel.post(for: focusedVisibleID) {
            viewModel.markPostAsViewedFromListScroll(post)
        }
        visiblePostIDs = newVisiblePostIDs
    }

    private func focusPreferredPost(in proxy: ScrollViewProxy, force: Bool = false) {
        let preferredPost = viewModel.focusedPostID.flatMap { focusedID in
            viewModel.filteredPosts.first(where: { $0.id == focusedID })
        }
            ?? (viewModel.hasReadingAnchor ? nil : viewModel.filteredPosts.last)
        guard let preferredPostID = preferredPost?.id,
              force || focusedPostID != preferredPostID
        else {
            return
        }

        userHasScrolled = false
        focusedPostID = preferredPostID
        DispatchQueue.main.async {
            withAnimation(.smooth(duration: 0.45)) {
                proxy.scrollTo(preferredPostID, anchor: .top)
            }
        }
    }

    private func topVisiblePostID(in visibleRows: [VisibleNewsRow]) -> UnreadPostIdentity? {
        let sortedRows = visibleRows.sorted { lhs, rhs in
            lhs.minY < rhs.minY
        }
        return sortedRows.first(where: { $0.minY >= 0 })?.id ?? sortedRows.first?.id
    }

    private func badgeLabel(for count: Int) -> String {
        count > 99 ? "99+" : "\(count)"
    }

    @ViewBuilder
    private var emptyState: some View {
        if viewModel.isRefreshing {
            VStack(spacing: 14) {
                ProgressView()
                    .controlSize(.large)
                Text("Загружаю новости")
                    .font(.headline)
                Text("RSS и Telegram обновляются. Первый запуск может занять немного времени.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 32)
            }
        } else {
            ContentUnavailableView(
                "Новостей нет",
                systemImage: "line.3.horizontal.decrease.circle",
                description: Text(viewModel.errorMessage ?? "Измените фильтры или обновите источники.")
            )
        }
    }
}

private struct VisibleNewsRow: Equatable {
    let id: UnreadPostIdentity
    let minY: CGFloat
}

private struct VisibleNewsRowsPreferenceKey: PreferenceKey {
    static let defaultValue: [VisibleNewsRow] = []

    static func reduce(value: inout [VisibleNewsRow], nextValue: () -> [VisibleNewsRow]) {
        value.append(contentsOf: nextValue())
    }
}

private struct NewsRowView: View {
    let post: UnreadPost
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text(post.sourceKind == .rss ? "RSS" : "Telegram")
                    .font(.caption.weight(.bold))
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(.thinMaterial, in: Capsule(style: .continuous))

                Text(post.channelTitle)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)

                Spacer(minLength: 0)

            }

            Text(post.titleOrFallback)
                .font(.system(size: 16, weight: .semibold, design: .rounded))
                .foregroundStyle(.primary)
                .lineLimit(3)
                .multilineTextAlignment(.leading)

            let body = post.previewBody
            if body.isEmpty == false {
                Text(body)
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .lineLimit(3)
                    .multilineTextAlignment(.leading)
            }

            HStack(spacing: 8) {
                Image(systemName: "clock")
                Text(post.date.formatted(date: .abbreviated, time: .shortened))
                Spacer(minLength: 0)
                Image(systemName: "chevron.right")
            }
            .font(.caption)
            .foregroundStyle(.tertiary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(16)
        .background(rowBackground, in: RoundedRectangle(cornerRadius: 24, style: .continuous))
        .glassEffect(.regular.interactive(), in: RoundedRectangle(cornerRadius: 24, style: .continuous))
    }

    private var rowBackground: Color {
        if colorScheme == .dark {
            return Color.white.opacity(0.035)
        }
        return Color.white.opacity(0.28)
    }
}
