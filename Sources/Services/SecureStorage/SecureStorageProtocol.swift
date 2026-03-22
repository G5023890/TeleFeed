import Foundation

protocol SecureStorageProtocol {
    func save(_ value: String, for key: String) throws
    func loadValue(for key: String) throws -> String?
    func deleteValue(for key: String) throws
}

