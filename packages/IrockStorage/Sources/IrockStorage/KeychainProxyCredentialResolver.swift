import Foundation
import IrockCore
import IrockProtocols
import Security

public struct KeychainProxyCredentialResolver: ProxyCredentialResolver {
    public init() {}

    public func credential(for reference: CredentialReference) throws -> String {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: reference.keychainService,
            kSecAttrAccount as String: reference.account,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne
        ]

        var item: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &item)

        guard status == errSecSuccess else {
            if status == errSecItemNotFound {
                throw ProxyProtocolError.invalidConfiguration("credential not found in keychain: \(reference.keychainService)/\(reference.account)")
            }
            throw ProxyProtocolError.invalidConfiguration("keychain error: \(status)")
        }

        guard let data = item as? Data else {
            throw ProxyProtocolError.invalidConfiguration("invalid keychain data format")
        }

        guard let credential = String(data: data, encoding: .utf8) else {
            throw ProxyProtocolError.invalidConfiguration("invalid keychain data encoding")
        }

        return credential
    }

    public func storeCredential(_ credential: String, for reference: CredentialReference) throws {
        guard let data = credential.data(using: .utf8) else {
            throw ProxyProtocolError.invalidConfiguration("invalid credential encoding")
        }

        // Delete any existing item first
        let deleteQuery: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: reference.keychainService,
            kSecAttrAccount as String: reference.account
        ]
        SecItemDelete(deleteQuery as CFDictionary)

        // Add the new item
        let addQuery: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: reference.keychainService,
            kSecAttrAccount as String: reference.account,
            kSecValueData as String: data,
            kSecAttrAccessible as String: kSecAttrAccessibleAfterFirstUnlock
        ]

        let status = SecItemAdd(addQuery as CFDictionary, nil)
        guard status == errSecSuccess else {
            throw ProxyProtocolError.invalidConfiguration("failed to store credential in keychain: \(status)")
        }
    }

    public func deleteCredential(for reference: CredentialReference) throws {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: reference.keychainService,
            kSecAttrAccount as String: reference.account
        ]

        let status = SecItemDelete(query as CFDictionary)
        guard status == errSecSuccess || status == errSecItemNotFound else {
            throw ProxyProtocolError.invalidConfiguration("failed to delete credential from keychain: \(status)")
        }
    }
}
