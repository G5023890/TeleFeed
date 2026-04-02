import Foundation

final class FileAppStateStore: StateStoreProtocol {
    private enum DirectoryName {
        static let current = "TeleFeed"
        static let legacy = "Telega"
    }

    private let fileManager: FileManager
    private let fileURL: URL
    private let encoder = JSONEncoder()
    private let decoder = JSONDecoder()

    init(fileManager: FileManager = .default) {
        self.fileManager = fileManager
        let appSupport = fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        let directory = appSupport.appendingPathComponent(DirectoryName.current, isDirectory: true)
        let legacyDirectory = appSupport.appendingPathComponent(DirectoryName.legacy, isDirectory: true)
        try? fileManager.createDirectory(at: directory, withIntermediateDirectories: true)
        fileURL = directory.appendingPathComponent("state.json")
        let legacyFileURL = legacyDirectory.appendingPathComponent("state.json")
        if fileManager.fileExists(atPath: legacyFileURL.path), fileManager.fileExists(atPath: fileURL.path) == false {
            try? fileManager.createDirectory(at: directory, withIntermediateDirectories: true)
            try? fileManager.moveItem(at: legacyFileURL, to: fileURL)
        }
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
    }

    func load() -> PersistedAppState {
        guard
            let data = try? Data(contentsOf: fileURL),
            let state = try? decoder.decode(PersistedAppState.self, from: data)
        else {
            return loadLegacyState()
        }

        return state
    }

    func save(_ state: PersistedAppState) throws {
        let data = try encoder.encode(state)
        try data.write(to: fileURL, options: .atomic)
    }

    private func loadLegacyState() -> PersistedAppState {
        let appSupport = fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        let legacyFileURL = appSupport
            .appendingPathComponent(DirectoryName.legacy, isDirectory: true)
            .appendingPathComponent("state.json")

        guard
            let data = try? Data(contentsOf: legacyFileURL),
            let state = try? decoder.decode(PersistedAppState.self, from: data)
        else {
            return PersistedAppState()
        }

        return state
    }
}
