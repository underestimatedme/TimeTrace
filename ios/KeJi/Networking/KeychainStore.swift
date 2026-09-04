import Foundation
import Security

/// Stores session tokens in the Keychain (service `com.atlaspaces.keji`).
final class KeychainStore {
    static let service = "com.atlaspaces.keji"
    private let account: String

    init(account: String = "session-tokens") { self.account = account }

    private var baseQuery: [String: Any] {
        [kSecClass as String: kSecClassGenericPassword,
         kSecAttrService as String: KeychainStore.service,
         kSecAttrAccount as String: account]
    }

    func loadTokens() -> SessionTokens? {
        var query = baseQuery
        query[kSecReturnData as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne
        var item: CFTypeRef?
        guard SecItemCopyMatching(query as CFDictionary, &item) == errSecSuccess,
              let data = item as? Data else { return nil }
        return try? JSONCoding.decoder.decode(SessionTokens.self, from: data)
    }

    func saveTokens(_ tokens: SessionTokens) {
        guard let data = try? JSONCoding.encoder.encode(tokens) else { return }
        let status = SecItemUpdate(baseQuery as CFDictionary, [kSecValueData as String: data] as CFDictionary)
        if status == errSecItemNotFound {
            var add = baseQuery
            add[kSecValueData as String] = data
            add[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlock
            SecItemAdd(add as CFDictionary, nil)
        }
    }

    func clear() {
        SecItemDelete(baseQuery as CFDictionary)
    }
}
