import SwiftUI

struct IOSReaderView: View {
    let post: UnreadPost
    @StateObject private var viewModel = IOSReaderViewModel()
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        ZStack {
            IOSGlassBackground()

            content
        }
        .navigationTitle("Статья")
        .navigationBarTitleDisplayMode(.inline)
        .task {
            viewModel.open(post: post)
        }
    }

    @ViewBuilder
    private var content: some View {
        switch viewModel.phase {
        case .idle, .loading:
            VStack(spacing: 14) {
                ProgressView()
                    .controlSize(.large)
                Text("Загружаю статью")
                    .font(.headline)
                    .foregroundStyle(.secondary)
            }
        case .failed(let message):
            ContentUnavailableView(
                "Статья недоступна",
                systemImage: "doc.text.magnifyingglass",
                description: Text(message)
            )
        case .loaded(let article):
            IOSReaderWebView(
                html: ReaderHTMLTemplate.makeHTML(
                    for: article,
                    settings: AppSettings(),
                    appearance: colorScheme == .dark ? .dark : .light
                ),
                baseURL: article.canonicalURL
            )
            .ignoresSafeArea(edges: .bottom)
        }
    }
}
