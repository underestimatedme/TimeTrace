import SwiftUI

/// Sessions belonging to a report scope. `.all` covers every project; `.project`
/// stays within that project's tasks — a project report never leaks other work.
func sessionsInScope(_ scope: ReportScope, tasks: [TaskItem], sessions: [TimeSession]) -> [TimeSession] {
    switch scope {
    case .all:
        return sessions
    case .project(let projectId):
        let taskIds = Set(tasks.filter { $0.projectId == projectId }.map { $0.id })
        return sessions.filter { taskIds.contains($0.taskId) }
    }
}

/// 报告只回答三件事，全部由手机上已有的数据算出（见 `DailyBrief`）：
/// AI 今天替你干了什么、额度用得值不值、明天可以交给 AI 的。不再展示任何评分。
struct ReportsView: View {
    @Environment(\.theme) private var theme
    @Environment(AppStore.self) private var store
    @Environment(AppRouter.self) private var router
    @Environment(RemoteExecutionClient.self) private var remote
    let scope: ReportScope
    @State private var scheduling: Set<String> = []
    @State private var scheduled: [String: String] = [:]
    @State private var scheduleErrors: [String: String] = [:]

    private var title: String {
        switch scope { case .all: return "报告"; case .project: return "项目报告" }
    }

    private var brief: DailyBrief {
        DailyBrief.make(now: store.now, tasks: store.tasks, plans: store.plans, jobs: store.planJobs,
                        executions: store.aiExecutions, sessions: store.timeSessions, quota: store.accountQuota,
                        scope: scope)
    }

    var body: some View {
        SubPageScaffold(title: title) { content }
            .task {
                UsageEvents.shared.record(.reportOpened, ["scope": .string(scopeName)])
                UsageEvents.shared.record(.screenView, ["screen": .string("report")])
                guard store.workspaceClient != nil else { return }
                await store.refreshWorkspaceQuota()
                await remote.loadRunners()
            }
    }

    private var scopeName: String {
        switch scope { case .all: return "all"; case .project: return "project" }
    }

    @ViewBuilder
    private var content: some View {
        let brief = brief
        Text(Format.date(store.now)).font(Typo.sans(Typo.sm, weight: .medium)).foregroundStyle(theme.text)
            .padding(.bottom, 20)

        aiWorkSection(brief)
        quotaSection(brief)
        tomorrowSection(brief)
    }

    // MARK: - AI 今天替你干了什么

    @ViewBuilder
    private func aiWorkSection(_ brief: DailyBrief) -> some View {
        SectionTitle("AI 今天替你干了什么")
        if brief.isWorkEmpty {
            Card {
                EmptyState(title: "今天还没有派给 AI 的任务", description: "新建一个任务交给 AI，结果会在这里汇总。") {
                    AppButton("新建任务", icon: "plus", variant: .accent, size: .sm) {
                        UsageEvents.shared.record(.reportAction, ["action": .string("create")])
                        router.push(.taskCreate)
                    }
                    .accessibilityIdentifier("reports.work.create")
                }
            }
            .padding(.bottom, 20)
        } else {
            TwoColumnGrid {
                StatCard(label: "已完成", value: "\(brief.counts.completed)", valueColor: theme.success)
                    .accessibilityIdentifier("reports.work.completed")
                StatCard(label: "待验收", value: "\(brief.counts.awaitingReview)", valueColor: theme.warning)
                    .accessibilityIdentifier("reports.work.review")
                StatCard(label: "失败", value: "\(brief.counts.failed)", valueColor: theme.danger)
                    .accessibilityIdentifier("reports.work.failed")
                StatCard(label: "进行中", value: "\(brief.counts.inProgress)", valueColor: theme.ai)
                    .accessibilityIdentifier("reports.work.progress")
            }
            .padding(.bottom, 8)
            Card(padding: 0) {
                VStack(spacing: 0) {
                    ForEach(brief.items) { item in
                        workRow(item)
                        if item.id != brief.items.last?.id { Rectangle().fill(theme.border).frame(height: 1) }
                    }
                }
                .padding(.horizontal, 16)
            }
            .padding(.bottom, 20)
        }
    }

