import SwiftUI

/// Projects.tsx → GoalDetailPage
struct GoalDetailView: View {
    @Environment(\.theme) private var theme
    @Environment(AppStore.self) private var store
    @Environment(AppRouter.self) private var router
    let goalId: String

    var body: some View {
        SubPageScaffold(title: store.goal(goalId) == nil ? "目标" : "目标详情") {
            if let goal = store.goal(goalId) {
                content(goal)
            } else {
                MissingPlaceholder(text: "目标不存在")
            }
        }
    }

    @ViewBuilder
    private func content(_ goal: Goal) -> some View {
        let project = store.project(goal.projectId)
        let tasks = store.tasks.filter { $0.goalId == goal.id }
        let sessions = store.timeSessions.filter { s in tasks.contains { $0.id == s.taskId } }
        let human = Stats.humanSeconds(sessions, asOf: store.now)
        let ai = Stats.aiActiveSeconds(sessions)
        let completed = tasks.filter { $0.status == .completed }.count

        Text(goal.title).font(Typo.sans(Typo.lg, weight: .medium)).foregroundStyle(theme.text).padding(.bottom, 8)
        if let project {
            Text("\(project.icon) \(project.name)").font(Typo.sans(Typo.sm)).foregroundStyle(theme.textMuted).padding(.bottom, 16)
        }
        Text(goal.description).font(Typo.sans(Typo.sm)).foregroundStyle(theme.textSecondary).padding(.bottom, 16)

        VStack(spacing: 4) {
            HStack {
                Text("完成进度").font(Typo.sans(Typo.sm)).foregroundStyle(theme.textSecondary)
                Spacer()
                Text("\(Int(goal.progress))%").font(Typo.mono(Typo.sm)).foregroundStyle(theme.accent)
            }
            ProgressBar(value: goal.progress)
        }
        .padding(.bottom, 16)

        TwoColumnGrid {
            StatCard(label: "已投入时间", value: Format.duration(human + ai))
            StatCard(label: "AI 贡献", value: Format.duration(ai), valueColor: theme.ai)
            StatCard(label: "关联任务", value: "\(tasks.count)")
            StatCard(label: "已完成", value: "\(completed)", valueColor: theme.success)
        }
        .padding(.bottom, 24)

        SectionTitle("关联任务")
        VStack(spacing: 8) {
            ForEach(tasks) { task in
                Button { router.push(.taskDetail(task.id)) } label: {
                    Card { Text(task.title).font(Typo.sans(Typo.sm)).foregroundStyle(theme.text) }
                }
                .buttonStyle(.plain)
            }
        }
    }
}
