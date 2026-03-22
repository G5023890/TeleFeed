import Foundation
import TDLibFramework

struct TDLibError: LocalizedError {
    let code: Int
    let message: String

    var errorDescription: String? {
        "TDLib error \(code): \(message)"
    }
}

private final class TDJSONClientHandle: @unchecked Sendable {
    let pointer: UnsafeMutableRawPointer

    init?(pointer: UnsafeMutableRawPointer?) {
        guard let pointer else {
            return nil
        }
        self.pointer = pointer
    }
}

actor TDLibClient {
    private var clientHandle: TDJSONClientHandle?
    private var receiveTask: Task<Void, Never>?
    private var pendingResponses: [String: CheckedContinuation<String, Error>] = [:]
    private var pendingResponseOrder: [String] = []
    private var updateHandler: (@Sendable (String) -> Void)?

    func setUpdateHandler(_ handler: @escaping @Sendable (String) -> Void) {
        updateHandler = handler
    }

    func start() {
        guard receiveTask == nil else {
            return
        }
        if clientHandle == nil {
            clientHandle = TDJSONClientHandle(pointer: td_json_client_create())
        }
        guard let clientHandle else {
            return
        }

        receiveTask = Task.detached(priority: .background) { [weak self, clientHandle] in
            while Task.isCancelled == false {
                guard let rawPointer = td_json_client_receive(clientHandle.pointer, 0.25) else {
                    continue
                }

                let response = String(cString: rawPointer)
                await self?.handle(responseString: response)
            }
        }
    }

    func stop() async {
        let task = receiveTask
        task?.cancel()
        receiveTask = nil
        await task?.value

        for (_, continuation) in pendingResponses {
            continuation.resume(throwing: CancellationError())
        }
        pendingResponses.removeAll()
        pendingResponseOrder.removeAll()
        if let clientHandle {
            td_json_client_destroy(clientHandle.pointer)
            self.clientHandle = nil
        }
    }

    func send(_ requestJSON: String, extra: String) async throws -> String {
        guard let clientHandle else {
            throw TDLibError(code: -1, message: "TDLib client is unavailable.")
        }
        return try await withCheckedThrowingContinuation { continuation in
            pendingResponses[extra] = continuation
            pendingResponseOrder.append(extra)
            requestJSON.withCString { pointer in
                td_json_client_send(clientHandle.pointer, pointer)
            }
        }
    }

    func sendWithoutResponse(_ requestJSON: String) throws {
        guard let clientHandle else {
            throw TDLibError(code: -1, message: "TDLib client is unavailable.")
        }

        requestJSON.withCString { pointer in
            td_json_client_send(clientHandle.pointer, pointer)
        }
    }

    func execute(_ requestJSON: String) -> String? {
        requestJSON.withCString { pointer in
            guard let responsePointer = td_json_client_execute(clientHandle?.pointer, pointer) else {
                return nil
            }
            return String(cString: responsePointer)
        }
    }

    private func handle(responseString: String) {
        guard let object = Self.deserialize(responseString) else {
            return
        }

        if let extra = object.string("@extra"), let continuation = pendingResponses.removeValue(forKey: extra) {
            pendingResponseOrder.removeAll { $0 == extra }
            if object.tdType == "error" {
                continuation.resume(throwing: TDLibError(
                    code: Int(object.int32("code") ?? -1),
                    message: object.string("message") ?? "Unknown TDLib error"
                ))
            } else {
                continuation.resume(returning: responseString)
            }
            return
        }

        // Some TDLib JSON responses arrive without "@extra". TDLib still returns request
        // results in send order, so fall back to the oldest pending continuation.
        if object.tdType?.hasPrefix("update") != true,
           let key = pendingResponseOrder.first,
           let continuation = pendingResponses.removeValue(forKey: key) {
            pendingResponseOrder.removeFirst()
            print("[Telega][TDLibClient] Resumed pending request without @extra: \(object.tdType ?? "unknown")")
            if object.tdType == "error" {
                continuation.resume(throwing: TDLibError(
                    code: Int(object.int32("code") ?? -1),
                    message: object.string("message") ?? "Unknown TDLib error"
                ))
            } else {
                continuation.resume(returning: responseString)
            }
            return
        }

        updateHandler?(responseString)
    }

    private static func deserialize(_ string: String) -> TDLibObject? {
        guard
            let data = string.data(using: .utf8),
            let json = try? JSONSerialization.jsonObject(with: data) as? TDLibObject
        else {
            return nil
        }
        return json
    }
}
