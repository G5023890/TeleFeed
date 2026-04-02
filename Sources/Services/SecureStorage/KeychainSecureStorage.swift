import Foundation
import Security

final class KeychainSecureStorage: SecureStorageProtocol {
    private let service = "com.codex.TeleFeed"
    private let legacyService = "com.codex.Telega"

    func save(_ value: String, for key: String) throws {
        let data = Data(value.utf8)

        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: key,
        ]

        let attributes: [String: Any] = [
            kSecValueData as String: data,
        ]

        let status: OSStatus
        if try loadValue(for: key, service: service) != nil {
            status = SecItemUpdate(query as CFDictionary, attributes as CFDictionary)
        } else {
            var combined = query
            combined[kSecValueData as String] = data
            status = SecItemAdd(combined as CFDictionary, nil)
        }

        guard status == errSecSuccess else {
            throw SecureStorageError.unhandledStatus(status)
        }

        _ = deleteValue(for: key, service: legacyService)
    }

    func loadValue(for key: String) throws -> String? {
        if let value = try loadValue(for: key, service: service) {
            return value
        }
        return try loadValue(for: key, service: legacyService)
    }

    func deleteValue(for key: String) throws {
        let primaryStatus = deleteValue(for: key, service: service)
        let legacyStatus = deleteValue(for: key, service: legacyService)
        guard
            primaryStatus == errSecSuccess || primaryStatus == errSecItemNotFound,
            legacyStatus == errSecSuccess || legacyStatus == errSecItemNotFound
        else {
            throw SecureStorageError.unhandledStatus(primaryStatus != errSecSuccess ? primaryStatus : legacyStatus)
        }
    }

    private func loadValue(for key: String, service: String) throws -> String? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: key,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne,
        ]

        var result: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        switch status {
        case errSecSuccess:
            guard let data = result as? Data else {
                return nil
            }
            return String(data: data, encoding: .utf8)
        case errSecItemNotFound:
            return nil
        default:
            throw SecureStorageError.unhandledStatus(status)
        }
    }

    private func deleteValue(for key: String, service: String) -> OSStatus {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: key,
        ]

        return SecItemDelete(query as CFDictionary)
    }
}

enum SecureStorageError: LocalizedError {
    case unhandledStatus(OSStatus)

    var errorDescription: String? {
        switch self {
        case .unhandledStatus(let status):
            return "Keychain error: \(status)"
        }
    }
}
