import Foundation

/// 首页「报告」的全部内容：只用手机上已有的数据算出，不依赖服务端评分。
/// 1. AI 今天替你干了什么；2. 额度用得值不值；3. 明天可以交给 AI 的。
/// 纯值类型，便于单测；视图只负责渲染和发起派发。
struct DailyBrief: Equatable {
    enum WorkStatus: Equatable {
        case completed, awaitingReview, failed, inProgress
    }

    struct WorkCounts: Equatable {
        var completed = 0
        var awaitingReview = 0
        var failed = 0
        var inProgress = 0
    }

    struct WorkItem: Identifiable, Equatable {
        let id: String
        let taskId: String
        let planId: String?
        let title: String
        let status: WorkStatus
        let statusLabel: String
        let summary: String?
        let tool: String?
        let aiActiveMinutes: Int
        let at: Date
    }

    enum HintKind: Equatable { case waste, exhausted, unknown }

    struct WindowLine: Equatable {
        let label: String
        let remaining: String
        let reset: String?
    }

    struct QuotaRow: Identifiable, Equatable {
        let id: String
        let name: String
        let tier: String
        let source: String
        let windows: [WindowLine]
        let hint: String?
        let hintKind: HintKind?
    }

    struct Candidate: Identifiable, Equatable {
        var id: String { taskId }
        let taskId: String
        let title: String
        let provider: AIProvider?
        /// 可直接派发的 Plan；nil 表示点「安排」时再去准备。
        let planId: String?
        /// 计划执行时刻（对应额度池下一次重置 + 2 分钟）；nil 表示重置时间未知。
        let notBefore: Date?
        let scheduleText: String?
    }

    enum DispatchTarget: Equatable {
        case ready(runnerID: String, workspaceID: String, toolID: String)
        case unavailable(String)
    }

    static let maxItems = 10
    static let maxCandidates = 8
    static let unknownQuotaText = "额度未知（电脑离线或未上报）"

    var counts = WorkCounts()
    var items: [WorkItem] = []
    var quotaRows: [QuotaRow] = []
    var candidates: [Candidate] = []
    var nextReset: Date?

    var isWorkEmpty: Bool { items.isEmpty }

