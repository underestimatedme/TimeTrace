import SwiftUI

/// Projects.tsx → ProjectsPage
struct ProjectsView: View {
    @Environment(\.theme) private var theme
    @Environment(AppStore.self) private var store
    @Environment(AppRouter.self) private var router

    var body: some View {
        SubPageScaffold(title: "项目与目标", action: { createButton }) {
            if store.projects.isEmpty {
                emptyState
            }
            VStack(spacing: 12) { ForEach(store.projects) { projectCard($0) } }
        }
    }

    /// 全新安装时没有项目：说明第一条任务会自动建好默认项目，并直接给出入口。
    private var emptyState: some View {
        Card {
            VStack(alignment: .leading, spacing: 8) {
                Text("还没有项目").font(Typo.sans(Glass.cardTitle, weight: .semibold)).foregroundStyle(theme.text)
                Text("新建第一条任务，刻迹会为它建好默认项目；之后可以在任务里挑选或整理项目与目标。")
                    .font(Typo.sans(Typo.sm)).foregroundStyle(theme.textSecondary).lineSpacing(3)
                AppButton("新建第一条任务", icon: "plus", variant: .accent, fullWidth: true) { router.push(.taskCreate) }
                    .accessibilityIdentifier("projects.empty.create")
                    .padding(.top, 4)
            }
        }
    }

    /// The only entry point into task creation: the bottom tabs have no "新建" of
    /// their own, so the projects tab carries it (GlassWorkspace's `+` action).
    private var createButton: some View {
        Button { router.push(.taskCreate) } label: {
            Image(systemName: "plus").font(.system(size: 18, weight: .regular)).foregroundStyle(theme.accent)
        }
        .buttonStyle(.plain)
        .accessibilityLabel("新建任务")
        .accessibilityIdentifier("task.create")
    }

    private func projectCard(_ project: Project) -> some View {
        let goals = store.goals.filter { $0.projectId == project.id }
        let tasks = store.tasks.filter { $0.projectId == project.id }
        let completed = tasks.filter { $0.status == .completed }.count
        let progress = tasks.isEmpty ? 0 : Double(completed) / Double(tasks.count) * 100
        let sessions = store.timeSessions.filter { s in tasks.contains { $0.id == s.taskId } }
        let human = Stats.humanSeconds(sessions, asOf: store.now)
        let ai = Stats.aiActiveSeconds(sessions)

        return Button { router.push(.project(project.id)) } label: {
            Card {
                HStack {
                    HStack(spacing: 8) {
                        Text(project.icon).font(.system(size: 20))
                        VStack(alignment: .leading, spacing: 2) {
                            Text(project.name)
                                .font(Typo.sans(Glass.cardTitle, weight: .semibold))
                                .kerning(-0.4)
                                .foregroundStyle(theme.text)
                            Text(ReportChangeLog(plans: store.plans, tasks: store.tasks, scope: .project(project.id)).acceptanceRatioText)
                                .font(Typo.sans(Typo.xs)).foregroundStyle(theme.textMuted)
                        }
                    }
                    Spacer()
                    Image(systemName: "chevron.right").font(.system(size: 13)).foregroundStyle(theme.textMuted).accessibilityHidden(true)
                }
                .padding(.bottom, 12)
                ProgressBar(value: progress).padding(.bottom, 8)
                HStack(spacing: 16) {
                    Text("人工 \(Format.duration(human))")
                    Text("AI \(Format.duration(ai))")
                }
                .font(Typo.sans(Typo.xs)).foregroundStyle(theme.textMuted)
                if let first = goals.first {
                    Text("当前目标: \(first.title)").font(Typo.sans(Typo.xs)).foregroundStyle(theme.textSecondary).padding(.top, 8)
                }
            }
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier("project.\(project.id)")
    }
}
