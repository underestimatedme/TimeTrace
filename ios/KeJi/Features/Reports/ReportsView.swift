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

/// Daily report: human input, AI active time and waiting time are shown
/// separately (never summed). A total productivity score needs server coverage;
/// offline we present only the breakdown. Export uses the system share sheet and
/// never writes to a repo.
struct ReportsView: View {
    @Environment(\.theme) private var theme
    @Environment(AppStore.self) private var store
    @Environment(\.timeZone) private var timeZone
    let scope: ReportScope
    @State private var loader = ReportLoader()
    private var context: ReportContext { ReportContext(now: store.now, timeZone: timeZone) }
    private var report: DailyReport? { loader.currentReport(for: context) }
    private var loading: Bool { loader.context == context && loader.loading }
    private var reportError: String? { loader.context == context ? loader.error : nil }

    private var title: String {
        switch scope { case .all: return "报告"; case .project: return "项目报告" }
    }

    var body: some View {
        SubPageScaffold(title: title) { content }
            .task(id: context) { await loadReport(generate: false) }
    }

    @ViewBuilder
    private var content: some View {
        let day = context.date
        let sessions = sessionsInScope(scope, tasks: store.tasks, sessions: store.timeSessions)
        let presentation = presentation(sessions: sessions, day: day)

        VStack(alignment: .leading, spacing: 0) {
            Text(Format.date(store.now)).font(Typo.sans(Typo.sm, weight: .medium)).foregroundStyle(theme.text)
            Text(report.map { "时区 \($0.breakdown?.zone ?? TimeZone.current.identifier) · 修订 \($0.revision) · 私有草稿" }
                 ?? "时区 \(timeZone.identifier) · 本地草稿")
                .font(Typo.sans(Typo.xs)).foregroundStyle(theme.textMuted)
        }
        .padding(.bottom, 20)

        SectionTitle("时间拆分（人工 / AI / 等待分开统计）")
        TwoColumnGrid {
            StatCard(label: "人工投入", value: presentation.human.text, valueColor: theme.accent)
                .accessibilityIdentifier("reports.human")
            StatCard(label: "AI 活跃（累计）", value: presentation.ai.text, valueColor: theme.ai)
                .accessibilityIdentifier("reports.ai")
            StatCard(label: "等待", value: presentation.waiting.text, valueColor: theme.warning)
                .accessibilityIdentifier("reports.waiting")
        }
        .padding(.bottom, 8)
        Text("人工、AI 与等待时间不相加；人工重叠取并集，AI 独立执行累计。无记录与未知不等于零。")
            .font(Typo.sans(Typo.xs)).foregroundStyle(theme.textMuted)
            .padding(.bottom, 20)

        SectionTitle("生产力")
        Card {
            Text(totalText)
                .font(Typo.sans(Typo.sm)).foregroundStyle(theme.textSecondary)
            Text("时间事实覆盖率 \(Format.percent(presentation.evidenceCoverage))；这不是生产力评分覆盖率。")
                .font(Typo.sans(Typo.xs)).foregroundStyle(theme.textMuted).padding(.top, 6)
            if let report {
                Text("评分覆盖率 \(Format.percent(report.coverage)) · 基线 \(report.baselineVersion)")
                    .font(Typo.sans(Typo.xs)).foregroundStyle(theme.textMuted)
            }
        }
        .padding(.bottom, 20)

        if store.workspaceClient != nil {
            Button(loading ? "生成中…" : "生成新修订") { Task { await loadReport(generate: true) } }
                .disabled(loading)
                .accessibilityIdentifier("reports.generate")
                .padding(.bottom, 12)
        }
        if let reportError {
            Text(reportError).font(Typo.sans(Typo.xs)).foregroundStyle(theme.warning).padding(.bottom, 12)
        }
        ShareLink(item: markdown(presentation)) {
            Text("导出为 Markdown").font(Typo.sans(Typo.sm)).foregroundStyle(theme.accent)
        }
        .accessibilityIdentifier("reports.export")
    }

    private var totalText: String {
        if case .all = scope, let report, report.hasTotal, let total = report.totalScore {
            return "生产力总分 \(Int(total.rounded()))"
        }
        return "样本覆盖不足，暂不显示总分。"
    }

    private func presentation(sessions: [TimeSession], day: String) -> ReportPresentation {
        let ids: Set<String>?
        switch scope { case .all: ids = nil; case .project(let id): ids = Set(store.tasks.filter { $0.projectId == id }.map(\.id)) }
        return loader.presentation(for: context, sessions: sessions, taskIds: ids)
    }

    @MainActor private func loadReport(generate: Bool) async {
        guard let client = store.workspaceClient else { return }
        let requested = context
        await loader.load(context: requested) {
            try await (generate ? client.generateReport(date: requested.date, zone: requested.zone) : client.report(date: requested.date, zone: requested.zone))
        }
    }

    private func markdown(_ presentation: ReportPresentation) -> String {
        """
        # 刻迹日报 \(Format.date(store.now))
        - 人工投入：\(presentation.human.text)
        - AI 活跃（累计）：\(presentation.ai.text)
        - 等待：\(presentation.waiting.text)
        - 时间事实覆盖率：\(Format.percent(presentation.evidenceCoverage))
        - 修订：\(report.map { String($0.revision) } ?? "本地草稿") · 私有草稿
        > 人工、AI 与等待分开统计。\(totalText)
        """
    }
}
