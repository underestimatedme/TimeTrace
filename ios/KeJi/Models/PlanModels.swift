import Foundation
import CryptoKit

/// Execution status of a Plan, projected by the server. Snake_case values match
/// the Valley contract; an unrecognized value decodes to `.unknown` so one new
/// server state never fails the whole snapshot.
enum PlanState: String, Codable, CaseIterable {
    case draft, ready, queued, running
    case waitingQuota = "waiting_quota"
    case waitingLocalAuth = "waiting_local_auth"
    case waitingInput = "waiting_input"
    case awaitingReview = "awaiting_review"
    case accepted, failed, cancelled
    case unknown

    init(from decoder: Decoder) throws {
        let raw = try decoder.singleValueContainer().decode(String.self)
        self = PlanState(rawValue: raw) ?? .unknown
    }
}

/// Per-Plan execution policy. Mirrors the workspace API `execution_policy`.
struct PlanExecutionPolicy: Codable, Equatable {
    var mode: String
    var preferredProfileId: String?
    var allowAutoResume: Bool
    var maxAdditionalSpendMinor: Int

    static let balanced = PlanExecutionPolicy(mode: "balanced", preferredProfileId: nil,
                                              allowAutoResume: true, maxAdditionalSpendMinor: 0)
}

/// The unit of AI/human execution beneath a Task (项目 → 任务 → Plan).
struct PlanItem: Codable, Identifiable, Equatable {
    var id: String
    var taskId: String
    var revision: Int
    var title: String
    var priority: Int
    var status: PlanState
    var criteria: [String]
    var dependsOn: [String]
    var estimatedHumanMinutes: Int
    var estimatedAiMinutes: Int
    var workWeight: Double
    var risk: Int
    var executionPolicy: PlanExecutionPolicy
    var createdAt: Date
    var updatedAt: Date

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(String.self, forKey: .id)
        taskId = try c.decode(String.self, forKey: .taskId)
        revision = try c.decodeIfPresent(Int.self, forKey: .revision) ?? 1
        title = try c.decodeIfPresent(String.self, forKey: .title) ?? ""
        priority = try c.decodeIfPresent(Int.self, forKey: .priority) ?? 2
        status = try c.decodeIfPresent(PlanState.self, forKey: .status) ?? .ready
        criteria = try c.decodeIfPresent([String].self, forKey: .criteria) ?? []
        dependsOn = try c.decodeIfPresent([String].self, forKey: .dependsOn) ?? []
        estimatedHumanMinutes = try c.decodeIfPresent(Int.self, forKey: .estimatedHumanMinutes) ?? 0
        estimatedAiMinutes = try c.decodeIfPresent(Int.self, forKey: .estimatedAiMinutes) ?? 0
        workWeight = try c.decodeIfPresent(Double.self, forKey: .workWeight) ?? 1
        risk = try c.decodeIfPresent(Int.self, forKey: .risk) ?? 2
        executionPolicy = try c.decodeIfPresent(PlanExecutionPolicy.self, forKey: .executionPolicy) ?? .balanced
        createdAt = try c.decodeIfPresent(Date.self, forKey: .createdAt) ?? Date(timeIntervalSince1970: 0)
        updatedAt = try c.decodeIfPresent(Date.self, forKey: .updatedAt) ?? createdAt
    }

    init(id: String, taskId: String, revision: Int, title: String, priority: Int, status: PlanState,
         criteria: [String], dependsOn: [String], estimatedHumanMinutes: Int, estimatedAiMinutes: Int,
         workWeight: Double, risk: Int, executionPolicy: PlanExecutionPolicy, createdAt: Date, updatedAt: Date) {
        self.id = id; self.taskId = taskId; self.revision = revision; self.title = title
        self.priority = priority; self.status = status; self.criteria = criteria; self.dependsOn = dependsOn
        self.estimatedHumanMinutes = estimatedHumanMinutes; self.estimatedAiMinutes = estimatedAiMinutes
        self.workWeight = workWeight; self.risk = risk; self.executionPolicy = executionPolicy
        self.createdAt = createdAt; self.updatedAt = updatedAt
    }
}

/// Deterministic default Plan id for a legacy Task. Must match Valley V1's
/// `timetrace:default-plan:v1:` SHA256 namespace so client and server agree.
func defaultPlanID(taskID: String) -> String {
    let bytes = Data("timetrace:default-plan:v1:\(taskID)".utf8)
    return SHA256.hash(data: bytes).prefix(16).map { String(format: "%02x", $0) }.joined()
}

/// Maps a legacy Task to its default Plan (used for local migration until the
/// server snapshot carries plans).
func defaultPlan(for task: TaskItem, now: Date = Date()) -> PlanItem {
    let priority: Int
    switch task.priority.rawValue {
    case "urgent", "critical", "p0": priority = 0
    case "high", "p1": priority = 1
    case "low", "p3": priority = 3
    default: priority = 2
    }
    let status: PlanState = task.completedAt != nil ? .accepted : .ready
    return PlanItem(id: defaultPlanID(taskID: task.id), taskId: task.id, revision: 1, title: task.title,
                    priority: priority, status: status, criteria: [], dependsOn: [],
                    estimatedHumanMinutes: task.estimatedMinutes, estimatedAiMinutes: 0, workWeight: 1, risk: 2,
                    executionPolicy: .balanced, createdAt: task.createdAt, updatedAt: now)
}

/// Idempotently ensures every Task has a default Plan and bumps the snapshot to
/// schema version 2. Existing plans (by id) are preserved unchanged.
func migrateDefaultPlans(_ snapshot: StateSnapshot, now: Date = Date()) -> StateSnapshot {
    var result = snapshot
    var existing = Set(snapshot.plans.map { $0.id })
    for task in snapshot.tasks {
        let pid = defaultPlanID(taskID: task.id)
        if !existing.contains(pid) {
            result.plans.append(defaultPlan(for: task, now: now))
            existing.insert(pid)
        }
    }
    result.schemaVersion = max(result.schemaVersion, 2)
    return result
}
