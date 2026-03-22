import Foundation

final class FileAppStateStore: StateStoreProtocol {
    private let fileURL: URL
    private let encoder = JSONEncoder()
    private let decoder = JSONDecoder()

    init(fileManager: FileManager = .default) {
        let appSupport = fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        let directory = appSupport.appendingPathComponent("Telega", isDirectory: true)
        try? fileManager.createDirectory(at: directory, withIntermediateDirectories: true)
        fileURL = directory.appendingPathComponent("state.json")
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
    }

    func load() -> PersistedAppState {
        guard
            let data = try? Data(contentsOf: fileURL),
            let state = try? decoder.decode(PersistedAppState.self, from: data)
        else {
            return PersistedAppState()
        }

        return state
    }

    func save(_ state: PersistedAppState) throws {
        let data = try encoder.encode(state)
        try data.write(to: fileURL, options: .atomic)
    }
}

