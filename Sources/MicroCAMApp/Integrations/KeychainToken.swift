import Foundation
import Security

/// Secrets (webhook token, stream photo PIN, MCP token) are kept in the Keychain rather
/// than in UserDefaults. (Ad-hoc signed rebuilds may ask once to allow access.)
enum KeychainToken {
    private static let service = "xyz.vaclavik.microcam.webhook"

    private static func query(_ account: String) -> [String: Any] {
        [kSecClass as String: kSecClassGenericPassword,
         kSecAttrService as String: service,
         kSecAttrAccount as String: account]
    }

    static func read(account: String = "token") -> String? {
        var q = query(account)
        q[kSecReturnData as String] = true
        q[kSecMatchLimit as String] = kSecMatchLimitOne
        var item: CFTypeRef?
        guard SecItemCopyMatching(q as CFDictionary, &item) == errSecSuccess,
              let data = item as? Data else { return nil }
        return String(data: data, encoding: .utf8)
    }

    /// Empty or nil removes the secret. Returns false when the Keychain refused it.
    @discardableResult
    static func write(_ value: String?, account: String = "token") -> Bool {
        SecItemDelete(query(account) as CFDictionary)
        guard let value, !value.isEmpty else { return true }
        var q = query(account)
        q[kSecValueData as String] = Data(value.utf8)
        return SecItemAdd(q as CFDictionary, nil) == errSecSuccess
    }
}
