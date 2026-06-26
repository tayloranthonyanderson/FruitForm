import Foundation
import Security

/// Thin wrapper over the iOS keychain for a single generic-password secret
/// (the Anthropic API key). Stored under one fixed service+account so it stays
/// on this device only — unlike `@AppStorage`, it is never written to the
/// iCloud-backed defaults plist. No special entitlements are needed for the
/// app's own generic-password items.
enum Keychain {
    private static let service = "com.fruitform.app"
    private static let account = "anthropicAPIKey"

    /// Reads the stored string, or nil if no item exists / the bytes aren't UTF-8.
    static func read() -> String? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne
        ]
        var item: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &item)
        guard status == errSecSuccess,
              let data = item as? Data,
              let value = String(data: data, encoding: .utf8) else { return nil }
        return value
    }

    /// Upserts the secret; an empty string clears the item. Returns whether the
    /// keychain ended in the requested state.
    @discardableResult
    static func set(_ value: String) -> Bool {
        guard !value.isEmpty else { return delete() }
        guard let data = value.data(using: .utf8) else { return false }

        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account
        ]
        let attributes: [String: Any] = [kSecValueData as String: data]

        let updateStatus = SecItemUpdate(query as CFDictionary, attributes as CFDictionary)
        if updateStatus == errSecSuccess { return true }
        guard updateStatus == errSecItemNotFound else { return false }

        var addQuery = query
        addQuery[kSecValueData as String] = data
        addQuery[kSecAttrAccessible as String] = kSecAttrAccessibleWhenUnlockedThisDeviceOnly
        return SecItemAdd(addQuery as CFDictionary, nil) == errSecSuccess
    }

    /// Removes the stored secret. Succeeds whether or not an item was present.
    @discardableResult
    static func delete() -> Bool {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account
        ]
        let status = SecItemDelete(query as CFDictionary)
        return status == errSecSuccess || status == errSecItemNotFound
    }
}
