import SwiftUI

/// Projects.tsx → ProjectDetailPage
struct ProjectDetailView: View {
    @Environment(\.theme) private var theme
    @Environment(AppStore.self) private var store
    @Environment(AppRouter.self) private var router
    let projectId: String

    var body: some View {
        if let project = store.project(projectId) {
            SubPageScaffold(title: project.name) { content(project) }
        } else {
            SubPageScaffold(title: "项目") { MissingPlaceholder(text: "项目不存在") }
        }
    }

    @ViewBuilder
    private func content(_ project: Project) -> some View {
        let goals = store.goals.filter { $0.projectId == project.id }
        let tasks = store.tasks.filter { $0.projectId == project.id }
        let pending = tasks.filter { !TaskStatus.terminal.contains($0.status) }
        let sessions = store.timeSessions.filter { s in tasks.contains { $0.id == s.taskId } }

        HStack(spacing: 12) {
            Text(project.icon).font(.system(size: 30))
            Text(project.description).font(Typo.sans(Typo.sm)).foregroundStyle(theme.textSecondary)
        }
        .padding(.bottom, 24)

        TwoColumnGrid {
            StatCard(label: "人工投入", value: Format.duration(Stats.humanSeconds(sessions)), valueColor: theme.accent)
            StatCard(label: "AI 投入", value: Format.duration(Stats.aiActiveSeconds(sessions)), valueColor: theme.ai)
        }
        .padding(.bottom, 12)

        AppButton("项目报告", variant: .secondary, fullWidth: true) { router.push(.reports(.project(project.id))) }
            .accessibilityIdentifier("reports.open.project")
            .padding(.bottom, 24)

        // 版本目标：项目当前进行中的目标及其预计交付日期（真实数据，不用设计稿的演示值）。
        if let milestone = goals.first(where: { $0.status == .active }) ?? goals.first {
            Card {
                Text("版本目标").font(Typo.sans(Typo.xs)).foregroundStyle(theme.textSecondary)
                Text(milestone.title).font(Typo.sans(Typo.lg, weight: .medium)).foregroundStyle(theme.text)
                    .padding(.vertical, 4)
                Text("预计交付 \(Format.dateShort(milestone.targetDate))")
                    .font(Typo.sans(Typo.xs)).foregroundStyle(theme.textSecondary)
            }
            .accessibilityIdentifier("project.milestone")
            .padding(.bottom, 24)
        }

        SectionTitle("目标")
        VStack(spacing: 8) {
            ForEach(goals) { goal in
                Button { router.push(.goal(goal.id)) } label: {
                    Card {
                        HStack {
                            Text(goal.title).font(Typo.sans(Typo.sm, weight: .medium)).foregroundStyle(theme.text)
                            Spacer()
                            Text("\(Int(goal.progress))%").font(Typo.mono(Typo.xs)).foregroundStyle(theme.accent)
                        }
                        .padding(.bottom, 8)
                        ProgressBar(value: goal.progress)
                    }
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.bottom, 24)

        // Every task in the project, pending first. A completed or cancelled task
        // is still reachable — this list is the only way into a task's detail.
        let ordered = pending + tasks.filter { TaskStatus.terminal.contains($0.status) }
        SectionTitle("目标范围 (\(ordered.count))")
        if ordered.isEmpty { MissingPlaceholder(text: "暂无任务") }
        // .gl-task-row —— 细分隔线的长列表，而不是每行一张卡片
        VStack(spacing: 0) {
            ForEach(ordered) { task in
                Button { router.push(.taskDetail(task.id)) } label: {
                    HStack(spacing: 13) {
                        VStack(alignment: .leading, spacing: 6) {
                            Text(task.title)
                                .font(Typo.sans(Glass.rowTitle, weight: .medium)).foregroundStyle(theme.text)
                            Text("\(task.priority.label)优先级 · \(store.plans(forTask: task.id).filter { !$0.id.hasPrefix("draft-") }.count) 个 Plan")
                                .font(Typo.sans(Glass.small)).foregroundStyle(theme.textSecondary)
                        }
                        Spacer(minLength: 8)
                        StatusBadge(status: task.status)
                        Image(systemName: "chevron.right").font(.system(size: 12)).foregroundStyle(theme.textMuted).accessibilityHidden(true)
                    }
                    .padding(.vertical, Glass.rowSpacing)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityIdentifier("task.\(task.id)")
                if task.id != ordered.last?.id { Divider1() }
            }
        }
    }
}
