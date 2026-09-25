import XCTest
@testable import KeJi

/// 报告页三段内容全部由手机上已有的数据算出：AI 今天做了什么、额度值不值、明天交给 AI 什么。
final class DailyBriefTests: XCTestCase {
    private var calendar: Calendar = {
        var c = Calendar(identifier: .gregorian)
        c.timeZone = TimeZone(identifier: "Asia/Dubai")!
        return c
    }()
    /// 2026-09-15 14:00 Dubai.
    private let now = ISO8601DateFormatter().date(from: "2026-09-15T10:00:00Z")!

    private func task(_ id: String, _ executor: ExecutorType = .ai, provider: AIProvider? = .codex,
                      status: TaskStatus = .ready, priority: TaskPriority = .medium, project: String = "p1",
                      created: TimeInterval = 0) -> TaskItem {
        TaskItem(id: id, projectId: project, goalId: nil, title: "任务 \(id)", description: "", executorType: executor,
                 aiProvider: provider, collaborationMode: nil, status: status, priority: priority,
                 estimatedMinutes: 10, dueDate: nil, scheduledStart: nil, scheduledEnd: nil,
                 createdAt: now.addingTimeInterval(-86400 + created), completedAt: nil, resultSummary: nil,
                 updatedAt: now)
    }

    private func plan(_ id: String, task: String, status: PlanState = .ready) -> PlanItem {
        PlanItem(id: id, taskId: task, revision: 1, title: id, priority: 2, status: status, criteria: [],
                 dependsOn: [], estimatedHumanMinutes: 0, estimatedAiMinutes: 0, workWeight: 1, risk: 2,
                 executionPolicy: .balanced, createdAt: now.addingTimeInterval(-3600), updatedAt: now)
    }

    private func job(_ id: String, task: String, plan: String?, status: RemoteJobStatus, updated: TimeInterval = -600,
                     summary: String? = nil, notBefore: Date? = nil) -> RemoteJob {
        RemoteJob(id: id, taskId: task, runnerId: "r", workspaceId: "w", toolProfileId: "tool", status: status,
                  revision: 1, resultSummary: summary, prompt: nil, createdAt: now.addingTimeInterval(updated - 60),
                  updatedAt: now.addingTimeInterval(updated), planId: plan, notBefore: notBefore)
    }

    private func execution(_ id: String, task: String, status: AIExecutionStatus, provider: AIProvider = .claude,
                           start: TimeInterval, end: TimeInterval?, summary: String? = nil, error: String? = nil,
                           jobId: String? = nil) -> AIExecution {
        AIExecution(id: id, taskId: task, provider: provider, model: "m", status: status,
                    startedAt: now.addingTimeInterval(start), endedAt: end.map { now.addingTimeInterval($0) },
                    activeSeconds: 0, elapsedSeconds: 0, waitingHumanSeconds: 0, tokenInput: 0, tokenOutput: 0,
                    estimatedCost: 0, toolCallCount: 0, filesChanged: 0, resultSummary: summary, errorMessage: error,
                    remoteJobId: jobId, logs: [], currentStep: nil, updatedAt: now)
    }

    private func session(_ id: String, task: String, type: TimeSessionType = .aiActive,
                         start: TimeInterval, end: TimeInterval?) -> TimeSession {
        TimeSession(id: id, taskId: task, type: type, executor: "codex", startedAt: now.addingTimeInterval(start),
                    endedAt: end.map { now.addingTimeInterval($0) }, durationSeconds: 0, source: .integration,
                    confidence: .exact, note: nil, updatedAt: now)
    }

    private func window(_ scope: String, used: Double?, reset: TimeInterval?, minutes: Int = 0, fresh: Bool = true,
                        pool: String = "pool-codex") -> QuotaWindow {
        QuotaWindow(poolId: pool, scope: scope, kind: "codex", usedPercent: used,
                    resetAt: reset.map { now.addingTimeInterval($0) },
                    observedAt: now.addingTimeInterval(-300),
                    expiresAt: fresh ? now.addingTimeInterval(3600) : now.addingTimeInterval(-60),
                    source: "runner", confidence: "exact", windowMins: minutes)
    }

