import SwiftUI

/// Projects.tsx → ProjectsPage
struct ProjectsView: View {
    @Environment(\.theme) private var theme
    @Environment(AppStore.self) private var store
    @Environment(AppRouter.self) private var router

    var body: some View {
        SubPageScaffold(title: "项目与目标") {
            if store.projects.isEmpty {
                MissingPlaceholder(text: "暂无项目")
            }
            VStack(spacing: 12) { ForEach(store.projects) { projectCard($0) } }
        }
    }

    private func projectCard(_ project: Project) -> some View {
        let goals = store.goals.filter { $0.projectId == project.id }
        let tasks = store.tasks.filter { $0.projectId == project.id }
        let completed = tasks.filter { $0.status == .completed }.count
        let progress = tasks.isEmpty ? 0 : Double(completed) / Double(tasks.count) * 100
        let sessions = store.timeSessions.filter { s in tasks.contains { $0.id == s.taskId } }
        let human = Stats.humanSeconds(sessions)
        let ai = Stats.aiActiveSeconds(sessions)

        return Button { router.push(.project(project.id)) } label: {
            Card {
                HStack {
                    HStack(spacing: 8) {
                        Text(project.icon).font(.system(size: 20))
                        VStack(alignment: .leading, spacing: 2) {
                            Text(project.name).font(Typo.sans(Typo.sm, weight: .medium)).foregroundStyle(theme.text)
                            Text("\(tasks.count) 个任务").font(Typo.sans(Typo.xs)).foregroundStyle(theme.textMuted)
                        }
                    }
                    Spacer()
                    Image(systemName: "chevron.right").font(.system(size: 13)).foregroundStyle(theme.textMuted)
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
