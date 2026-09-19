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
    var themeMode: ThemeMode = .light
    var accent: AccentPalette = .blue
    var diagnosticsEnabled = false
    var notifications = NotificationPreferences()

    static let defaults = UserPreferences()

    init() {}

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        schemaVersion = try c.decodeIfPresent(Int.self, forKey: .schemaVersion) ?? 1
        hiddenModules = try c.decodeIfPresent(Set<HomeModule>.self, forKey: .hiddenModules) ?? []
        reduceMotion = try c.decodeIfPresent(Bool.self, forKey: .reduceMotion) ?? false
        themeMode = try c.decodeIfPresent(ThemeMode.self, forKey: .themeMode) ?? .light
        accent = try c.decodeIfPresent(AccentPalette.self, forKey: .accent) ?? .blue
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

    var trimmedText: String { text.trimmingCharacters(in: .whitespacesAndNewlines) }

    /// 重试同一条反馈时沿用原来的幂等键，服务端返回同一张单，不会重复建单；
    /// 内容变了才生成新键。
    static func next(pending: FeedbackDraft?, text: String, attachDiagnostics: Bool) -> FeedbackDraft {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        if let pending, pending.trimmedText == trimmed {
            return FeedbackDraft(idempotencyKey: pending.idempotencyKey, text: text, attachDiagnostics: attachDiagnostics)
        }
        return .new(text: text, attachDiagnostics: attachDiagnostics)
    }
}

/// Valley 返回的反馈工单。
struct FeedbackTicket: Codable, Equatable {
    var ticketId: String
    var body: String
    var status: String
    var includeDiagnostics: Bool
    var createdAt: Date
    var updatedAt: Date
}

/// Valley `GET /preferences` / `PUT /preferences` 的记录。服务端还没记录时 revision 为 0、data 为 `{}`。
struct RemotePreferences: Decodable, Equatable {
    var revision: Int64
    var data: UserPreferences
}

/// 偏好的三方合并。Valley 要求冲突时重新合并、不能静默覆盖：
/// 以上次同步的版本为基准，只把本机改过的字段套到服务端最新版上。
enum PreferencesMerge {
    static func threeWay(base: UserPreferences, local: UserPreferences, remote: UserPreferences) -> UserPreferences {
        var merged = remote
        if local.hiddenModules != base.hiddenModules { merged.hiddenModules = local.hiddenModules }
        if local.reduceMotion != base.reduceMotion { merged.reduceMotion = local.reduceMotion }
        if local.themeMode != base.themeMode { merged.themeMode = local.themeMode }
        if local.accent != base.accent { merged.accent = local.accent }
        if local.diagnosticsEnabled != base.diagnosticsEnabled { merged.diagnosticsEnabled = local.diagnosticsEnabled }
        if local.notifications != base.notifications { merged.notifications = local.notifications }
        merged.schemaVersion = max(local.schemaVersion, remote.schemaVersion)
        return merged
    }
}

/// 上次同步成功时的服务端版本号与内容（三方合并的基准）。
struct PreferencesSyncState: Codable, Equatable {
    var revision: Int64 = 0
    var base: UserPreferences = .defaults
}

/// 偏好同步的决策，纯函数：本机没改过就采用服务端新版本；改过就合并后推送。
enum PreferencesSync {
    enum Action: Equatable {
        case none
        case adopt(UserPreferences, revision: Int64)
        case push(UserPreferences, expectedRevision: Int64)
    }

    static func plan(local: UserPreferences, state: PreferencesSyncState, remote: RemotePreferences) -> Action {
        let changedLocally = local != state.base
        guard changedLocally else {
            return remote.revision != state.revision ? .adopt(remote.data, revision: remote.revision) : .none
        }
        let merged = PreferencesMerge.threeWay(base: state.base, local: local, remote: remote.data)
        return .push(merged, expectedRevision: remote.revision)
    }
}