    private func make(tasks: [TaskItem] = [], plans: [PlanItem] = [], jobs: [RemoteJob] = [],
                      executions: [AIExecution] = [], sessions: [TimeSession] = [], quota: AccountQuota? = nil,
                      scope: ReportScope = .all) -> DailyBrief {
        var byPlan: [String: RemoteJob] = [:]
        for job in jobs { byPlan[job.planId ?? job.id] = job }
        return DailyBrief.make(now: now, calendar: calendar, tasks: tasks, plans: plans, jobs: byPlan,
                               executions: executions, sessions: sessions, quota: quota, scope: scope)
    }

    // MARK: - AI 今天替你干了什么

    func testWorkCountsStatusesAndNewestFirst() {
        let tasks = [task("a"), task("b"), task("c"), task("d"), task("e", status: .waitingHuman), task("f")]
        let plans = [plan("pa", task: "a", status: .accepted), plan("pb", task: "b", status: .awaitingReview),
                     plan("pc", task: "c", status: .failed), plan("pd", task: "d", status: .running)]
        let jobs = [job("ja", task: "a", plan: "pa", status: .completed, updated: -3000, summary: "修好了登录\n第二行细节"),
                    job("jb", task: "b", plan: "pb", status: .awaitingReview, updated: -60, summary: "  \n等你验收"),
                    job("jc", task: "c", plan: "pc", status: .failed, updated: -1200),
                    job("jd", task: "d", plan: "pd", status: .running, updated: -30),
                    job("jx", task: "f", plan: "px", status: .cancelled, updated: -10)]
        let executions = [execution("e1", task: "e", status: .completed, start: -7200, end: -1800, summary: "12 个测试"),
                          // Linked to a job already listed: not counted twice.
                          execution("e2", task: "a", status: .completed, start: -3600, end: -3000, jobId: "ja")]
        let brief = make(tasks: tasks, plans: plans, jobs: jobs, executions: executions)

        XCTAssertEqual(brief.counts, DailyBrief.WorkCounts(completed: 1, awaitingReview: 2, failed: 1, inProgress: 1))
        XCTAssertEqual(brief.items.map(\.taskId), ["d", "b", "c", "e", "a"], "newest first, cancelled dropped")
        let a = brief.items.first { $0.taskId == "a" }!
        XCTAssertEqual(a.status, .completed)
        XCTAssertEqual(a.statusLabel, "已验收")
        XCTAssertEqual(a.summary, "修好了登录")
        XCTAssertEqual(a.planId, "pa")
        XCTAssertEqual(a.tool, "Claude", "tool comes from the linked execution")
        let b = brief.items.first { $0.taskId == "b" }!
        XCTAssertEqual(b.status, .awaitingReview)
        XCTAssertEqual(b.statusLabel, "待验收")
        XCTAssertEqual(b.summary, "等你验收", "first non-empty line")
        XCTAssertEqual(b.tool, "Codex", "falls back to the task's provider")
        let e = brief.items.first { $0.taskId == "e" }!
        XCTAssertEqual(e.status, .awaitingReview, "a finished local execution whose task waits for me needs review")
        XCTAssertNil(e.planId)
        XCTAssertEqual(brief.items.first { $0.taskId == "d" }!.statusLabel, "AI 执行中")
        XCTAssertFalse(brief.isWorkEmpty)
    }

    func testWorkIsTodayOnlyButOpenItemsStay() {
        let tasks = [task("old"), task("review"), task("fail")]
        let jobs = [job("j1", task: "old", plan: "p1", status: .completed, updated: -3 * 86400),
                    job("j2", task: "review", plan: "p2", status: .awaitingReview, updated: -2 * 86400)]
        let executions = [execution("e", task: "fail", status: .failed, start: -90000, end: -89000, error: "上下文不足\n详情")]
        let brief = make(tasks: tasks, jobs: jobs, executions: executions)
        XCTAssertEqual(brief.items.map(\.taskId), ["review"], "yesterday's finished work is not today's; review still pending is")
    }

