import Foundation

/// A private daily report from Valley's GET/POST /reports. Human input, AI
/// active time and waiting time are separate; a total score is present only when
/// coverage is high enough. Estimated API-equivalent value and actual new spend
/// are distinct fields.
struct DailyReport: Codable, Equatable {
    var localDate: String
    var revision: Int
    var status: String            // draft / empty
    var humanSeconds: Int?
    var aiSeconds: Int?
    var waitingSeconds: Int?
    var coverage: Double
    var totalScore: Double?
    var evidenceIds: [String]
    var baselineVersion: String
    var estimatedValueMinor: Int?
    var actualSpendMinor: Int?
    var generatedAt: Date?
    var breakdown: ReportPhaseFacts?

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        localDate = try c.decodeIfPresent(String.self, forKey: .localDate) ?? ""
        revision = try c.decodeIfPresent(Int.self, forKey: .revision) ?? 0
        status = try c.decodeIfPresent(String.self, forKey: .status) ?? "empty"
        humanSeconds = try c.decodeIfPresent(Int.self, forKey: .humanSeconds)
        aiSeconds = try c.decodeIfPresent(Int.self, forKey: .aiSeconds)
        waitingSeconds = try c.decodeIfPresent(Int.self, forKey: .waitingSeconds)
        coverage = try c.decodeIfPresent(Double.self, forKey: .coverage) ?? 0
        totalScore = try c.decodeIfPresent(Double.self, forKey: .totalScore)
        evidenceIds = try c.decodeIfPresent([String].self, forKey: .evidenceIds) ?? []
        baselineVersion = try c.decodeIfPresent(String.self, forKey: .baselineVersion) ?? ""
        estimatedValueMinor = try c.decodeIfPresent(Int.self, forKey: .estimatedValueMinor)
        actualSpendMinor = try c.decodeIfPresent(Int.self, forKey: .actualSpendMinor)
        generatedAt = try? c.decodeIfPresent(Date.self, forKey: .generatedAt)
        breakdown = try c.decodeIfPresent(ReportPhaseFacts.self, forKey: .breakdown)
    }

    var hasTotal: Bool { coverage >= 0.80 && coverage <= 1 && totalScore?.isFinite == true }
    var isEmpty: Bool { status == "empty" || revision == 0 }
}

struct ReportPhaseFact: Codable, Equatable, Identifiable {
    var id: String
    var taskId: String
    var track: TimelineTrack
    var state: String
    var start: Date
    var end: Date
}

struct ReportPhaseFacts: Codable, Equatable {
    var zone: String
    var facts: [ReportPhaseFact]
    var evidenceCoverage: Double
}

/// Plans belonging to a report scope; a project report never leaks another project's plans.
func plansInScope(_ scope: ReportScope, tasks: [TaskItem], plans: [PlanItem]) -> [PlanItem] {
    switch scope {
    case .all:
        return plans
    case .project(let projectId):
        let taskIds = Set(tasks.filter { $0.projectId == projectId }.map(\.id))
        return plans.filter { taskIds.contains($0.taskId) }
    }
}

/// 报告的「交付」视角：按验收事实记录的 ChangeLog（design/src/review 的报告页）。
/// 只统计真实存在的 Plan —— 本地草稿（`draft-` 前缀）不是交付，不计入。
struct ReportChangeLog: Equatable {
    struct Row: Equatable, Identifiable {
        var id: String
        var title: String
        var status: PlanState
        var isAccepted: Bool { status == .accepted }
    }

    var rows: [Row]

    var acceptedCount: Int { rows.filter(\.isAccepted).count }
    var totalCount: Int { rows.count }
    var isEmpty: Bool { rows.isEmpty }

    /// 「N 个 Plan 已验收」——没有 Plan 时显示 0，不编造交付量。
    var deliveryText: String { "\(acceptedCount) 个 Plan 已验收" }

    /// 项目卡片上的进度：「N / M Plan 已验收」。
    var acceptanceRatioText: String { "\(acceptedCount) / \(totalCount) Plan 已验收" }

    /// 设计稿的「下一步建议」，按当前 Plan 状态给出，不编造进展。
    var nextStepAdvice: String {
        if rows.contains(where: { $0.status == .awaitingReview }) { return "先确认待验收的结果，再安排后续工作。" }
        if rows.contains(where: { $0.status == .waitingQuota }) { return "等待工具额度核验，同时安排可并行的人工工作。" }
        if rows.isEmpty { return "先为项目创建任务与 Plan。" }
        return "检查剩余计划与已验收成果，安排下一步。"
    }

    init(plans: [PlanItem], tasks: [TaskItem], scope: ReportScope) {
        rows = plansInScope(scope, tasks: tasks, plans: plans)
            .filter { !$0.id.hasPrefix("draft-") }
            .sorted { ($0.updatedAt, $0.id) > ($1.updatedAt, $1.id) }
            .map { Row(id: $0.id, title: $0.title, status: $0.status) }
    }
}

enum ReportMeasurement: Equatable {
    case empty, unknown, seconds(Int)
    var text: String {
        switch self { case .empty: return "无记录"; case .unknown: return "未测量"; case .seconds(let seconds): return Format.duration(seconds) }
    }
}

/// The screen and export share this projection, including project filtering.
struct ReportPresentation {
    /// 设计稿：样本不足不显示假总分。
    static let insufficientSampleText = "样本不足，暂不计算"

    var human: ReportMeasurement
    var ai: ReportMeasurement
    var waiting: ReportMeasurement
    var evidenceCoverage: Double

    init(facts: [ReportPhaseFact], taskIds: Set<String>? = nil) {
        var seen = Set<String>()
        let selected = facts.filter { (taskIds == nil || taskIds!.contains($0.taskId)) && seen.insert($0.id).inserted }
        func measurement(_ track: TimelineTrack) -> ReportMeasurement {
            let rows = selected.filter { $0.track == track }
            guard !rows.isEmpty else { return .empty }
            guard rows.allSatisfy({ $0.state == "known" }) else { return .unknown }
            let intervals = rows.map { TrackInterval(id: $0.id, start: $0.start, end: $0.end, track: $0.track) }
            return .seconds(Int(track == .human ? unionSeconds(intervals, track: track) : activeSeconds(intervals, track: track)))
        }
        human = measurement(.human); ai = measurement(.ai); waiting = measurement(.waiting)
        evidenceCoverage = selected.isEmpty ? 0 : Double(selected.filter { $0.state == "known" }.count) / Double(selected.count)
    }

    init(sessions: [TimeSession], day: String, timeZone: TimeZone) {
        guard let bounds = reportDayInterval(day, timeZone: timeZone) else { self.init(facts: []); return }
        let facts: [ReportPhaseFact] = sessions.compactMap { s in
            let track: TimelineTrack
            if Stats.humanTypes.contains(s.type) { track = .human }
            else if Stats.aiTypes.contains(s.type) { track = .ai }
            else if Stats.waitingTypes.contains(s.type) { track = .waiting }
            else { return nil }
            let end = s.endedAt ?? bounds.end
            let midnightZero = end == s.startedAt && end == bounds.start
            guard s.startedAt < bounds.end, end > bounds.start || midnightZero else { return nil }
            return ReportPhaseFact(id: s.id, taskId: s.taskId, track: track,
                                   state: s.endedAt != nil && end >= s.startedAt ? "known" : "unknown",
                                   start: max(s.startedAt, bounds.start), end: min(end, bounds.end))
        }
        self.init(facts: facts)
    }
}