    static func make(now: Date, calendar: Calendar = Format.calendar, tasks: [TaskItem], plans: [PlanItem],
                     jobs: [String: RemoteJob], executions: [AIExecution], sessions: [TimeSession],
                     quota: AccountQuota?, scope: ReportScope = .all) -> DailyBrief {
        let scoped: [TaskItem]
        switch scope {
        case .all: scoped = tasks
        case .project(let id): scoped = tasks.filter { $0.projectId == id }
        }
        let tasksByID = Dictionary(scoped.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        let inScope: (String) -> Bool = { id in
            if case .all = scope { return true }
            return tasksByID[id] != nil
        }
        let day = calendar.dateInterval(of: .day, for: now) ?? DateInterval(start: now, duration: 86400)

        var brief = DailyBrief()
        let work = workItems(now: now, day: day, tasks: tasksByID, plans: plans, jobs: jobs,
                             executions: executions, sessions: sessions, inScope: inScope)
        for item in work {
            switch item.status {
            case .completed: brief.counts.completed += 1
            case .awaitingReview: brief.counts.awaitingReview += 1
            case .failed: brief.counts.failed += 1
            case .inProgress: brief.counts.inProgress += 1
            }
        }
        brief.items = Array(work.prefix(maxItems))

        let pools = quota?.pools ?? []
        brief.quotaRows = pools.map { quotaRow($0, now: now) }
        brief.nextReset = pools.flatMap(\.windows).compactMap(\.resetAt).filter { $0 > now }.min()
        brief.candidates = candidates(now: now, tasks: scoped, plans: plans, jobs: jobs, pools: pools,
                                      fallbackReset: brief.nextReset)
        return brief
    }

    // MARK: - AI 今天替你干了什么

    private static func workItems(now: Date, day: DateInterval, tasks: [String: TaskItem], plans: [PlanItem],
                                  jobs: [String: RemoteJob], executions: [AIExecution], sessions: [TimeSession],
                                  inScope: (String) -> Bool) -> [WorkItem] {
        let plansByID = Dictionary(plans.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        let executionByJob = Dictionary(executions.compactMap { e in e.remoteJobId.map { ($0, e) } },
                                        uniquingKeysWith: { first, _ in first })
        let isToday: (Date) -> Bool = { day.contains($0) }
        var items: [WorkItem] = []

        for (key, job) in jobs where inScope(job.taskId) {
            let planId = job.planId ?? (plansByID[key] != nil ? key : nil)
            let plan = planId.flatMap { plansByID[$0] }
            let status: WorkStatus
            let label: String
            if plan?.status == .accepted {
                status = .completed; label = PlanState.accepted.label
            } else {
                switch job.status {
                case .cancelled: continue
                case .completed: status = .completed; label = job.status.label
                case .awaitingReview: status = .awaitingReview; label = PlanState.awaitingReview.label
                case .failed, .expired, .interrupted: status = .failed; label = PlanState.failed.label
                case .queued, .leased, .running, .waitingQuota, .waitingLocalAuth, .waitingInput:
                    status = .inProgress; label = job.displayLabel(now: now)
                }
            }
            guard isToday(job.updatedAt) || status == .awaitingReview || status == .inProgress else { continue }
            let task = tasks[job.taskId]
            let tool = executionByJob[job.id]?.provider.label ?? task?.aiProvider?.label
            items.append(WorkItem(id: "job-" + job.id, taskId: job.taskId, planId: planId,
                                  title: task?.title ?? "任务", status: status, statusLabel: label,
                                  summary: firstLine(job.resultSummary), tool: tool,
                                  aiActiveMinutes: aiMinutes(taskId: job.taskId, sessions: sessions, day: day, now: now),
                                  at: job.updatedAt))
        }

        let jobIDs = Set(jobs.values.map(\.id))
        for execution in executions where inScope(execution.taskId) {
            if let linked = execution.remoteJobId, jobIDs.contains(linked) { continue }
            let task = tasks[execution.taskId]
            let status: WorkStatus
            let label: String
            switch execution.status {
            case .cancelled: continue
            case .completed:
                if task?.status == .waitingHuman { status = .awaitingReview; label = PlanState.awaitingReview.label }
                else { status = .completed; label = execution.status.label }
            case .failed: status = .failed; label = PlanState.failed.label
            case .queued, .running, .waitingAuth, .waitingInput: status = .inProgress; label = execution.status.label
            }
            let at = execution.endedAt ?? execution.startedAt
            guard isToday(at) || status == .awaitingReview || status == .inProgress else { continue }
            let summary = firstLine(execution.resultSummary) ?? (status == .failed ? firstLine(execution.errorMessage) : nil)
            let planId = plans.filter { $0.taskId == execution.taskId && !$0.id.hasPrefix("draft-") }
                .sorted { ($0.priority, $0.createdAt) < ($1.priority, $1.createdAt) }.first?.id
            items.append(WorkItem(id: "exec-" + execution.id, taskId: execution.taskId, planId: planId,
                                  title: task?.title ?? "任务", status: status, statusLabel: label,
                                  summary: summary, tool: execution.provider.label,
                                  aiActiveMinutes: aiMinutes(taskId: execution.taskId, sessions: sessions, day: day, now: now),
                                  at: at))
        }
        return items.sorted { ($0.at, $0.id) > ($1.at, $1.id) }
    }

    private static func firstLine(_ text: String?) -> String? {
        text?.split(whereSeparator: \.isNewline)
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .first { !$0.isEmpty }
    }

    /// 当天（按本地日界裁剪）该任务 ai_active 会话的分钟数；进行中的会话算到现在。
    private static func aiMinutes(taskId: String, sessions: [TimeSession], day: DateInterval, now: Date) -> Int {
        let dayEnd = min(day.end, now)
        let seconds = sessions.reduce(0.0) { total, s in
            guard s.taskId == taskId, s.type == .aiActive else { return total }
            let start = max(s.startedAt, day.start)
            let end = min(s.endedAt ?? now, dayEnd)
            return total + max(0, end.timeIntervalSince(start))
        }
        return Int((seconds / 60).rounded())
    }

    // MARK: - 额度用得值不值

    private static func quotaRow(_ pool: AccountQuotaPool, now: Date) -> QuotaRow {
        let card = ToolQuotaCard(pool: pool, now: now)
        let ordered = pool.windows.sorted { $0.isMainLimit(of: pool.provider) && !$1.isMainLimit(of: pool.provider) }
        var shown = [ordered.first { $0.bucket == .weekly }, ordered.first { $0.bucket == .short }].compactMap { $0 }
        if shown.isEmpty, let first = ordered.first { shown = [first] }
        let lines = shown.map { window in
            WindowLine(label: window.scopeLabel,
                       remaining: quotaLabel(remaining: window.remainingPercent, fresh: window.isFresh(now: now)),
                       reset: window.resetAt.map { Format.resetMoment($0, now: now) })
        }

        let known = pool.windows.filter { $0.isFresh(now: now) && $0.remainingPercent != nil }
        let hint: String?
        let kind: HintKind?
        let exhausted = known.filter { ($0.remainingPercent ?? 100) < 0.5 }
        if known.isEmpty {
            hint = unknownQuotaText; kind = .unknown
        } else if !exhausted.isEmpty || pool.availability == "blocked" {
            let reset = (exhausted.isEmpty ? known : exhausted).compactMap(\.resetAt).filter { $0 > now }.max()
            hint = reset.map { "已用尽，\(Format.resetMoment($0, now: now)) 重置" } ?? "已用尽，重置时间未知"
            kind = .exhausted
        } else if let waste = shown.first(where: { window in
            guard window.isFresh(now: now), let remaining = window.remainingPercent, remaining >= 40,
                  let reset = window.resetAt else { return false }
            return reset > now && reset.timeIntervalSince(now) <= 86400
        }), let remaining = waste.remainingPercent, let reset = waste.resetAt {
            hint = "还剩 \(Int(remaining.rounded()))%，\(Format.resetMoment(reset, now: now)) 重置——现在派一批任务更划算"
            kind = .waste
        } else {
            hint = nil; kind = nil
        }
        return QuotaRow(id: pool.poolId, name: card.name, tier: card.tier, source: card.source,
                        windows: lines, hint: hint, hintKind: kind)
    }

    /// 额度池下一次「有用」的重置：有窗口已用尽时要等它（取最晚的一个），否则取最早的重置。
    static func usefulReset(of pool: AccountQuotaPool, now: Date) -> Date? {
        let upcoming = pool.windows.filter { ($0.resetAt ?? .distantPast) > now }
        let exhausted = upcoming.filter { $0.isFresh(now: now) && ($0.remainingPercent ?? 100) < 0.5 }
        if !exhausted.isEmpty { return exhausted.compactMap(\.resetAt).max() }
        return upcoming.compactMap(\.resetAt).min()
    }

    // MARK: - 明天可以交给 AI 的

    private static let activePlanStates: Set<PlanState> = [.queued, .running, .waitingQuota, .waitingLocalAuth,
                                                           .waitingInput, .awaitingReview]
    private static let activeJobStates: Set<RemoteJobStatus> = [.queued, .leased, .running, .waitingQuota,
                                                                .waitingLocalAuth, .waitingInput, .awaitingReview]
    private static let excludedTaskStates: Set<TaskStatus> = [.completed, .cancelled, .aiQueued, .aiRunning, .waitingHuman]

    private static func candidates(now: Date, tasks: [TaskItem], plans: [PlanItem], jobs: [String: RemoteJob],
                                   pools: [AccountQuotaPool], fallbackReset: Date?) -> [Candidate] {
        let busyTasks = Set(jobs.values.filter { activeJobStates.contains($0.status) }.map(\.taskId))
            .union(plans.filter { activePlanStates.contains($0.status) }.map(\.taskId))
        let rank: [TaskPriority: Int] = [.urgent: 0, .high: 1, .medium: 2, .low: 3]
        return tasks
            .filter { ($0.executorType == .ai || $0.executorType == .collaboration)
                && !excludedTaskStates.contains($0.status) && !busyTasks.contains($0.id) }
            .sorted { (rank[$0.priority] ?? 9, $0.createdAt, $0.id) < (rank[$1.priority] ?? 9, $1.createdAt, $1.id) }
            .prefix(maxCandidates)
            .map { task in
                let planId = plans.filter { $0.taskId == task.id && !$0.id.hasPrefix("draft-") }
                    .sorted { ($0.priority, $0.createdAt) < ($1.priority, $1.createdAt) }
                    .first { canDispatchPlan($0, allPlans: plans) }?.id
                let pool = task.aiProvider.flatMap { provider in pools.first { $0.provider == provider.rawValue } }
                let reset = pool.flatMap { usefulReset(of: $0, now: now) } ?? fallbackReset
                let start = scheduledStart(after: reset, now: now)
                return Candidate(taskId: task.id, title: task.title, provider: task.aiProvider, planId: planId,
                                 notBefore: start, scheduleText: start.map { Format.resetMoment($0, now: now) })
            }
    }

    /// 重置后 2 分钟再开始；限制在 [现在 + 2 分钟, 现在 + 30 天]，与派发面板的可选范围一致。
    static func scheduledStart(after reset: Date?, now: Date) -> Date? {
        guard let reset else { return nil }
        let lower = now.addingTimeInterval(120)
        let upper = now.addingTimeInterval(30 * 86400)
        return min(max(reset.addingTimeInterval(120), lower), upper)
    }

    /// 第一台在线电脑上第一个启用的工作区，以及与任务 AI 匹配的可用工具。
    static func dispatchTarget(provider: AIProvider?, runners: [RunnerInventory]) -> DispatchTarget {
        let online = runners.online
        guard !online.isEmpty else { return .unavailable("没有在线电脑") }
        var sawWorkspace = false
        for inventory in online {
            guard let workspace = inventory.workspaces.first(where: \.enabled) else { continue }
            sawWorkspace = true
            if let tool = inventory.tools.first(where: { $0.status == "available" && (provider == nil || $0.provider == provider) }) {
                return .ready(runnerID: inventory.runner.id, workspaceID: workspace.id, toolID: tool.id)
            }
        }
        guard sawWorkspace else { return .unavailable("电脑上没有启用的工作区") }
        return .unavailable("电脑上没有可用的 \(provider?.label ?? "AI 工具")")
    }
}