    func testFailedExecutionUsesErrorAsSummaryAndCapsAtTen() {
        var tasks: [TaskItem] = []
        var executions: [AIExecution] = []
        for i in 0..<12 {
            tasks.append(task("t\(i)"))
            executions.append(execution("e\(i)", task: "t\(i)", status: .failed, start: -Double(i * 60) - 600,
                                        end: -Double(i * 60), error: "上下文不足\n详情"))
        }
        let brief = make(tasks: tasks, executions: executions)
        XCTAssertEqual(brief.counts.failed, 12)
        XCTAssertEqual(brief.items.count, 10)
        XCTAssertEqual(brief.items.first?.taskId, "t0")
        XCTAssertEqual(brief.items.first?.summary, "上下文不足")
        XCTAssertEqual(brief.items.first?.statusLabel, "失败")
    }

    func testAIActiveMinutesComeFromTodaysSessionsClipped() {
        // Dubai midnight is 2026-09-14T20:00Z = now - 14h.
        let sessions = [session("s1", task: "a", start: -15 * 3600, end: -13 * 3600),   // 1h after midnight counts
                        session("s2", task: "a", start: -600, end: nil),                // open: runs until now
                        session("s3", task: "a", type: .humanFocus, start: -3600, end: -60),
                        session("s4", task: "b", start: -3600, end: -60)]
        let brief = make(tasks: [task("a")], jobs: [job("j", task: "a", plan: "p", status: .running)], sessions: sessions)
        XCTAssertEqual(brief.items.first?.aiActiveMinutes, 70)
    }

    func testScheduledJobIsInProgressWithScheduleLabel() {
        let at = now.addingTimeInterval(7200)
        let brief = make(tasks: [task("a")], jobs: [job("j", task: "a", plan: "p", status: .queued, notBefore: at)])
        XCTAssertEqual(brief.counts.inProgress, 1)
        XCTAssertEqual(brief.items.first?.statusLabel, "已安排 · " + Format.resetMoment(at, now: now))
    }

    func testEmptyWorkAndProjectScope() {
        XCTAssertTrue(make().isWorkEmpty)
        let tasks = [task("a", project: "A"), task("b", project: "B")]
        let jobs = [job("ja", task: "a", plan: "pa", status: .running), job("jb", task: "b", plan: "pb", status: .running)]
        let brief = make(tasks: tasks, jobs: jobs, scope: .project("A"))
        XCTAssertEqual(brief.items.map(\.taskId), ["a"])
    }

    // MARK: - 额度用得值不值

    func testQuotaRowShowsWeeklyAndShortWithWasteHint() {
        var pool = AccountQuotaPool(poolId: "pool-codex", provider: "codex", availability: "available",
                                    windows: [window("primary", used: 30, reset: 3 * 3600, minutes: 300),
                                              window("secondary", used: 35, reset: 20 * 3600, minutes: 10080)],
                                    planTier: "pro")
        pool.sources = [QuotaSource(runnerId: "r", runnerName: "Mac mini", observedAt: now)]
        let brief = make(quota: AccountQuota(pools: [pool], observedAt: now))
        let row = brief.quotaRows[0]
        XCTAssertEqual(row.name, "Codex")
        XCTAssertEqual(row.tier, "套餐 Pro")
        XCTAssertEqual(row.source, "来自 Mac mini")
        XCTAssertEqual(row.windows.map(\.label), ["本周", "短时"])
        XCTAssertEqual(row.windows.map(\.remaining), ["65%", "70%"])
        XCTAssertEqual(row.windows[0].reset, Format.resetMoment(now.addingTimeInterval(20 * 3600), now: now))
        let reset = Format.resetMoment(now.addingTimeInterval(20 * 3600), now: now)
        XCTAssertEqual(row.hint, "还剩 65%，\(reset) 重置——现在派一批任务更划算", "the weekly window wins over the short one")
        XCTAssertEqual(row.hintKind, .waste)
    }

