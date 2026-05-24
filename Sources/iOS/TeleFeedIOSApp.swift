import SwiftUI
import BackgroundTasks

@main
struct TeleFeedIOSApp: App {
    private static let backgroundRefreshIdentifier = "com.codex.TeleFeed.iOS.news-refresh"

    @StateObject private var viewModel = IOSNewsFlowViewModel()
    @Environment(\.scenePhase) private var scenePhase

    init() {
        BGTaskScheduler.shared.register(
            forTaskWithIdentifier: Self.backgroundRefreshIdentifier,
            using: nil
        ) { task in
            guard let task = task as? BGAppRefreshTask else {
                task.setTaskCompleted(success: false)
                return
            }
            Self.scheduleBackgroundRefresh()
            let refreshTask = Task {
                let viewModel = await MainActor.run {
                    BackgroundRefreshCoordinator.shared.viewModel
                }
                await viewModel?.performBackgroundRefresh()
                task.setTaskCompleted(success: Task.isCancelled == false)
            }
            task.expirationHandler = {
                refreshTask.cancel()
            }
        }
    }

    var body: some Scene {
        WindowGroup {
            IOSNewsFlowView(viewModel: viewModel)
                .onAppear {
                    BackgroundRefreshCoordinator.shared.viewModel = viewModel
                    Self.scheduleBackgroundRefresh()
                }
                .onChange(of: scenePhase) { _, newPhase in
                    if newPhase == .background {
                        Self.scheduleBackgroundRefresh()
                    }
                }
        }
    }

    private static func scheduleBackgroundRefresh() {
        let request = BGAppRefreshTaskRequest(identifier: backgroundRefreshIdentifier)
        request.earliestBeginDate = Date(timeIntervalSinceNow: 15 * 60)
        try? BGTaskScheduler.shared.submit(request)
    }
}

@MainActor
private final class BackgroundRefreshCoordinator {
    static let shared = BackgroundRefreshCoordinator()
    weak var viewModel: IOSNewsFlowViewModel?
}
