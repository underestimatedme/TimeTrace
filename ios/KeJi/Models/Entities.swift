import Foundation

struct Project: Codable, Identifiable, Equatable {
    var id: String
    var name: String
    var description: String
    var icon: String
    var color: String
    var status: ProjectStatus
    var createdAt: Date
    var updatedAt: Date
}

struct Goal: Codable, Identifiable, Equatable {
    var id: String
    var projectId: String
    var title: String
    var description: String
    var targetDate: Date
    var progress: Double
    var status: GoalStatus
    var updatedAt: Date
}

/// Named `TaskItem` (not `Task`) to avoid clashing with Swift Concurrency's `Task`.
struct TaskItem: Codable, Identifiable, Equatable {
    var id: String
    var projectId: String
    var goalId: String?
    var title: String
    var description: String
    var executorType: ExecutorType
    var aiProvider: AIProvider?
    var collaborationMode: CollaborationMode?
    var status: TaskStatus
    var priority: TaskPriority
    var estimatedMinutes: Int
    /// `yyyy-MM-dd` (contract: due_date is a date-only string).
    var dueDate: String?
    var scheduledStart: Date?
    var scheduledEnd: Date?
    var createdAt: Date
    var completedAt: Date?
    var resultSummary: String?
    var updatedAt: Date
}

struct TimeSession: Codable, Identifiable, Equatable {
    var id: String
    var taskId: String
    var type: TimeSessionType
    /// "human" | AIProvider raw value | "external" (string union in TS).
    var executor: String
    var startedAt: Date
    var endedAt: Date?
    var durationSeconds: Int
    var source: TimeSessionSource
    var confidence: Confidence
    var note: String?
    var updatedAt: Date

    static let humanExecutor = "human"
    static let externalExecutor = "external"

    var isHumanExecutor: Bool { executor == TimeSession.humanExecutor }
    var providerExecutor: AIProvider? { AIProvider(rawValue: executor) }
    var isOpen: Bool { endedAt == nil }
}

struct AIExecutionLog: Codable, Equatable {
    var time: String
    var message: String
}

struct AIExecution: Codable, Identifiable, Equatable {
    var id: String
    var taskId: String
    var provider: AIProvider
    var model: String
    var status: AIExecutionStatus
    var startedAt: Date
    var endedAt: Date?
    var activeSeconds: Int
    var elapsedSeconds: Int
    var waitingHumanSeconds: Int
    var tokenInput: Int
    var tokenOutput: Int
    var estimatedCost: Double
    var toolCallCount: Int
    var filesChanged: Int
    var resultSummary: String?
    var errorMessage: String?
    var logs: [AIExecutionLog]
    var currentStep: String?
    var updatedAt: Date

    init(id: String, taskId: String, provider: AIProvider, model: String, status: AIExecutionStatus,
         startedAt: Date, endedAt: Date? = nil, activeSeconds: Int, elapsedSeconds: Int,
         waitingHumanSeconds: Int, tokenInput: Int, tokenOutput: Int, estimatedCost: Double,
         toolCallCount: Int, filesChanged: Int, resultSummary: String? = nil, errorMessage: String? = nil,
         logs: [AIExecutionLog], currentStep: String? = nil, updatedAt: Date) {
        self.id = id; self.taskId = taskId; self.provider = provider; self.model = model; self.status = status
        self.startedAt = startedAt; self.endedAt = endedAt; self.activeSeconds = activeSeconds
        self.elapsedSeconds = elapsedSeconds; self.waitingHumanSeconds = waitingHumanSeconds
        self.tokenInput = tokenInput; self.tokenOutput = tokenOutput; self.estimatedCost = estimatedCost
        self.toolCallCount = toolCallCount; self.filesChanged = filesChanged; self.resultSummary = resultSummary
        self.errorMessage = errorMessage; self.logs = logs; self.currentStep = currentStep; self.updatedAt = updatedAt
    }