    func testQuotaHintsForShortWindowExhaustedAndUnknown() {
        // Weekly resets in 3 days: only the short window can be wasted.
        let shortOnly = AccountQuotaPool(poolId: "a", provider: "claude", availability: "available",
                                         windows: [window("five_hour", used: 50, reset: 3600, pool: "a"),
                                                   window("seven_day", used: 10, reset: 3 * 86400, pool: "a")])
        // 39% left is below the threshold → no hint.
        let fine = AccountQuotaPool(poolId: "b", provider: "codex", availability: "available",
                                    windows: [window("weekly", used: 61, reset: 3600, pool: "b")])
        let exhausted = AccountQuotaPool(poolId: "c", provider: "codex", availability: "blocked",
                                         windows: [window("short", used: 100, reset: 5400, pool: "c"),
                                                   window("weekly", used: 70, reset: 2 * 86400, pool: "c")])
        let stale = AccountQuotaPool(poolId: "d", provider: "gemini", availability: "unknown",
                                     windows: [window("weekly", used: 20, reset: 3600, fresh: false, pool: "d")])
        let empty = AccountQuotaPool(poolId: "e", provider: "cursor", availability: "unknown", windows: [])
        let noResetExhausted = AccountQuotaPool(poolId: "f", provider: "codex", availability: "available",
                                                windows: [window("weekly", used: 100, reset: nil, pool: "f")])
        let brief = make(quota: AccountQuota(pools: [shortOnly, fine, exhausted, stale, empty, noResetExhausted], observedAt: now))
        let rows = Dictionary(uniqueKeysWithValues: brief.quotaRows.map { ($0.id, $0) })
        XCTAssertEqual(rows["a"]?.hint, "还剩 50%，\(Format.resetMoment(now.addingTimeInterval(3600), now: now)) 重置——现在派一批任务更划算")
        XCTAssertNil(rows["b"]?.hint)
        XCTAssertEqual(rows["c"]?.hint, "已用尽，\(Format.resetMoment(now.addingTimeInterval(5400), now: now)) 重置")
        XCTAssertEqual(rows["c"]?.hintKind, .exhausted)
        XCTAssertEqual(rows["d"]?.hint, "额度未知（电脑离线或未上报）")
        XCTAssertEqual(rows["d"]?.windows.first?.remaining, "待核验")
        XCTAssertEqual(rows["e"]?.hint, "额度未知（电脑离线或未上报）")
        XCTAssertEqual(rows["e"]?.hintKind, .unknown)
        XCTAssertEqual(rows["f"]?.hint, "已用尽，重置时间未知")
        XCTAssertEqual(brief.nextReset, now.addingTimeInterval(3600))
    }

    // MARK: - 明天可以交给 AI 的

    func testCandidatesSkipDoneHumanAndActiveTasksAndSortByPriority() {
        let tasks = [task("low", priority: .low), task("urgent", priority: .urgent),
                     task("human", .human, provider: nil), task("done", status: .completed),
                     task("cancel", status: .cancelled), task("running", status: .aiRunning),
                     task("review", status: .waitingHuman), task("queued"), task("planActive"),
                     task("collab", .collaboration, provider: .claude, priority: .high),
                     task("failed", status: .failed, priority: .high, created: 10)]
        let plans = [plan("p-low", task: "low"), plan("p-planActive", task: "planActive", status: .waitingQuota)]
        let jobs = [job("jq", task: "queued", plan: "p-queued", status: .queued)]
        let brief = make(tasks: tasks, plans: plans, jobs: jobs)
        XCTAssertEqual(brief.candidates.map(\.taskId), ["urgent", "collab", "failed", "low"])
        XCTAssertEqual(brief.candidates.last?.planId, "p-low")
        XCTAssertNil(brief.candidates.first?.planId, "no plan yet: prepared on demand")
        var many: [TaskItem] = []
        for i in 0..<10 { many.append(task("m\(i)", created: Double(i))) }
        XCTAssertEqual(make(tasks: many).candidates.count, 8)
    }

