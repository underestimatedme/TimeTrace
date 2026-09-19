import Foundation

/// Local persistence for display/behaviour preferences (UserDefaults). Kept
/// separate from the synced state snapshot. Under UI testing it is in-memory so
/// runs stay isolated.
final class PreferencesStore {
    private let key = "keji.preferences.v1"
    private let defaults: UserDefaults?

    init() {
        if LaunchOptions.current.uiTesting {
            // Isolated from the real defaults, but still persistent across launches so
            // UI tests can verify that a preference survives a relaunch. `--sample-data`
            // resets it, mirroring how the sample state file is reset.
            defaults = UserDefaults(suiteName: "keji-ui-testing")
            if LaunchOptions.current.sampleData {
                defaults?.removeObject(forKey: key)
                defaults?.removeObject(forKey: "keji.feedback.pending.v1")
            }
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

    // 未成功提交的反馈草稿（连同幂等键）。离开页面、重启 App 都还在，重试不会重复建单。
    private let feedbackKey = "keji.feedback.pending.v1"

    func loadPendingFeedback() -> FeedbackDraft? {
        guard let data = defaults?.data(forKey: feedbackKey) else { return nil }
        return try? JSONCoding.decoder.decode(FeedbackDraft.self, from: data)
    }

    func savePendingFeedback(_ draft: FeedbackDraft?) {
        guard let defaults else { return }
        if let draft, let data = try? JSONCoding.encoder.encode(draft) {
            defaults.set(data, forKey: feedbackKey)
        } else {
            defaults.removeObject(forKey: feedbackKey)
        }
    }
}
