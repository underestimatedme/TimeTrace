import SwiftUI

/// TaskCard in SubPageLayout.tsx; the trailing slot hosts the "…" menu on the Tasks page.
struct TaskCard<Menu: View>: View {
    @Environment(\.theme) private var theme
    let task: TaskItem
    var project: Project?
    let onTap: () -> Void
    @ViewBuilder var menu: () -> Menu

    init(task: TaskItem, project: Project?, onTap: @escaping () -> Void,
         @ViewBuilder menu: @escaping () -> Menu = { EmptyView() }) {
        self.task = task; self.project = project; self.onTap = onTap; self.menu = menu
    }

    private var borderColor: Color? {
        switch task.status {
        case .humanRunning: return theme.accent.opacity(0.3)
        case .aiRunning: return theme.ai.opacity(0.3)
        default: return nil
        }
    }

    var body: some View {
        Card(borderColor: borderColor) {
            HStack(alignment: .top, spacing: 8) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(task.title)
                        .font(Typo.sans(Typo.sm, weight: .medium))
                        .foregroundStyle(theme.text)
                        .lineLimit(1)
                    if let project {
                        Text("\(project.icon) \(project.name)")
                            .font(Typo.sans(Typo.xs))
                            .foregroundStyle(theme.textMuted)
                    }
                }
                Spacer(minLength: 0)
                menu()
            }
            .padding(.bottom, 8)
            HStack(spacing: 8) {
                StatusBadge(status: task.status)
                ExecutorBadge(type: task.executorType, provider: task.aiProvider)
                PriorityBadge(priority: task.priority)
                Spacer(minLength: 0)
                Text("\(task.estimatedMinutes) 分钟").font(Typo.sans(Typo.xs)).foregroundStyle(theme.textMuted)
            }
        }
        .contentShape(Rectangle())
        .onTapGesture(perform: onTap)
    }
}
