@preconcurrency import CloudKit
import Foundation
import OSLog

@MainActor
final class CloudSyncService: CloudSyncServiceProtocol {
    private static let logger = Logger(subsystem: "com.codex.TeleFeed", category: "CloudSyncService")

    private enum Constants {
        static let containerIdentifier = "iCloud.com.codex.TeleFeed"
        static let recordType = "AppState"
        static let recordName = "shared-state-v1"
        static let stateJSONKey = "stateJSON"
        static let legacyPayloadKey = "payload"
        static let updatedAtKey = "updatedAt"
        static let keyValueStoreKey = "syncable-app-state-v1"
    }

    private let database: CKDatabase
    private let keyValueStore: NSUbiquitousKeyValueStore
    private let encoder = JSONEncoder()
    private let decoder = JSONDecoder()

    init(
        containerIdentifier: String = Constants.containerIdentifier,
        keyValueStore: NSUbiquitousKeyValueStore = .default
    ) {
        let container = CKContainer(identifier: containerIdentifier)
        self.database = container.privateCloudDatabase
        self.keyValueStore = keyValueStore
        encoder.outputFormatting = [.sortedKeys]
    }

    func pullAndMerge(local: PersistedAppState) async throws -> PersistedAppState {
        Self.logger.info("CloudKit pull begin")
        guard let remote = try await fetchRemoteState() else {
            Self.logger.info("CloudKit pull complete: no remote state")
            return local
        }

        let merged = SyncableAppState(local: local).merged(with: remote)
        Self.logger.info("CloudKit pull complete: merged remote state")
        return merged.applied(to: local)
    }

    func push(local: PersistedAppState) async throws -> PersistedAppState {
        Self.logger.info("CloudKit push begin")
        let localSyncable = SyncableAppState(local: local)
        var stateToPush = localSyncable
        do {
            stateToPush = Self.mergedStateForPush(local: local, remote: try await fetchRemoteState())
            let pushedState = try await push(state: stateToPush, retryOnConflict: true)
            saveKeyValueState(pushedState)
            Self.logger.info("CloudKit push complete")
            return pushedState.applied(to: local)
        } catch {
            if Self.canFallbackToKeyValueStore(error) {
                Self.logger.error("CloudKit push failed; using iCloud KVS fallback: \(Self.describe(error), privacy: .public)")
                saveKeyValueState(stateToPush)
                return stateToPush.applied(to: local)
            } else {
                Self.logger.error("CloudKit push failed: \(Self.describe(error), privacy: .public)")
                throw error
            }
        }
    }

    static func mergedStateForPush(local: PersistedAppState, remote: SyncableAppState?) -> SyncableAppState {
        let localSyncable = SyncableAppState(local: local)
        return remote.map { localSyncable.merged(with: $0) } ?? localSyncable
    }

    func sync(local: PersistedAppState) async throws -> PersistedAppState {
        Self.logger.info("CloudKit sync begin")
        do {
            let merged = try await pullAndMerge(local: local)
            let pushed = try await push(local: merged)
            Self.logger.info("CloudKit sync complete")
            return pushed
        } catch {
            Self.logger.error("CloudKit sync failed: \(Self.describe(error), privacy: .public)")
            throw error
        }
    }

    private func push(state syncable: SyncableAppState, retryOnConflict: Bool) async throws -> SyncableAppState {
        let record = try await fetchRecord() ?? CKRecord(
            recordType: Constants.recordType,
            recordID: CKRecord.ID(recordName: Constants.recordName)
        )
        let encodedState = try encoder.encode(syncable)
        guard let stateJSON = String(data: encodedState, encoding: .utf8) else {
            throw CloudSyncEncodingError()
        }
        record[Constants.stateJSONKey] = stateJSON as CKRecordValue
        record[Constants.legacyPayloadKey] = nil
        record[Constants.updatedAtKey] = Date() as CKRecordValue
        do {
            _ = try await save(record)
            return syncable
        } catch let error as CKError where retryOnConflict && error.code == .serverRecordChanged {
            Self.logger.info("CloudKit push conflict; retrying with server record")
            let serverRecord = error.serverRecord ?? CKRecord(
                recordType: Constants.recordType,
                recordID: CKRecord.ID(recordName: Constants.recordName)
            )
            let serverState = try decodeState(from: serverRecord)
            let mergedState = serverState?.merged(with: syncable) ?? syncable
            let mergedData = try encoder.encode(mergedState)
            guard let mergedStateJSON = String(data: mergedData, encoding: .utf8) else {
                throw CloudSyncEncodingError()
            }
            serverRecord[Constants.stateJSONKey] = mergedStateJSON as CKRecordValue
            serverRecord[Constants.legacyPayloadKey] = nil
            serverRecord[Constants.updatedAtKey] = record[Constants.updatedAtKey]
            _ = try await save(serverRecord)
            return mergedState
        }
    }

    private func fetchRemoteState() async throws -> SyncableAppState? {
        let keyValueState = fetchKeyValueState()
        do {
            guard let record = try await fetchRecord() else {
                return keyValueState
            }

            let cloudState = try decodeState(from: record)
            if let cloudState, let keyValueState {
                return keyValueState.merged(with: cloudState)
            }
            return cloudState ?? keyValueState
        } catch {
            if Self.canFallbackToKeyValueStore(error) {
                Self.logger.error("CloudKit pull failed; using iCloud KVS fallback: \(Self.describe(error), privacy: .public)")
                return keyValueState
            } else {
                throw error
            }
        }
    }

