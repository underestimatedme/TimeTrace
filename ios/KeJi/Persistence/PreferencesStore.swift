import Foundation

/// Local persistence for display/behaviour preferences (UserDefaults). Kept
/// separate from the synced state snapshot. Under UI testing it is in-memory so
/// runs stay isolated.
final class PreferencesStore {
    private let defaults: UserDefaults?

    init(defaults: UserDefaults? = LaunchOptions.current.uiTesting ? nil : .standard) {
        self.defaults = defaults
    }

    private func key(_ userID: String) -> String {
        "keji.preferences.v2." + Data(userID.utf8).base64EncodedString()
    }

    func load(userID: String?) -> UserPreferences {
        guard let userID, let data = defaults?.data(forKey: key(userID)),
              let prefs = try? JSONCoding.decoder.decode(UserPreferences.self, from: data) else {
            return .defaults
        }
        return prefs
    }

    func save(_ prefs: UserPreferences, userID: String?) {
        guard let userID, let defaults, let data = try? JSONCoding.encoder.encode(prefs) else { return }
        defaults.set(data, forKey: key(userID))
    }
}
