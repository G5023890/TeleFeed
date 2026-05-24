import SwiftUI

struct IOSNewsFlowView: View {
    @ObservedObject var viewModel: IOSNewsFlowViewModel
    @Environment(\.scenePhase) private var scenePhase

    var body: some View {
        NavigationStack(path: $viewModel.path) {
            NewsListView(viewModel: viewModel)
                .navigationDestination(for: IOSNewsFlowViewModel.Route.self) { route in
                    switch route {
                    case .detail(let postID):
                        if let post = viewModel.post(for: postID) {
                            NewsDetailView(
                                post: post,
                                onDownloadMedia: { post in
                                    try await viewModel.downloadMedia(for: post)
                                },
                                onOpenReader: {
                                    viewModel.openReader(for: post)
                                }
                            )
                        } else {
                            MissingNewsView()
                        }
                    case .reader(let postID):
                        if let post = viewModel.post(for: postID) {
                            IOSReaderView(post: post)
                        } else {
                            MissingNewsView()
                        }
                    }
                }
        }
        .tint(.primary)
        .onAppear {
            viewModel.start()
        }
        .onChange(of: scenePhase) { _, newValue in
            if newValue == .active {
                viewModel.resumeFromForeground()
            } else if newValue == .background {
                Task {
                    await viewModel.stop()
                }
            }
        }
    }
}

private struct MissingNewsView: View {
    var body: some View {
        ContentUnavailableView(
            "Новость недоступна",
            systemImage: "newspaper",
            description: Text("Лента обновилась, и эта запись больше не находится в локальном списке.")
        )
        .navigationTitle("Новость")
    }
}