    private func workRow(_ item: DailyBrief.WorkItem) -> some View {
        let review = item.status == .awaitingReview
        return Button { open(item) } label: {
            HStack(alignment: .top, spacing: 12) {
                Image(systemName: symbol(item.status))
                    .foregroundStyle(color(item.status))
                    .padding(.top, 2)
                    .accessibilityHidden(true)
                VStack(alignment: .leading, spacing: 4) {
                    Text(item.title).font(Typo.sans(Typo.sm, weight: .medium)).foregroundStyle(theme.text).lineLimit(2)
                    Text(detailLine(item)).font(Typo.sans(Typo.xs)).foregroundStyle(theme.textSecondary).lineLimit(1)
                    if let summary = item.summary {
                        Text(summary).font(Typo.sans(Typo.xs)).foregroundStyle(theme.textMuted).lineLimit(1)
                    }
                }
                Spacer(minLength: 0)
                if review {
                    Text("去验收")
                        .font(Typo.sans(Typo.xs, weight: .semibold))
                        .foregroundStyle(theme.bg)
                        .padding(.horizontal, 10).padding(.vertical, 5)
                        .background(theme.warning, in: Capsule())
                } else {
                    Image(systemName: "chevron.right").font(.system(size: 12)).foregroundStyle(theme.textMuted)
                        .padding(.top, 4).accessibilityHidden(true)
                }
            }
            .padding(.vertical, 14)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier(review ? "reports.work.review.\(item.taskId)" : "reports.work.item.\(item.taskId)")
        .accessibilityLabel(review ? "\(item.title)，待验收，去验收" : "\(item.title)，\(item.statusLabel)")
    }

    private func detailLine(_ item: DailyBrief.WorkItem) -> String {
        var parts = [item.statusLabel]
        if let tool = item.tool { parts.append(tool) }
        if item.aiActiveMinutes > 0 { parts.append("AI 活跃 \(item.aiActiveMinutes) 分钟") }
        return parts.joined(separator: " · ")
    }

    private func open(_ item: DailyBrief.WorkItem) {
        if item.status == .awaitingReview {
            UsageEvents.shared.record(.reportAction, ["action": .string("review")])
        }
        if let planId = item.planId { router.push(.plan(planId)) } else { router.push(.taskDetail(item.taskId)) }
    }

    private func symbol(_ status: DailyBrief.WorkStatus) -> String {
        switch status {
        case .completed: return "checkmark.circle.fill"
        case .awaitingReview: return "exclamationmark.circle.fill"
        case .failed: return "xmark.circle.fill"
        case .inProgress: return "arrow.triangle.2.circlepath.circle"
        }
    }

    private func color(_ status: DailyBrief.WorkStatus) -> Color {
        switch status {
        case .completed: return theme.success
        case .awaitingReview: return theme.warning
        case .failed: return theme.danger
        case .inProgress: return theme.ai
        }
    }

    // MARK: - 额度用得值不值

    @ViewBuilder
    private func quotaSection(_ brief: DailyBrief) -> some View {
        SectionTitle("额度用得值不值")
        if brief.quotaRows.isEmpty {
            Card {
                Text(DailyBrief.unknownQuotaText).font(Typo.sans(Typo.sm)).foregroundStyle(theme.textSecondary)
                    .accessibilityIdentifier("reports.quota.unknown")
            }
            .padding(.bottom, 20)
        } else {
            VStack(spacing: 8) {
                ForEach(brief.quotaRows) { row in quotaCard(row) }
            }
            .padding(.bottom, 20)
        }
    }

    private func quotaCard(_ row: DailyBrief.QuotaRow) -> some View {
        Card {
            HStack(alignment: .firstTextBaseline) {
                Text(row.name).font(Typo.sans(Typo.sm, weight: .semibold)).foregroundStyle(theme.text)
                Text(row.tier).font(Typo.sans(Typo.xs)).foregroundStyle(theme.textMuted)
                Spacer(minLength: 0)
            }
            ForEach(row.windows, id: \.label) { line in
                Text("\(line.label)剩 \(line.remaining)" + (line.reset.map { " · \($0) 重置" } ?? ""))
                    .font(Typo.sans(Typo.xs)).foregroundStyle(theme.textSecondary).monospacedDigit()
                    .padding(.top, 4)
            }
            if let hint = row.hint {
                Text(hint).font(Typo.sans(Typo.xs, weight: .medium))
                    .foregroundStyle(row.hintKind == .waste ? theme.accent : row.hintKind == .exhausted ? theme.danger : theme.textMuted)
                    .padding(.top, 6)
                    .accessibilityIdentifier("reports.quota.hint.\(row.id)")
            }
            Text(row.source).font(Typo.sans(Typo.xs)).foregroundStyle(theme.textMuted).padding(.top, 4)
        }
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier("reports.quota.\(row.id)")
    }

    // MARK: - 明天可以交给 AI 的

    @ViewBuilder
    private func tomorrowSection(_ brief: DailyBrief) -> some View {
        SectionTitle("明天可以交给 AI 的")
        Text(brief.nextReset.map { "下一次额度重置：\(Format.resetMoment($0, now: store.now))" } ?? "下一次额度重置时间未知")
            .font(Typo.sans(Typo.xs)).foregroundStyle(theme.textMuted).padding(.bottom, 8)
            .accessibilityIdentifier("reports.tomorrow.reset")
        if brief.candidates.isEmpty {
            Card {
                Text("没有等着交给 AI 的任务。").font(Typo.sans(Typo.sm)).foregroundStyle(theme.textSecondary)
            }
        } else {
            VStack(spacing: 8) {
                ForEach(brief.candidates) { candidate in candidateCard(candidate) }
            }
        }
    }

    private func candidateCard(_ candidate: DailyBrief.Candidate) -> some View {
        let target = DailyBrief.dispatchTarget(provider: candidate.provider, runners: remote.runners)
        let busy = scheduling.contains(candidate.taskId)
        let disabledReason: String? = {
            if case .unavailable(let reason) = target { return reason }
            if candidate.notBefore == nil { return "重置时间未知" }
            return nil
        }()
        return Card {
            Text(candidate.title).font(Typo.sans(Typo.sm, weight: .medium)).foregroundStyle(theme.text).lineLimit(2)
            Text([candidate.provider?.label ?? "AI", candidate.scheduleText.map { "计划 \($0) 开始" }].compactMap { $0 }.joined(separator: " · "))
                .font(Typo.sans(Typo.xs)).foregroundStyle(theme.textSecondary).padding(.top, 2)
            if let done = scheduled[candidate.taskId] {
                Text("已安排 · \(done)").font(Typo.sans(Typo.xs, weight: .medium)).foregroundStyle(theme.success).padding(.top, 8)
            } else {
                let label = busy ? "安排中…" : (disabledReason ?? "安排在重置后执行")
                AppButton(label, icon: disabledReason == nil ? "clock" : nil,
                          variant: disabledReason == nil ? .accent : .secondary, size: .sm, fullWidth: true,
                          disabled: busy || disabledReason != nil) {
                    Task { await schedule(candidate, target: target) }
                }
                .accessibilityLabel("\(candidate.title)：\(label)")
                .accessibilityIdentifier("reports.schedule.\(candidate.taskId)")
                .padding(.top, 8)
            }
            if let error = scheduleErrors[candidate.taskId] {
                Text(error).font(Typo.sans(Typo.xs)).foregroundStyle(theme.warning).padding(.top, 6)
            }
        }
    }

    @MainActor private func schedule(_ candidate: DailyBrief.Candidate, target: DailyBrief.DispatchTarget) async {
        guard case let .ready(runnerID, workspaceID, toolID) = target, let notBefore = candidate.notBefore,
              !scheduling.contains(candidate.taskId) else { return }
        UsageEvents.shared.record(.reportAction, ["action": .string("schedule")])
        scheduling.insert(candidate.taskId)
        defer { scheduling.remove(candidate.taskId) }
        scheduleErrors[candidate.taskId] = nil
        var planId = candidate.planId
        if planId == nil {
            planId = await store.prepareTaskPlan(candidate.taskId)?.id
        }
        guard let planId else {
            scheduleErrors[candidate.taskId] = store.planErrors[candidate.taskId] ?? "暂时无法准备 Plan，请稍后重试。"
            return
        }
        let provider = remote.runners.first { $0.id == runnerID }?.tools.first { $0.id == toolID }?.provider
        if await store.dispatchPlan(planId, runnerID: runnerID, workspaceID: workspaceID, toolID: toolID,
                                    notBefore: notBefore, source: "report", toolProvider: provider) {
            scheduled[candidate.taskId] = Format.resetMoment(notBefore, now: store.now)
        } else {
            scheduleErrors[candidate.taskId] = store.planErrors[planId] ?? "派发失败，请稍后重试。"
        }
    }
}