    // Tolerate `logs: null` from the server.
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(String.self, forKey: .id)
        taskId = try c.decode(String.self, forKey: .taskId)
        provider = try c.decode(AIProvider.self, forKey: .provider)
        model = try c.decodeIfPresent(String.self, forKey: .model) ?? ""
        status = try c.decode(AIExecutionStatus.self, forKey: .status)
        startedAt = try c.decode(Date.self, forKey: .startedAt)
        endedAt = try c.decodeIfPresent(Date.self, forKey: .endedAt)
        activeSeconds = try c.decodeIfPresent(Int.self, forKey: .activeSeconds) ?? 0
        elapsedSeconds = try c.decodeIfPresent(Int.self, forKey: .elapsedSeconds) ?? 0
        waitingHumanSeconds = try c.decodeIfPresent(Int.self, forKey: .waitingHumanSeconds) ?? 0
        tokenInput = try c.decodeIfPresent(Int.self, forKey: .tokenInput) ?? 0
        tokenOutput = try c.decodeIfPresent(Int.self, forKey: .tokenOutput) ?? 0
        estimatedCost = try c.decodeIfPresent(Double.self, forKey: .estimatedCost) ?? 0
        toolCallCount = try c.decodeIfPresent(Int.self, forKey: .toolCallCount) ?? 0
        filesChanged = try c.decodeIfPresent(Int.self, forKey: .filesChanged) ?? 0
        resultSummary = try c.decodeIfPresent(String.self, forKey: .resultSummary)
        errorMessage = try c.decodeIfPresent(String.self, forKey: .errorMessage)
        logs = try c.decodeIfPresent([AIExecutionLog].self, forKey: .logs) ?? []
        currentStep = try c.decodeIfPresent(String.self, forKey: .currentStep)
        updatedAt = try c.decodeIfPresent(Date.self, forKey: .updatedAt) ?? startedAt
    }
}

struct DailyStats: Codable, Equatable {
    var date: String
    var humanSeconds: Int
    var aiActiveSeconds: Int
    var waitingSeconds: Int
    var deepWorkSeconds: Int
    var interruptionCount: Int
    var reworkSeconds: Int
    var completedTasks: Int
    var plannedMinutes: Int
    var actualHumanMinutes: Int

    static let zero = DailyStats(date: "aggregate", humanSeconds: 0, aiActiveSeconds: 0, waitingSeconds: 0,
                                 deepWorkSeconds: 0, interruptionCount: 0, reworkSeconds: 0, completedTasks: 0,
                                 plannedMinutes: 0, actualHumanMinutes: 0)
}

struct EfficiencyExperiment: Codable, Identifiable, Equatable {
    var id: String
    var title: String
    var description: String
    var startDate: Date
    var durationDays: Int
    var status: ExperimentStatus
    var beforeMetric: String
    var afterMetric: String?
    var effective: Bool?
    var updatedAt: Date
}

struct UserSettings: Codable, Equatable {
    var name: String
    var weeklyTimeGoalHours: Int
    var workStartHour: Int
    var workEndHour: Int
    var defaultFocusMinutes: Int
    var streakDays: Int
    var theme: ThemeName
    var updatedAt: Date

    static func defaults(now: Date = Date()) -> UserSettings {
        UserSettings(name: "刻迹用户", weeklyTimeGoalHours: 40, workStartHour: 9, workEndHour: 18,
                     defaultFocusMinutes: 45, streakDays: 0, theme: .claude, updatedAt: now)
    }

    init(name: String, weeklyTimeGoalHours: Int, workStartHour: Int, workEndHour: Int,
         defaultFocusMinutes: Int, streakDays: Int, theme: ThemeName, updatedAt: Date) {
        self.name = name; self.weeklyTimeGoalHours = weeklyTimeGoalHours; self.workStartHour = workStartHour
        self.workEndHour = workEndHour; self.defaultFocusMinutes = defaultFocusMinutes
        self.streakDays = streakDays; self.theme = theme; self.updatedAt = updatedAt
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        let d = UserSettings.defaults()
        name = try c.decodeIfPresent(String.self, forKey: .name) ?? d.name
        weeklyTimeGoalHours = try c.decodeIfPresent(Int.self, forKey: .weeklyTimeGoalHours) ?? d.weeklyTimeGoalHours
        workStartHour = try c.decodeIfPresent(Int.self, forKey: .workStartHour) ?? d.workStartHour
        workEndHour = try c.decodeIfPresent(Int.self, forKey: .workEndHour) ?? d.workEndHour
        defaultFocusMinutes = try c.decodeIfPresent(Int.self, forKey: .defaultFocusMinutes) ?? d.defaultFocusMinutes
        streakDays = try c.decodeIfPresent(Int.self, forKey: .streakDays) ?? d.streakDays
        theme = (try? c.decodeIfPresent(ThemeName.self, forKey: .theme)) ?? d.theme
        updatedAt = try c.decodeIfPresent(Date.self, forKey: .updatedAt) ?? .distantPast
    }
}

struct AIToolConnection: Codable, Identifiable, Equatable {
    var provider: AIProvider
    var name: String
    var connected: Bool
    var lastSync: Date?

    var id: String { provider.rawValue }

    static let defaults: [AIToolConnection] = [
        AIToolConnection(provider: .claude, name: "Claude Code", connected: false),
        AIToolConnection(provider: .codex, name: "Codex CLI", connected: false),
        AIToolConnection(provider: .chatgpt, name: "ChatGPT", connected: false),
        AIToolConnection(provider: .gemini, name: "Gemini", connected: false),
    ]
}

struct ActiveFocus: Codable, Equatable {
    var taskId: String
    var startedAt: Date
    var accumulatedSeconds: Int
}