    private func decodeState(from record: CKRecord) throws -> SyncableAppState? {
        if let stateJSON = record[Constants.stateJSONKey] as? String,
           let payload = stateJSON.data(using: .utf8) {
            return try decoder.decode(SyncableAppState.self, from: payload)
        }

        guard let payload = record[Constants.legacyPayloadKey] as? Data else {
            return nil
        }
        return try decoder.decode(SyncableAppState.self, from: payload)
    }

    private func fetchKeyValueState() -> SyncableAppState? {
        keyValueStore.synchronize()
        guard let stateJSON = keyValueStore.string(forKey: Constants.keyValueStoreKey),
              let data = stateJSON.data(using: .utf8) else {
            return nil
        }
        return try? decoder.decode(SyncableAppState.self, from: data)
    }

    private func saveKeyValueState(_ state: SyncableAppState) {
        do {
            let data = try encoder.encode(state)
            guard let stateJSON = String(data: data, encoding: .utf8) else {
                throw CloudSyncEncodingError()
            }
            keyValueStore.set(stateJSON, forKey: Constants.keyValueStoreKey)
            keyValueStore.synchronize()
            Self.logger.info("iCloud KVS sync state saved")
        } catch {
            Self.logger.error("iCloud KVS sync state failed: \(Self.describe(error), privacy: .public)")
        }
    }

    private func fetchRecord() async throws -> CKRecord? {
        do {
            return try await fetchRecord(
                with: CKRecord.ID(recordName: Constants.recordName)
            )
        } catch let error as CKError where error.code == .unknownItem {
            return nil
        } catch let error as CKError where error.code == .serverRejectedRequest {
            Self.logger.error("CloudKit fetch treated as missing remote record: \(Self.describe(error), privacy: .public)")
            return nil
        }
    }

    private func fetchRecord(with id: CKRecord.ID) async throws -> CKRecord {
        try await withCheckedThrowingContinuation { continuation in
            let resume = SingleResumeContinuation(continuation)
            resume.timeout(after: 12, operation: "CloudKit fetch")
            database.fetch(withRecordID: id) { record, error in
                if let error {
                    resume.resume(throwing: error)
                } else if let record {
                    resume.resume(returning: record)
                } else {
                    resume.resume(throwing: CKError(.unknownItem))
                }
            }
        }
    }

    private func save(_ record: CKRecord) async throws -> CKRecord {
        try await withCheckedThrowingContinuation { continuation in
            let resume = SingleResumeContinuation(continuation)
            resume.timeout(after: 12, operation: "CloudKit save")
            database.save(record) { savedRecord, error in
                if let error {
                    resume.resume(throwing: error)
                } else if let savedRecord {
                    resume.resume(returning: savedRecord)
                } else {
                    resume.resume(throwing: CKError(.internalError))
                }
            }
        }
    }

    private static func describe(_ error: Error) -> String {
        guard let ckError = error as? CKError else {
            return error.localizedDescription
        }

        var parts = [
            "CKError.\(ckError.code)",
            ckError.localizedDescription
        ]
        if let serverDescription = ckError.userInfo[NSLocalizedFailureReasonErrorKey] as? String {
            parts.append(serverDescription)
        }
        if let retryAfter = ckError.userInfo[CKErrorRetryAfterKey] as? TimeInterval {
            parts.append("retryAfter=\(retryAfter)")
        }
        return parts.joined(separator: " | ")
    }

    private static func canFallbackToKeyValueStore(_ error: Error) -> Bool {
        guard let ckError = error as? CKError else {
            return false
        }
        switch ckError.code {
        case .networkFailure, .networkUnavailable, .serverRejectedRequest, .serviceUnavailable, .requestRateLimited, .zoneBusy:
            return true
        default:
            return false
        }
    }

}

private final class SingleResumeContinuation<Value>: @unchecked Sendable {
    private let lock = NSLock()
    private var continuation: CheckedContinuation<Value, Error>?

    init(_ continuation: CheckedContinuation<Value, Error>) {
        self.continuation = continuation
    }

    func resume(returning value: sending Value) {
        let continuation = takeContinuation()
        continuation?.resume(returning: value)
    }

    func resume(throwing error: Error) {
        let continuation = takeContinuation()
        continuation?.resume(throwing: error)
    }

    func timeout(after seconds: TimeInterval, operation: String) {
        DispatchQueue.global(qos: .utility).asyncAfter(deadline: .now() + seconds) { [weak self] in
            self?.resume(throwing: CloudSyncTimeoutError(operation: operation, seconds: seconds))
        }
    }

    private func takeContinuation() -> CheckedContinuation<Value, Error>? {
        lock.lock()
        defer {
            lock.unlock()
        }

        let continuation = continuation
        self.continuation = nil
        return continuation
    }
}

private struct CloudSyncTimeoutError: LocalizedError {
    let operation: String
    let seconds: TimeInterval

    var errorDescription: String? {
        "\(operation) timed out after \(Int(seconds)) seconds"
    }
}

private struct CloudSyncEncodingError: LocalizedError {
    var errorDescription: String? {
        "Cloud sync state could not be encoded as UTF-8 JSON"
    }
}
