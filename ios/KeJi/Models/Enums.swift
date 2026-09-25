import Foundation

// String raw values are identical to the TS unions in design/src/types/index.ts
// and to the enum strings the backend stores (spec §3.2).

enum ProjectStatus: String, Codable, CaseIterable {
    case active, archived, paused
}

enum GoalStatus: String, Codable, CaseIterable {
    case active, completed, paused, cancelled
}

enum ExecutorType: String, Codable, CaseIterable {
    case human, ai, collaboration, external

    var label: String {
        switch self {
        case .human: return "我"
        case .ai: return "AI"
        case .collaboration: return "协作"
        case .external: return "外部"
        }
    }
}

enum AIProvider: String, Codable, CaseIterable {
    case claude, codex, chatgpt, gemini, other

    var label: String {
        switch self {
        case .claude: return "Claude"
        case .codex: return "Codex"
        case .chatgpt: return "ChatGPT"
        case .gemini: return "Gemini"
        case .other: return "其他"
        }
    }

    /// Mirrors `p.charAt(0).toUpperCase() + p.slice(1)` in TaskCreate.tsx.
    var capitalizedRaw: String { rawValue.prefix(1).uppercased() + rawValue.dropFirst() }
}

enum TaskStatus: String, Codable, CaseIterable {
    case inbox, planned, ready
    case humanRunning = "human_running"
    case aiQueued = "ai_queued"
    case aiRunning = "ai_running"
    case waitingHuman = "waiting_human"
    case waitingExternal = "waiting_external"
    case paused, completed, failed, cancelled

    /// 服务端曾写过 todo / in_progress；不认识的状态按「待开始」处理，绝不让整份同步失败。
    init(from decoder: Decoder) throws {
        let raw = try decoder.singleValueContainer().decode(String.self)
        self = TaskStatus(rawValue: raw) ?? .ready
    }

    var label: String {
        switch self {
        case .inbox: return "收件箱"
        case .planned: return "已计划"
        case .ready: return "待开始"
        case .humanRunning: return "进行中"
        case .aiQueued: return "AI 排队"
        case .aiRunning: return "AI 执行中"
        case .waitingHuman: return "等待我"
        case .waitingExternal: return "等待外部"
        case .paused: return "已暂停"
        case .completed: return "已完成"
        case .failed: return "失败"
        case .cancelled: return "已取消"
        }
    }

    static let pending: [TaskStatus] = [
        .inbox, .planned, .ready, .humanRunning, .aiQueued, .aiRunning, .waitingHuman, .waitingExternal, .paused,
    ]
    static let startable: [TaskStatus] = [.ready, .planned, .inbox, .paused]
    static let terminal: [TaskStatus] = [.completed, .cancelled, .failed]
}

enum TaskPriority: String, Codable, CaseIterable {
    case low, medium, high, urgent

    var label: String {
        switch self {
        case .low: return "低"
        case .medium: return "中"
        case .high: return "高"
        case .urgent: return "紧急"
        }
    }
}

enum CollaborationMode: String, Codable, CaseIterable {
    case aiIndependent = "ai_independent"
    case aiFirstReview = "ai_first_review"
    case humanFirstAI = "human_first_ai"
    case alternating

    var label: String {
        switch self {
        case .aiIndependent: return "AI 独立完成"
        case .aiFirstReview: return "AI 先做，我审核"
        case .humanFirstAI: return "我先准备，AI 执行"
        case .alternating: return "我和 AI 交替完成"
        }
    }
}

enum TimeSessionType: String, Codable, CaseIterable {
    case humanFocus = "human_focus"
    case humanReview = "human_review"
    case aiActive = "ai_active"
    case aiIdle = "ai_idle"
    case waitingHuman = "waiting_human"
    case waitingAI = "waiting_ai"
    case waitingExternal = "waiting_external"
    case interruption, rework

    /// Timeline legend label (Timeline.tsx typeLabels).
    var label: String {
        switch self {
        case .humanFocus: return "我"
        case .humanReview: return "我·审核"
        case .aiActive: return "AI"
        case .aiIdle: return "AI·空闲"
        case .waitingHuman: return "等待我"
        case .waitingAI: return "等待 AI"
        case .waitingExternal: return "等待外部"
        case .interruption: return "中断"
        case .rework: return "返工"
        }
    }
}

enum TimeSessionSource: String, Codable, CaseIterable {
    case manual, timer, integration, inferred, simulated
}

enum Confidence: String, Codable, CaseIterable {
    case exact, estimated
}

enum AIExecutionStatus: String, Codable, CaseIterable {
    case queued, running
    case waitingAuth = "waiting_auth"
    case waitingInput = "waiting_input"
    case completed, failed, cancelled

    var label: String {
        switch self {
        case .queued: return "排队中"
        case .running: return "执行中"
        case .waitingAuth: return "等待授权"
        case .waitingInput: return "等待用户输入"
        case .completed: return "已完成"
        case .failed: return "执行失败"
        case .cancelled: return "已取消"
        }
    }
}

enum ExperimentStatus: String, Codable, CaseIterable {
    case active, completed, planned

    var label: String {
        switch self {
        case .active: return "进行中"
        case .planned: return "计划中"
        case .completed: return "已完成"
        }
    }
}

enum ThemeName: String, Codable, CaseIterable {
    case claude, codex, cursor, light, dark
}
