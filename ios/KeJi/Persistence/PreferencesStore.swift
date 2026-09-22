import Foundation

/// Local persistence for display/behaviour preferences (UserDefaults). Kept
/// separate from the synced state snapshot. Every record is scoped to an account
/// id so switching accounts on one device never leaks another account's choices;
/// with no account there is nothing to load or save.
final class PreferencesStore {
    private let defaults: UserDefaults?

    init(defaults: UserDefaults? = PreferencesStore.defaultStorage()) {
        self.defaults = defaults
    }

    private static func defaultStorage() -> UserDefaults? {
        guard LaunchOptions.current.uiTesting else { return .standard }
        // Isolated from the real defaults, but still persistent across launches so
        // UI tests can verify that a preference survives a relaunch. `--sample-data`
        // resets it, mirroring how the sample state file is reset.
        let suite = UserDefaults(suiteName: "keji-ui-testing")
        if LaunchOptions.current.sampleData, let suite {
            for key in suite.dictionaryRepresentation().keys where key.hasPrefix("keji.") {
                suite.removeObject(forKey: key)
            }
        }
        return suite
    }

    private func scoped(_ prefix: String, _ userID: String) -> String {
        prefix + Data(userID.utf8).base64EncodedString()
    }
    private func prefsKey(_ userID: String) -> String { scoped("keji.preferences.v2.", userID) }
    private func syncKey(_ userID: String) -> String { scoped("keji.preferences.sync.v2.", userID) }

    func load(userID: String?) -> UserPreferences {
        guard let userID, let data = defaults?.data(forKey: prefsKey(userID)),
              let prefs = try? JSONCoding.decoder.decode(UserPreferences.self, from: data) else {
            return .defaults
        }
        return prefs
    }

    func save(_ prefs: UserPreferences, userID: String?) {
        guard let userID, let defaults, let data = try? JSONCoding.encoder.encode(prefs) else { return }
        defaults.set(data, forKey: prefsKey(userID))
    }

    // 偏好的同步基准：上次同步成功时服务端的版本与内容，同样按账号隔离。

    func loadSyncState(userID: String?) -> PreferencesSyncState {
        guard let userID, let data = defaults?.data(forKey: syncKey(userID)),
              let state = try? JSONCoding.decoder.decode(PreferencesSyncState.self, from: data) else { return .init() }
        return state
    }

    func saveSyncState(_ state: PreferencesSyncState, userID: String?) {
        guard let userID, let defaults, let data = try? JSONCoding.encoder.encode(state) else { return }
        defaults.set(data, forKey: syncKey(userID))
    }
}
