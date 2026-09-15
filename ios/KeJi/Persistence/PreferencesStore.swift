import Foundation

/// Local persistence for display/behaviour preferences (UserDefaults). Kept
/// separate from the synced state snapshot. Under UI testing it is in-memory so
/// runs stay isolated.
final class PreferencesStore {
    private let key = "keji.preferences.v1"
    private let defaults: UserDefaults?

    init() {
        if LaunchOptions.current.uiTesting {
            defaults = nil // isolated: don't read or write real UserDefaults
        } else {
            defaults = .standard
        }
    }

    func load() -> UserPreferences {
        guard let data = defaults?.data(forKey: key),
              let prefs = try? JSONCoding.decoder.decode(UserPreferences.self, from: data) else {
            return .defaults
        }
        return prefs
    }

    func save(_ prefs: UserPreferences) {
        guard let defaults, let data = try? JSONCoding.encoder.encode(prefs) else { return }
        defaults.set(data, forKey: key)
    }
}
