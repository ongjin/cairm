import Foundation
import Security

/// Reads/writes SSH login passwords to macOS Keychain, keyed by ssh_config
/// nickname (when saved with "Save to ~/.ssh/config as:") or by a synthetic
/// `user@host:port` string for ad-hoc connections.
///
/// Parallel to `KeychainPassphraseStore`; separated so the two secret
/// categories never cross-contaminate in Keychain Access and so that deleting
/// one doesn't nuke the other.
enum KeychainPasswordStore {
    private static let service = "com.cairn.ssh.password"

    /// Keychain account identifier for a host alias. Prefixed so Keychain
    /// Access groups Cairn's password entries distinct from its key-file ones.
    private static func account(for alias: String) -> String {
        "ssh-pw:\(alias)"
    }

    static func load(for alias: String) -> String? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account(for: alias),
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne,
        ]
        var item: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &item)
        guard status == errSecSuccess, let data = item as? Data else { return nil }
        return String(data: data, encoding: .utf8)
    }

    static func save(_ password: String, for alias: String) {
        let account = account(for: alias)
        let delete: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
        ]
        SecItemDelete(delete as CFDictionary)
        let add: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecValueData as String: Data(password.utf8),
            kSecAttrAccessible as String: kSecAttrAccessibleWhenUnlocked,
        ]
        SecItemAdd(add as CFDictionary, nil)
    }

    static func delete(for alias: String) {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account(for: alias),
        ]
        SecItemDelete(query as CFDictionary)
    }
}
