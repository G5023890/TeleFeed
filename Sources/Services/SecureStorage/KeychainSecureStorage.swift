import Foundation
import Security

final class KeychainSecureStorage: SecureStorageProtocol {
    private let service = "com.codex.Telega"

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
        if try loadValue(for: key) != nil {
            status = SecItemUpdate(query as CFDictionary, attributes as CFDictionary)
        } else {
            var combined = query
            combined[kSecValueData as String] = data
            status = SecItemAdd(combined as CFDictionary, nil)
        }

        guard status == errSecSuccess else {
            throw SecureStorageError.unhandledStatus(status)
        }
    }

    func loadValue(for key: String) throws -> String? {
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

    func deleteValue(for key: String) throws {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: key,
        ]

        let status = SecItemDelete(query as CFDictionary)
        guard status == errSecSuccess || status == errSecItemNotFound else {
            throw SecureStorageError.unhandledStatus(status)
        }
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

