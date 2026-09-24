import SwiftUI

/// TaskCreate.tsx
struct TaskCreateView: View {
    @Environment(\.theme) private var theme
    @Environment(AppStore.self) private var store
    @Environment(AppRouter.self) private var router
    @Environment(RemoteExecutionClient.self) private var remote
    @Environment(AppEnvironment.self) private var appEnv

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
    @State private var runnerId = ""
    @State private var workspaceId = ""
    @State private var toolId = ""

    private var projectGoals: [Goal] { store.goals.filter { $0.projectId == projectId } }
    private var showsAI: Bool { executorType == .ai || executorType == .collaboration }
    private var canSave: Bool {
        guard !title.trimmingCharacters(in: .whitespaces).isEmpty else { return false }
        if showsAI && !appEnv.options.offline {
            return selectedRunner != nil && !workspaceId.isEmpty && !toolId.isEmpty
        }
        return true
    }
    private var selectedRunner: RunnerInventory? { remote.runners.first { $0.runner.id == runnerId } }
    private var availableTools: [RunnerTool] {
        selectedRunner?.tools.filter { $0.provider == aiProvider && $0.status == "available" } ?? []
    }

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
                if remote.runners.isEmpty {
                    Card(borderColor: theme.ai.opacity(0.2)) {
                        Text("还没有在线电脑。请先在「AI 工具管理」中绑定 Mac，并运行 keji agent。")
                            .font(Typo.sans(Typo.xs)).foregroundStyle(theme.textSecondary)
                    }
                } else {
                    FormField(label: "执行电脑") {
                        AppSelect(options: remote.runners.map(\.runner.id), selection: $runnerId) { id in
                            remote.runners.first { $0.runner.id == id }?.runner.name ?? id
                        }
                    }
                    if let selectedRunner {
                        FormField(label: "本地工作区") {
                            AppSelect(options: selectedRunner.workspaces.map(\.id), selection: $workspaceId) { id in
                                selectedRunner.workspaces.first { $0.id == id }?.name ?? id
                            }
                        }
                        FormField(label: "本机工具") {
                            AppSelect(options: availableTools.map(\.id), selection: $toolId) { id in
                                availableTools.first { $0.id == id }.map { "\($0.provider.label) · \($0.version)" } ?? id
                            }
                        }
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
                AppButton("保存并安排时间", variant: .ghost, fullWidth: true,
                          disabled: !canSave || scheduledStart == nil || executorType != .ai || appEnv.options.offline) { save(.schedule) }
                    .accessibilityIdentifier("task.schedule")
                Text("「安排时间」按「计划开始」的时刻派给 AI 执行；需要选 AI 来做并填好计划开始。")
                    .font(Typo.sans(Typo.xs)).foregroundStyle(theme.textMuted)
            }
            .padding(.top, 8)
        }
        .onAppear {
            if projectId.isEmpty { projectId = store.projects.first?.id ?? "" }
            selectRemoteDefaults()
            _Concurrency.Task { await remote.loadRunners(); selectRemoteDefaults() }
        }
        .onChange(of: projectId) { _, _ in goalId = "" }
        .onChange(of: runnerId) { _, _ in selectRunnerDefaults() }
        .onChange(of: aiProvider) { _, _ in toolId = availableTools.first?.id ?? "" }
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
        case .start, .schedule:
            router.go(.projects)
            if executorType == .ai {
                router.push(.taskDetail(id))
                if !appEnv.options.offline {
                    // 「安排时间」= 同一条派发，只是带上「计划开始」作为执行时刻。
                    let notBefore = action == .schedule ? scheduledStart : nil
                    _Concurrency.Task {
                        if let plan = await store.prepareTaskPlan(id) {
                            router.push(.plan(plan.id))
                            await store.dispatchPlan(plan.id, runnerID: runnerId, workspaceID: workspaceId, toolID: toolId,
                                                     notBefore: notBefore)
                        }
                    }
                }
            } else {
                store.startFocus(id)
                router.push(.focus(id))
            }
        case .save:
            router.go(.projects)
        }
    }

    private func selectRemoteDefaults() {
        if runnerId.isEmpty { runnerId = remote.runners.first?.runner.id ?? "" }
        selectRunnerDefaults()
    }

    private func selectRunnerDefaults() {
        guard let selectedRunner else { return }
        if !selectedRunner.workspaces.contains(where: { $0.id == workspaceId }) {
            workspaceId = selectedRunner.workspaces.first?.id ?? ""
        }
        if !availableTools.contains(where: { $0.id == toolId }) {
            toolId = availableTools.first?.id ?? ""
        }
    }
}
