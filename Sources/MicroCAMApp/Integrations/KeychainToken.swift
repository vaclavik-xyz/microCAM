import Foundation
import Security

/// The webhook token is a credential, so it is kept in the Keychain rather
/// than in UserDefaults. (Ad-hoc signed rebuilds may ask once to allow access.)
enum KeychainToken {
    private static let service = "xyz.vaclavik.microcam.webhook"
    private static let account = "token"

    private static var query: [String: Any] {
        [kSecClass as String: kSecClassGenericPassword,
         kSecAttrService as String: service,
         kSecAttrAccount as String: account]
    }

    static func read() -> String? {
        var q = query
        q[kSecReturnData as String] = true
        q[kSecMatchLimit as String] = kSecMatchLimitOne
        var item: CFTypeRef?
        guard SecItemCopyMatching(q as CFDictionary, &item) == errSecSuccess,
              let data = item as? Data else { return nil }
        return String(data: data, encoding: .utf8)
    }

    /// Empty or nil removes the token.
    static func write(_ token: String?) {
        SecItemDelete(query as CFDictionary)
        guard let token, !token.isEmpty else { return }
        var q = query
        q[kSecValueData as String] = Data(token.utf8)
        SecItemAdd(q as CFDictionary, nil)
    }
}
