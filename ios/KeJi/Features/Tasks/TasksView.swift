import SwiftUI

/// Tasks.tsx: filter chips, project chips, task cards with a "…" menu.
struct TasksView: View {
    @Environment(\.theme) private var theme
    @Environment(AppStore.self) private var store
    @Environment(AppRouter.self) private var router
    @Environment(AppEnvironment.self) private var appEnv

    enum Filter: String, CaseIterable {
        case all, pending, human, ai, waiting, completed
        var label: String {
            switch self {
            case .all: return "全部"
            case .pending: return "待处理"
            case .human: return "我来做"
            case .ai: return "AI 执行"
            case .waiting: return "等待我"
            case .completed: return "已完成"
            }
        }
    }

    enum Action { case start, pause, complete, delegate, delete }

    @State private var filter: Filter = .all
    @State private var projectFilter: String = "all"

    private var filtered: [TaskItem] {
        store.tasks.filter { t in
            if projectFilter != "all" && t.projectId != projectFilter { return false }
            switch filter {
            case .pending: return TaskStatus.pending.contains(t.status)
            case .human: return t.executorType == .human || t.executorType == .collaboration
            case .ai: return t.executorType == .ai || t.status == .aiRunning || t.status == .aiQueued
            case .waiting: return t.status == .waitingHuman
            case .completed: return t.status == .completed
            case .all: return true
            }
        }
    }

    var body: some View {
        TabPage {
            HStack {
                PageTitle(title: "任务")
                Spacer()
                Button { router.push(.taskCreate) } label: {
                    Image(systemName: "plus")
                        .font(.system(size: 18, weight: .light))
                        .foregroundStyle(theme.accent)
                        .frame(width: 36, height: 36)
                        .background(theme.accent.opacity(0.15))
                        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                }
                .buttonStyle(.plain)
                .accessibilityLabel("新建任务")
            }
            .padding(.bottom, 16)

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    ForEach(Filter.allCases, id: \.self) { f in
                        PillChip(label: f.label, selected: filter == f) { filter = f }
                    }
                }
                .padding(.horizontal, 2)
            }
            .padding(.bottom, 12)

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    OutlineChip(label: "全部项目", selected: projectFilter == "all") { projectFilter = "all" }
                    ForEach(store.projects) { p in
                        OutlineChip(label: "\(p.icon) \(p.name)", selected: projectFilter == p.id) { projectFilter = p.id }
                    }
                }
                .padding(.horizontal, 2)
            }
            .padding(.bottom, 16)

            if filtered.isEmpty {
                EmptyState(icon: "📋", title: "暂无任务", description: "点击右上角 + 创建新任务") {
                    AppButton("新建任务", variant: .accent) { router.push(.taskCreate) }
                }
            } else {
                VStack(spacing: 12) {
                    ForEach(filtered) { task in
                        TaskCard(task: task, project: store.project(task.projectId),
                                 onTap: { router.push(.taskDetail(task.id)) }) {
                            taskMenu(task)
                        }
                    }
                }
            }
        }
    }

    private func taskMenu(_ task: TaskItem) -> some View {
        Menu {
            if TaskStatus.startable.contains(task.status) && (task.executorType != .ai || appEnv.options.offline) {
                Button { handle(task, .start) } label: { Label("开始", systemImage: "play") }
            }
            if task.status == .humanRunning {
                Button { handle(task, .pause) } label: { Label("暂停", systemImage: "pause") }
            }
            Button { handle(task, .complete) } label: { Label("完成", systemImage: "checkmark") }
            if task.executorType == .human && appEnv.options.offline {
                Button { handle(task, .delegate) } label: { Label("委派给 AI", systemImage: "cpu") }
            }
            Button(role: .destructive) { handle(task, .delete) } label: { Label("删除", systemImage: "trash") }
        } label: {
            Image(systemName: "ellipsis")
                .rotationEffect(.degrees(90))
                .font(.system(size: 14))
                .foregroundStyle(theme.textMuted)
                .frame(width: 28, height: 24)
                .contentShape(Rectangle())
        }
        .accessibilityLabel("更多操作")
    }

    private func handle(_ task: TaskItem, _ action: Action) {
        switch action {
        case .start:
            if task.executorType == .ai {
                store.startAIExecution(task.id)
                router.push(.ai(task.id))
            } else {
                store.startFocus(task.id)
                router.push(.focus(task.id))
            }
        case .pause:
            store.pauseFocus()
            store.setTaskStatus(task.id, .paused)
        case .complete:
            store.setTaskStatus(task.id, .completed)
        case .delegate:
            store.startAIExecution(task.id)
        case .delete:
            store.deleteTask(task.id)
        }
    }
}
