import SwiftUI

/// TaskDetail.tsx
struct TaskDetailView: View {
    @Environment(\.theme) private var theme
    @Environment(AppStore.self) private var store
    @Environment(AppRouter.self) private var router
    @Environment(AppEnvironment.self) private var appEnv
    let taskId: String

    private struct TimelineEvent: Identifiable { let id = UUID(); let time: Date; let label: String }

    var body: some View {
        SubPageScaffold(title: "任务详情") {
            if let task = store.task(taskId) {
                content(task)
            } else {
                MissingPlaceholder(text: "任务不存在")
            }
        }
    }

    @ViewBuilder
    private func content(_ task: TaskItem) -> some View {
        let project = store.project(task.projectId)
        let goal = task.goalId.flatMap(store.goal)
        let breakdown = Stats.taskTimeBreakdown(store.timeSessions, taskId: task.id)
        let aiExec = store.aiExecutions.last { $0.taskId == task.id }

        VStack(alignment: .leading, spacing: 0) {
            Text(task.title).font(Typo.sans(Typo.lg, weight: .medium)).foregroundStyle(theme.text).padding(.bottom, 8)
            HStack(spacing: 8) {
                StatusBadge(status: task.status)
                ExecutorBadge(type: task.executorType, provider: task.aiProvider)
            }
            .padding(.bottom, 12)
            if !task.description.isEmpty {
                Text(task.description).font(Typo.sans(Typo.sm)).foregroundStyle(theme.textSecondary).lineSpacing(4)
            }
        }
        .padding(.bottom, 24)

        TwoColumnGrid {
            StatCard(label: "预计时间", value: "\(task.estimatedMinutes) 分钟")
            StatCard(label: "实际人工", value: Format.duration(breakdown.human), valueColor: theme.accent)
        }
        if let goal { infoCard("所属目标", goal.title).padding(.top, 8) }
        if let project { infoCard("所属项目", "\(project.icon) \(project.name)").padding(.top, 8) }
        Spacer().frame(height: 24)

        SectionTitle("流程时间线")
        timeline(task).padding(.bottom, 24)

        SectionTitle("时间拆分")
        TwoColumnGrid {
            StatCard(label: "人工投入", value: Format.duration(breakdown.human), valueColor: theme.accent)
            StatCard(label: "AI 活跃", value: Format.duration(breakdown.ai), valueColor: theme.ai)
            StatCard(label: "等待人工", value: Format.duration(breakdown.waitingHuman), valueColor: theme.warning)
            StatCard(label: "总历时", value: Format.duration(breakdown.total))
        }
        .padding(.bottom, 24)

        if let aiExec {
            SectionTitle("AI 执行信息")
            aiInfo(aiExec).padding(.bottom, 24)
        }

        HStack(spacing: 8) {
            if task.status == .waitingHuman {
                AppButton("审核完成", variant: .accent, fullWidth: true) { store.completeAIReview(task.id) }
            }
            if TaskStatus.startable.contains(task.status) && (task.executorType != .ai || appEnv.options.offline) {
                AppButton("开始执行", variant: .accent, fullWidth: true) {
                    if task.executorType == .ai {
                        store.startAIExecution(task.id)
                        router.push(.ai(task.id))
                    } else {
                        store.startFocus(task.id)
                        router.push(.focus(task.id))
                    }
                }
            }
            if task.status == .aiRunning {
                AppButton("查看 AI 执行", variant: .secondary, fullWidth: true) { router.push(.ai(task.id)) }
            }
        }
        if TaskStatus.startable.contains(task.status), task.executorType == .ai, !appEnv.options.offline {
            Text("在线 AI 任务请在新建任务时选择电脑、工作区和工具后派发。")
                .font(Typo.sans(Typo.xs)).foregroundStyle(theme.textMuted)
        }
    }

    private func infoCard(_ label: String, _ value: String) -> some View {
        Card {
            Text(label).font(Typo.sans(Typo.xs)).foregroundStyle(theme.textMuted)
            Text(value).font(Typo.sans(Typo.sm)).foregroundStyle(theme.text)
        }
    }

    private func timeline(_ task: TaskItem) -> some View {
        let sessions = store.timeSessions.filter { $0.taskId == task.id }.sorted { $0.startedAt < $1.startedAt }
        var events = [TimelineEvent(time: task.createdAt, label: "创建任务")]
        events += sessions.map {
            TimelineEvent(time: $0.startedAt,
                          label: "\($0.isHumanExecutor ? "我" : $0.executor): \($0.type.rawValue.replacingOccurrences(of: "_", with: " "))")
        }
        if let done = task.completedAt { events.append(TimelineEvent(time: done, label: "任务完成")) }
        events.sort { $0.time < $1.time }

        return VStack(alignment: .leading, spacing: 0) {
            ForEach(events) { event in
                HStack(alignment: .top, spacing: 12) {
                    Circle().fill(theme.accent).frame(width: 8, height: 8).padding(.top, 4)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(Format.time(event.time)).font(Typo.mono(Typo.xs)).foregroundStyle(theme.textMuted)
                        Text(event.label).font(Typo.sans(Typo.sm)).foregroundStyle(theme.text)
                    }
                }
                .padding(.bottom, 16)
            }
        }
        .padding(.leading, 2)
        .background(alignment: .topLeading) {
            Rectangle().fill(theme.border).frame(width: 1).padding(.leading, 5.5).padding(.vertical, 8)
        }
    }

    private func aiInfo(_ exec: AIExecution) -> some View {
        Card {
            LazyVGrid(columns: [GridItem(.flexible(), spacing: 12), GridItem(.flexible(), spacing: 12)], alignment: .leading, spacing: 12) {
                pair("提供商", exec.provider.rawValue, color: theme.ai, mono: false)
                pair("模型", exec.model, mono: false)
                pair("Token 输入", Format.number(exec.tokenInput))
                pair("Token 输出", Format.number(exec.tokenOutput))
                pair("估算费用", Format.cost(exec.estimatedCost))
                pair("工具调用", "\(exec.toolCallCount)")
                pair("修改文件", "\(exec.filesChanged)")
            }
            if let summary = exec.resultSummary {
                Divider1().padding(.top, 12)
                Text(summary).font(Typo.sans(Typo.sm)).foregroundStyle(theme.textSecondary).padding(.top, 12)
            }
        }
    }

    private func pair(_ label: String, _ value: String, color: Color? = nil, mono: Bool = true) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(label).font(Typo.sans(Typo.xs)).foregroundStyle(theme.textMuted)
            Text(value).font(mono ? Typo.mono(Typo.sm) : Typo.sans(Typo.sm)).foregroundStyle(color ?? theme.text)
        }
    }
}
