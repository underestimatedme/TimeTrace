import SwiftUI

/// TaskCreate.tsx
struct TaskCreateView: View {
    @Environment(\.theme) private var theme
    @Environment(AppStore.self) private var store
    @Environment(AppRouter.self) private var router

    enum SaveAction { case save, start, schedule }

    @State private var title = ""
    @State private var description = ""
    @State private var projectId = ""
    @State private var goalId = ""
    @State private var executorType: ExecutorType = .human
    @State private var aiProvider: AIProvider = .claude
    @State private var collaborationMode: CollaborationMode = .aiIndependent
    @State private var estimatedMinutes = "30"
    @State private var priority: TaskPriority = .medium
    @State private var scheduledStart: Date?
    @State private var dueDate: Date?

    private var projectGoals: [Goal] { store.goals.filter { $0.projectId == projectId } }
    private var showsAI: Bool { executorType == .ai || executorType == .collaboration }
    private var canSave: Bool { !title.trimmingCharacters(in: .whitespaces).isEmpty }

    var body: some View {
        SubPageScaffold(title: "新建任务") {
            FormField(label: "任务名称") { AppTextField(placeholder: "输入任务名称", text: $title) }

            FormField(label: "所属项目") {
                if store.projects.isEmpty {
                    Text("📌 我的任务（自动创建）").modifier(InputChrome())
                } else {
                    AppSelect(options: store.projects.map(\.id), selection: $projectId) { id in
                        store.project(id).map { "\($0.icon) \($0.name)" } ?? ""
                    }
                }
            }

            if !projectGoals.isEmpty {
                FormField(label: "所属目标") {
                    AppSelect(options: [""] + projectGoals.map(\.id), selection: $goalId) { id in
                        id.isEmpty ? "不关联目标" : (store.goal(id)?.title ?? "")
                    }
                }
            }

            FormField(label: "执行者") {
                TwoColumnGrid {
                    executorTile(.human, "我来做")
                    executorTile(.ai, "AI 来做")
                    executorTile(.collaboration, "协作")
                    executorTile(.external, "等待其他人")
                }
            }

            if showsAI {
                FormField(label: "AI 提供商") {
                    LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 8), count: 3), spacing: 8) {
                        ForEach(AIProvider.allCases, id: \.self) { p in
                            OptionTile(label: p.capitalizedRaw, selected: aiProvider == p, tint: theme.ai,
                                       fontSize: Typo.xs, vertical: 8) { aiProvider = p }
                        }
                    }
                }
                if executorType == .collaboration {
                    FormField(label: "协作方式") {
                        AppSelect(options: CollaborationMode.allCases, selection: $collaborationMode) { $0.label }
                    }
                }
            }

            HStack(alignment: .top, spacing: 16) {
                FormField(label: "预计时间（分钟）") {
                    AppTextField(placeholder: "30", text: $estimatedMinutes, keyboard: .numberPad)
                }
                FormField(label: "优先级") {
                    AppSelect(options: TaskPriority.allCases, selection: $priority) { $0.label }
                }
            }

            HStack(alignment: .top, spacing: 16) {
                FormField(label: "计划开始") { OptionalDateField(date: $scheduledStart, components: [.date, .hourAndMinute]) }
                FormField(label: "截止日期") { OptionalDateField(date: $dueDate, components: [.date]) }
            }

            FormField(label: "任务描述") { AppTextEditor(placeholder: "描述任务详情...", text: $description) }

            VStack(spacing: 8) {
                AppButton("保存任务", variant: .accent, fullWidth: true, disabled: !canSave) { save(.save) }
                AppButton("保存并开始", variant: .secondary, fullWidth: true, disabled: !canSave) { save(.start) }
                AppButton("保存并安排时间", variant: .ghost, fullWidth: true, disabled: !canSave) { save(.schedule) }
            }
            .padding(.top, 8)
        }
        .onAppear {
            if projectId.isEmpty { projectId = store.projects.first?.id ?? "" }
        }
        .onChange(of: projectId) { _, _ in goalId = "" }
    }

    private func executorTile(_ type: ExecutorType, _ label: String) -> some View {
        OptionTile(label: label, selected: executorType == type) { executorType = type }
    }

    private func buildTask() -> TaskItem {
        let pid = projectId.isEmpty ? store.ensureDefaultProject().id : projectId
        return TaskItem(
            id: "", projectId: pid, goalId: goalId.isEmpty ? nil : goalId,
            title: title.trimmingCharacters(in: .whitespaces), description: description,
            executorType: executorType,
            aiProvider: showsAI ? aiProvider : nil,
            collaborationMode: executorType == .collaboration ? collaborationMode : nil,
            status: .inbox, priority: priority,
            estimatedMinutes: Int(estimatedMinutes) ?? 0,
            dueDate: dueDate.map(Format.dayKey),
            scheduledStart: scheduledStart, scheduledEnd: nil,
            createdAt: Date(), completedAt: nil, resultSummary: nil, updatedAt: Date())
    }

    private func save(_ action: SaveAction) {
        guard canSave else { return }
        let id = store.addTask(buildTask())
        switch action {
        case .start:
            router.go(.tasks)
            if executorType == .ai {
                store.startAIExecution(id)
                router.push(.ai(id))
            } else {
                store.startFocus(id)
                router.push(.focus(id))
            }
        case .save, .schedule:
            router.go(.tasks)
        }
    }
}
