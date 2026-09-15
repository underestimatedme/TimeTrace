import Foundation

/// Mirrors spec §3.2 `state`. Arrays tolerate `null` from the server.
struct StateSnapshot: Codable, Equatable {
    var projects: [Project] = []
    var goals: [Goal] = []
    var tasks: [TaskItem] = []
    var timeSessions: [TimeSession] = []
    var aiExecutions: [AIExecution] = []
    var experiments: [EfficiencyExperiment] = []
    var plans: [PlanItem] = []
    var settings: UserSettings = .defaults()
    var aiTools: [AIToolConnection] = AIToolConnection.defaults
    var activeFocus: ActiveFocus?
    /// 1 = pre-Plan snapshots; 2 = Plans present. Absent decodes as 1.
    var schemaVersion: Int = 1

    init() {}

    init(projects: [Project], goals: [Goal], tasks: [TaskItem], timeSessions: [TimeSession],
         aiExecutions: [AIExecution], experiments: [EfficiencyExperiment], plans: [PlanItem] = [],
         settings: UserSettings, aiTools: [AIToolConnection], activeFocus: ActiveFocus?,
         schemaVersion: Int = 2) {
        self.projects = projects; self.goals = goals; self.tasks = tasks; self.timeSessions = timeSessions
        self.aiExecutions = aiExecutions; self.experiments = experiments; self.plans = plans
        self.settings = settings; self.aiTools = aiTools; self.activeFocus = activeFocus
        self.schemaVersion = schemaVersion
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        projects = try c.decodeIfPresent([Project].self, forKey: .projects) ?? []
        goals = try c.decodeIfPresent([Goal].self, forKey: .goals) ?? []
        tasks = try c.decodeIfPresent([TaskItem].self, forKey: .tasks) ?? []
        timeSessions = try c.decodeIfPresent([TimeSession].self, forKey: .timeSessions) ?? []
        aiExecutions = try c.decodeIfPresent([AIExecution].self, forKey: .aiExecutions) ?? []
        experiments = try c.decodeIfPresent([EfficiencyExperiment].self, forKey: .experiments) ?? []
        // Old snapshots have no plans/schema_version: default to empty + v1 so a
        // pre-Plan local cache still loads, then migration fills defaults.
        plans = try c.decodeIfPresent([PlanItem].self, forKey: .plans) ?? []
        settings = try c.decodeIfPresent(UserSettings.self, forKey: .settings) ?? .defaults()
        aiTools = try c.decodeIfPresent([AIToolConnection].self, forKey: .aiTools) ?? AIToolConnection.defaults
        activeFocus = try c.decodeIfPresent(ActiveFocus.self, forKey: .activeFocus)
        schemaVersion = try c.decodeIfPresent(Int.self, forKey: .schemaVersion) ?? 1
    }
}

/// Entity buckets that take part in upserts/deletes (spec §3.3).
enum SyncEntity: String, Codable, CaseIterable, Hashable {
    case projects, goals, tasks
    case timeSessions = "time_sessions"
    case aiExecutions = "ai_executions"
    case experiments
}
