import SwiftUI

struct FeedListView: View {
    let channel: WatchedChannel
    @ObservedObject var viewModel: FeedViewModel
    let onRefresh: () -> Void
    let onOpen: (UnreadPost) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text(channel.title)
                        .font(.system(size: 28, weight: .semibold, design: .rounded))
                    Text("@\(channel.username)")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                }

                Spacer()

                Button(L10n.tr("feed.refresh"), action: onRefresh)
                    .buttonStyle(.bordered)
            }

            if viewModel.isLoading {
                ProgressView()
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if viewModel.unreadPosts.isEmpty {
                ContentUnavailableView(L10n.tr("feed.empty"), systemImage: "tray")
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                ScrollView {
                    LazyVStack(spacing: 14) {
                        ForEach(viewModel.unreadPosts) { post in
                            Button {
                                onOpen(post)
                            } label: {
                                VStack(alignment: .leading, spacing: 10) {
                                    HStack {
                                        Text(post.author ?? post.channelTitle)
                                            .font(.headline)
                                        Spacer()
                                        Text(post.date.formatted(date: .abbreviated, time: .shortened))
                                            .font(.caption)
                                            .foregroundStyle(.secondary)
                                    }

                                    Text(post.summary.isEmpty ? L10n.tr("notifications.defaultBody") : post.summary)
                                        .font(.body)
                                        .multilineTextAlignment(.leading)
                                        .lineLimit(5)

                                    Text(postTypeLabel(post.content))
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                }
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .padding(18)
                                .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 24, style: .continuous))
                            }
                            .buttonStyle(.plain)
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
        .padding(28)
    }

    private func postTypeLabel(_ content: TelegramPostContent) -> String {
        switch content {
        case .text:
            return "Text"
        case .photo:
            return "Photo"
        case .video:
            return "Video"
        case .unsupported:
            return L10n.tr("feed.unsupported")
        }
    }
}

