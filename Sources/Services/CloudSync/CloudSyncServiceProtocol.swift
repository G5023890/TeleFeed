import Foundation

@MainActor
protocol CloudSyncServiceProtocol: AnyObject {
    func pullAndMerge(local: PersistedAppState) async throws -> PersistedAppState
    func push(local: PersistedAppState) async throws -> PersistedAppState
    func sync(local: PersistedAppState) async throws -> PersistedAppState
}
