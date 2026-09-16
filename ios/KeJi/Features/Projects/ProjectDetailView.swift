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

        AppButton("本项目报告", variant: .secondary, fullWidth: true) { router.push(.reports(.project(project.id))) }
            .accessibilityIdentifier("reports.open.project")
            .padding(.bottom, 24)

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
        SectionTitle("任务 (\(ordered.count))")
        if ordered.isEmpty { MissingPlaceholder(text: "暂无任务") }
        VStack(spacing: 8) {
            ForEach(ordered) { task in
                Button { router.push(.taskDetail(task.id)) } label: {
                    Card {
                        HStack(spacing: 8) {
                            Text(task.title).font(Typo.sans(Typo.sm)).foregroundStyle(theme.text)
                            Spacer(minLength: 8)
                            StatusBadge(status: task.status)
                        }
                    }
                }
                .buttonStyle(.plain)
                .accessibilityIdentifier("task.\(task.id)")
            }
        }
    }
}
