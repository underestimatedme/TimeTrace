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
    let scope: ReportScope

    private var title: String {
        switch scope { case .all: return "报告"; case .project: return "项目报告" }
    }

    var body: some View {
        SubPageScaffold(title: title) { content }
    }

    @ViewBuilder
    private var content: some View {
        let day = Format.dayKey(store.now)
        let sessions = sessionsInScope(scope, tasks: store.tasks, sessions: store.timeSessions)
        let human = Stats.humanSeconds(sessions, day: day)
        let ai = Stats.aiActiveSeconds(sessions, day: day)
        let waiting = Stats.waitingSeconds(sessions, day: day)

        VStack(alignment: .leading, spacing: 0) {
            Text(Format.date(store.now)).font(Typo.sans(Typo.sm, weight: .medium)).foregroundStyle(theme.text)
            Text("时区 \(TimeZone.current.identifier) · 修订 1 · 私有草稿")
                .font(Typo.sans(Typo.xs)).foregroundStyle(theme.textMuted)
        }
        .padding(.bottom, 20)

        SectionTitle("时间拆分（人工 / AI / 等待分开统计）")
        TwoColumnGrid {
            StatCard(label: "人工投入", value: Format.duration(human), valueColor: theme.accent)
                .accessibilityIdentifier("reports.human")
            StatCard(label: "AI 活跃（累计）", value: Format.duration(ai), valueColor: theme.ai)
                .accessibilityIdentifier("reports.ai")
            StatCard(label: "等待", value: Format.duration(waiting), valueColor: theme.warning)
                .accessibilityIdentifier("reports.waiting")
        }
        .padding(.bottom, 8)
        Text("人工与 AI 时间不相加；AI 多机活跃计为累计活跃。")
            .font(Typo.sans(Typo.xs)).foregroundStyle(theme.textMuted)
            .padding(.bottom, 20)

        SectionTitle("生产力")
        Card {
            Text("样本覆盖不足，暂不显示总分。")
                .font(Typo.sans(Typo.sm)).foregroundStyle(theme.textSecondary)
            Text("总分需服务端覆盖率达标后按已知权重给出，并附覆盖率、分项与版本。")
                .font(Typo.sans(Typo.xs)).foregroundStyle(theme.textMuted).padding(.top, 6)
        }
        .padding(.bottom, 20)

        ShareLink(item: markdown(human: human, ai: ai, waiting: waiting)) {
            Text("导出为 Markdown").font(Typo.sans(Typo.sm)).foregroundStyle(theme.accent)
        }
        .accessibilityIdentifier("reports.export")
    }

    private func markdown(human: Int, ai: Int, waiting: Int) -> String {
        """
        # 刻迹日报 \(Format.date(store.now))
        - 人工投入：\(Format.duration(human))
        - AI 活跃（累计）：\(Format.duration(ai))
        - 等待：\(Format.duration(waiting))
        > 人工与 AI 时间分开统计；样本不足暂不显示总分。
        """
    }
}
