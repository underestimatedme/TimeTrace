import Foundation
import Security

/// Stores session tokens in the Keychain (service `com.atlaspaces.keji`).
///
/// The Keychain can refuse writes (e.g. unsigned simulator builds return
/// `errSecMissingEntitlement`). Every status is checked; when the Keychain is
/// unavailable the tokens fall back to a file in Application Support with
/// complete file protection, so a session is never silently lost.
final class KeychainStore {
    static let service = "com.atlaspaces.keji"
    private let account: String
    private var cache: SessionTokens?
    private var cacheLoaded = false
    private var keychainUsable = true

    init(account: String = "session-tokens") { self.account = account }

    private var baseQuery: [String: Any] {
        [kSecClass as String: kSecClassGenericPassword,
         kSecAttrService as String: KeychainStore.service,
         kSecAttrAccount as String: account]
    }

    func loadTokens() -> SessionTokens? {
        if cacheLoaded { return cache }
        cacheLoaded = true
        cache = loadFromKeychain() ?? loadFromFile()
        return cache
    }

    func saveTokens(_ tokens: SessionTokens) {
        cache = tokens
        cacheLoaded = true
        guard let data = try? JSONCoding.encoder.encode(tokens) else { return }
        if keychainUsable, saveToKeychain(data) {
            removeFile()
            return
        }
        keychainUsable = false
        saveToFile(data)
    }

    func clear() {
        cache = nil
        cacheLoaded = true
        SecItemDelete(baseQuery as CFDictionary)
        removeFile()
    }

    // MARK: - Keychain

    private func loadFromKeychain() -> SessionTokens? {
        var query = baseQuery
        query[kSecReturnData as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne
        var item: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &item)
        guard status == errSecSuccess, let data = item as? Data else {
            if status != errSecItemNotFound { keychainUsable = false }
            return nil
        }
        return try? JSONCoding.decoder.decode(SessionTokens.self, from: data)
    }

    private func saveToKeychain(_ data: Data) -> Bool {
        let update = SecItemUpdate(baseQuery as CFDictionary, [kSecValueData as String: data] as CFDictionary)
        if update == errSecSuccess { return true }
        guard update == errSecItemNotFound else { return false }
        var add = baseQuery
        add[kSecValueData as String] = data
        add[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlock
        return SecItemAdd(add as CFDictionary, nil) == errSecSuccess
    }

    // MARK: - File fallback

    private var fileURL: URL? {
        guard let dir = try? FileManager.default.url(for: .applicationSupportDirectory, in: .userDomainMask,
                                                     appropriateFor: nil, create: true) else { return nil }
        let folder = dir.appendingPathComponent("KeJi", isDirectory: true)
        try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        return folder.appendingPathComponent("session-\(account).json")
    }

    private func loadFromFile() -> SessionTokens? {
        guard let url = fileURL, let data = try? Data(contentsOf: url) else { return nil }
        return try? JSONCoding.decoder.decode(SessionTokens.self, from: data)
    }

    private func saveToFile(_ data: Data) {
        guard let url = fileURL else { return }
        try? data.write(to: url, options: [.atomic, .completeFileProtection])
    }

    private func removeFile() {
        guard let url = fileURL else { return }
        try? FileManager.default.removeItem(at: url)
    }
}
