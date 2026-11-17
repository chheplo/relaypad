import Foundation
import Security

enum PairingStore {
    private static func query(_ account: String) -> [String: Any] {
        [kSecClass as String: kSecClassGenericPassword,
         kSecAttrService as String: "Relaypad.LocalPairing.v1",
         kSecAttrAccount as String: account]
    }

    static func read(_ account: String) -> String? {
        var lookup = query(account)
        lookup[kSecReturnData as String] = true
        lookup[kSecMatchLimit as String] = kSecMatchLimitOne
        var item: CFTypeRef?
        guard SecItemCopyMatching(lookup as CFDictionary, &item) == errSecSuccess,
              let data = item as? Data else { return nil }
        return String(data: data, encoding: .utf8)
    }

    static func save(_ code: String, for account: String) -> Bool {
        let attributes: [String: Any] = [kSecValueData as String: Data(code.utf8)]
        var record = query(account).merging(attributes) { _, new in new }
        record[kSecAttrAccessible as String] = kSecAttrAccessibleWhenUnlockedThisDeviceOnly
        let status = SecItemAdd(record as CFDictionary, nil)
        if status == errSecDuplicateItem {
            return SecItemUpdate(query(account) as CFDictionary, attributes as CFDictionary) == errSecSuccess
        }
        return status == errSecSuccess
    }

    static func remove(_ account: String) {
        SecItemDelete(query(account) as CFDictionary)
    }
}
