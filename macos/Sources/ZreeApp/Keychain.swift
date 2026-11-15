import Foundation
import Security

/// Minimal generic-password storage.
///
/// Note: the app is ad-hoc signed, so rebuilding can reset its code identity and
/// macOS may ask once for permission to read an existing item.
enum Keychain {
    private static let service = "im.sush.zree"

    static func set(_ value: String, for account: String) {
        let data = Data(value.utf8)
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
        ]
        let attributes: [String: Any] = [kSecValueData as String: data]
        let status = SecItemUpdate(query as CFDictionary, attributes as CFDictionary)
        if status == errSecItemNotFound {
            var add = query
            add[kSecValueData as String] = data
            add[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlock
            SecItemAdd(add as CFDictionary, nil)
        }
    }

    static func get(_ account: String) -> String? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne,
        ]
        var item: CFTypeRef?
        guard SecItemCopyMatching(query as CFDictionary, &item) == errSecSuccess,
              let data = item as? Data
        else { return nil }
        return String(data: data, encoding: .utf8)
    }

    static func delete(_ account: String) {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
        ]
        SecItemDelete(query as CFDictionary)
    }

    /// Read from the Keychain, migrating a value left in UserDefaults.
    static func migrateFromDefaults(_ defaults: UserDefaults, defaultsKey: String, account: String) -> String? {
        if let existing = get(account) {
            if defaults.string(forKey: defaultsKey) != nil {
                defaults.removeObject(forKey: defaultsKey)
            }
            return existing
        }
        if let legacy = defaults.string(forKey: defaultsKey) {
            set(legacy, for: account)
            defaults.removeObject(forKey: defaultsKey)
            return legacy
        }
        return nil
    }
}
