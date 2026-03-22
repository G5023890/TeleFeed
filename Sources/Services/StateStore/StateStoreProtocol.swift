import Foundation

protocol StateStoreProtocol {
    func load() -> PersistedAppState
    func save(_ state: PersistedAppState) throws
}

