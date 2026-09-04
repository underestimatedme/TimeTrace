import Foundation

/// Mirrors spec §3.2 `state`. Arrays tolerate `null` from the server.
struct StateSnapshot: Codable, Equatable {
    var projects: [Project] = []
    var goals: [Goal] = []
    var tasks: [TaskItem] = []
    var timeSessions: [TimeSession] = []
    var aiExecutions: [AIExecution] = []
    var experiments: [EfficiencyExperiment] = []
    var settings: UserSettings = .defaults()
    var aiTools: [AIToolConnection] = AIToolConnection.defaults
    var activeFocus: ActiveFocus?

    init() {}

    init(projects: [Project], goals: [Goal], tasks: [TaskItem], timeSessions: [TimeSession],
         aiExecutions: [AIExecution], experiments: [EfficiencyExperiment], settings: UserSettings,
         aiTools: [AIToolConnection], activeFocus: ActiveFocus?) {
        self.projects = projects; self.goals = goals; self.tasks = tasks; self.timeSessions = timeSessions
        self.aiExecutions = aiExecutions; self.experiments = experiments; self.settings = settings
        self.aiTools = aiTools; self.activeFocus = activeFocus
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        projects = try c.decodeIfPresent([Project].self, forKey: .projects) ?? []
        goals = try c.decodeIfPresent([Goal].self, forKey: .goals) ?? []
        tasks = try c.decodeIfPresent([TaskItem].self, forKey: .tasks) ?? []
        timeSessions = try c.decodeIfPresent([TimeSession].self, forKey: .timeSessions) ?? []
        aiExecutions = try c.decodeIfPresent([AIExecution].self, forKey: .aiExecutions) ?? []
        experiments = try c.decodeIfPresent([EfficiencyExperiment].self, forKey: .experiments) ?? []
        settings = try c.decodeIfPresent(UserSettings.self, forKey: .settings) ?? .defaults()
        aiTools = try c.decodeIfPresent([AIToolConnection].self, forKey: .aiTools) ?? AIToolConnection.defaults
        activeFocus = try c.decodeIfPresent(ActiveFocus.self, forKey: .activeFocus)
    }
}

/// Entity buckets that take part in upserts/deletes (spec §3.3).
enum SyncEntity: String, Codable, CaseIterable, Hashable {
    case projects, goals, tasks
    case timeSessions = "time_sessions"
    case aiExecutions = "ai_executions"
    case experiments
}
