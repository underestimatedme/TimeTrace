import Foundation

/// Home modules the user can rearrange. Core modules (goals / todos / blocked)
/// are never hidden — they carry the day's decisions.
enum HomeModule: String, Codable, CaseIterable, Identifiable {
    case goals, todos, blocked, timeline, aiActivity, insights

    var id: String { rawValue }
    var isCore: Bool { self == .goals || self == .todos || self == .blocked }
    var label: String {
        switch self {
        case .goals: return "目标"
        case .todos: return "待办"
        case .blocked: return "阻塞"
        case .timeline: return "时间线"
        case .aiActivity: return "AI 活动"
        case .insights: return "洞察"
        }
    }
}

/// Notification categories are independent of the auto-resume policy. Do-not-
/// disturb is expressed in the user's local hours.
struct NotificationPreferences: Codable, Equatable {
    var acceptance = true
    var failure = true
    var recovery = true
    var doNotDisturbStartHour: Int?
    var doNotDisturbEndHour: Int?
}

/// Display/behaviour preferences, kept separate from execution policy. Schema is
/// versioned; diagnostics default off.
struct UserPreferences: Codable, Equatable {
    var schemaVersion = 1
    var hiddenModules: Set<HomeModule> = []
    var reduceMotion = false
    var diagnosticsEnabled = false
    var notifications = NotificationPreferences()

    static let defaults = UserPreferences()

    init() {}

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        schemaVersion = try c.decodeIfPresent(Int.self, forKey: .schemaVersion) ?? 1
        hiddenModules = try c.decodeIfPresent(Set<HomeModule>.self, forKey: .hiddenModules) ?? []
        reduceMotion = try c.decodeIfPresent(Bool.self, forKey: .reduceMotion) ?? false
        diagnosticsEnabled = try c.decodeIfPresent(Bool.self, forKey: .diagnosticsEnabled) ?? false
        notifications = try c.decodeIfPresent(NotificationPreferences.self, forKey: .notifications) ?? NotificationPreferences()
    }

    /// Visible home modules in canonical order: core modules always present,
    /// non-core ones shown unless explicitly hidden.
    func resolvedVisibleModules() -> [HomeModule] {
        HomeModule.allCases.filter { $0.isCore || !hiddenModules.contains($0) }
    }

    /// Hiding a core module is a no-op; hiding a non-core module removes it.
    func hiding(_ module: HomeModule) -> UserPreferences {
        guard !module.isCore else { return self }
        var copy = self
        copy.hiddenModules.insert(module)
        return copy
    }

    func showing(_ module: HomeModule) -> UserPreferences {
        var copy = self
        copy.hiddenModules.remove(module)
        return copy
    }
}

/// A feedback submission kept idempotent by a stable key, so a retry after a
/// network failure does not open a second ticket. Drafts survive failures.
struct FeedbackDraft: Codable, Equatable {
    var idempotencyKey: String
    var text: String
    var attachDiagnostics: Bool = false

    static let maxLength = 4000

    static func new(text: String, attachDiagnostics: Bool = false) -> FeedbackDraft {
        FeedbackDraft(idempotencyKey: UUID().uuidString, text: text, attachDiagnostics: attachDiagnostics)
    }

    var isValid: Bool {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        return !trimmed.isEmpty && trimmed.count <= FeedbackDraft.maxLength
    }
}