    func testCandidateScheduleUsesMatchingPoolResetPlusTwoMinutesClamped() {
        let codex = AccountQuotaPool(poolId: "pool-codex", provider: "codex", availability: "available",
                                     windows: [window("short", used: 10, reset: 3600), window("weekly", used: 20, reset: 5 * 86400)])
        // Claude's weekly window is exhausted: the short reset doesn't help, wait for the weekly one.
        let claude = AccountQuotaPool(poolId: "pool-claude", provider: "claude", availability: "blocked",
                                      windows: [window("short", used: 10, reset: 1800, pool: "pool-claude"),
                                                window("weekly", used: 100, reset: 2 * 86400, pool: "pool-claude")])
        let quota = AccountQuota(pools: [codex, claude], observedAt: now)
        let brief = make(tasks: [task("c", provider: .codex), task("k", provider: .claude), task("g", provider: .gemini)], quota: quota)
        let byTask = Dictionary(uniqueKeysWithValues: brief.candidates.map { ($0.taskId, $0) })
        XCTAssertEqual(byTask["c"]?.notBefore, now.addingTimeInterval(3600 + 120))
        XCTAssertEqual(byTask["k"]?.notBefore, now.addingTimeInterval(2 * 86400 + 120))
        XCTAssertEqual(byTask["g"]?.notBefore, now.addingTimeInterval(1800 + 120), "no own pool: next reset anywhere")
        XCTAssertEqual(byTask["c"]?.scheduleText, Format.resetMoment(now.addingTimeInterval(3720), now: now))

        XCTAssertEqual(DailyBrief.scheduledStart(after: now.addingTimeInterval(-3600), now: now), now.addingTimeInterval(120))
        XCTAssertEqual(DailyBrief.scheduledStart(after: now.addingTimeInterval(40 * 86400), now: now), now.addingTimeInterval(30 * 86400))
        XCTAssertNil(DailyBrief.scheduledStart(after: nil, now: now))
        XCTAssertNil(make(tasks: [task("x")]).candidates.first?.notBefore, "no reset known")
    }

    func testDispatchTargetPicksOnlineRunnerWorkspaceAndMatchingTool() {
        func inventory(_ id: String, status: String, workspaces: [RunnerWorkspace], tools: [RunnerTool]) -> RunnerInventory {
            RunnerInventory(runner: RemoteRunner(id: id, name: id, platform: "darwin", clientVersion: "1", status: status,
                                                 lastSeenAt: nil, revokedAt: nil, createdAt: now, updatedAt: now),
                            workspaces: workspaces, tools: tools)
        }
        let ws = RunnerWorkspace(id: "ws", name: "repo", defaultBranch: "main", enabled: true, updatedAt: now)
        let disabled = RunnerWorkspace(id: "off", name: "old", defaultBranch: "main", enabled: false, updatedAt: now)
        let codex = RunnerTool(id: "tool-codex", provider: .codex, version: "1", status: "available", updatedAt: now)
        let claude = RunnerTool(id: "tool-claude", provider: .claude, version: "1", status: "available", updatedAt: now)
        let offline = inventory("offline", status: "offline", workspaces: [ws], tools: [codex])
        let online = inventory("online", status: "online", workspaces: [disabled, ws], tools: [codex, claude])

        XCTAssertEqual(DailyBrief.dispatchTarget(provider: .claude, runners: [offline, online]),
                       .ready(runnerID: "online", workspaceID: "ws", toolID: "tool-claude"))
        XCTAssertEqual(DailyBrief.dispatchTarget(provider: nil, runners: [online]),
                       .ready(runnerID: "online", workspaceID: "ws", toolID: "tool-codex"))
        XCTAssertEqual(DailyBrief.dispatchTarget(provider: .codex, runners: [offline]), .unavailable("没有在线电脑"))
        XCTAssertEqual(DailyBrief.dispatchTarget(provider: .codex, runners: []), .unavailable("没有在线电脑"))
        XCTAssertEqual(DailyBrief.dispatchTarget(provider: .gemini, runners: [online]), .unavailable("电脑上没有可用的 Gemini"))
        let noWorkspace = inventory("bare", status: "online", workspaces: [disabled], tools: [codex])
        XCTAssertEqual(DailyBrief.dispatchTarget(provider: .codex, runners: [noWorkspace]), .unavailable("电脑上没有启用的工作区"))
    }
}
