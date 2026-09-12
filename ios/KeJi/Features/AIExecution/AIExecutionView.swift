import SwiftUI

/// AIExecution.tsx
struct AIExecutionView: View {
    @Environment(\.theme) private var theme
    @Environment(AppStore.self) private var store
    @Environment(AppRouter.self) private var router
    let taskId: String
    @State private var pulse = false

    var body: some View {
        SubPageScaffold(title: "AI 执行") {
            if let task = store.task(taskId) {
                content(task, store.aiExecutions.last { $0.taskId == taskId })
            } else {
                MissingPlaceholder(text: "任务不存在")
            }
        }
        .onAppear { pulse = true }
    }

    private func statusColor(_ status: AIExecutionStatus?) -> Color {
        switch status {
        case .running: return theme.ai
        case .completed: return theme.success
        default: return theme.textMuted
        }
    }

    @ViewBuilder
    private func content(_ task: TaskItem, _ execution: AIExecution?) -> some View {
        let status = execution?.status ?? .queued
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 8) {
                Text(task.aiProvider?.rawValue ?? "AI").font(Typo.sans(Typo.sm, weight: .medium)).foregroundStyle(theme.ai)
                TintPill(text: status.label, color: statusColor(status))
                    .opacity(status == .running && pulse ? 0.6 : 1)
                    .animation(status == .running ? .easeInOut(duration: 1).repeatForever(autoreverses: true) : .default, value: pulse)
            }
            .padding(.bottom, 8)
            Text(task.title).font(Typo.sans(Typo.lg, weight: .medium)).foregroundStyle(theme.text)
            if let step = execution?.currentStep {
                Text("当前步骤: \(step)").font(Typo.sans(Typo.sm)).foregroundStyle(theme.textSecondary).padding(.top, 8)
            }
        }
        .padding(.bottom, 24)

        TwoColumnGrid {
            StatCard(label: "已运行", value: Format.duration(execution?.activeSeconds ?? 0), valueColor: theme.ai, valueSize: Typo.lg)
            StatCard(label: "估算费用", value: Format.cost(execution?.estimatedCost ?? 0), valueSize: Typo.lg)
            StatCard(label: "Token 使用", value: "\(Format.number(execution?.tokenInput ?? 0)) / \(Format.number(execution?.tokenOutput ?? 0))")
            StatCard(label: "工具调用", value: "\(execution?.toolCallCount ?? 0)", valueSize: Typo.lg)
        }
        .padding(.bottom, 24)

        SectionTitle("活动日志")
        Card {
            if let logs = execution?.logs, !logs.isEmpty {
                ScrollView {
                    VStack(alignment: .leading, spacing: 8) {
                        ForEach(Array(logs.enumerated()), id: \.offset) { _, log in
                            HStack(alignment: .top, spacing: 12) {
                                Text(log.time).font(Typo.mono(Typo.sm)).foregroundStyle(theme.textMuted)
                                Text(log.message).font(Typo.sans(Typo.sm)).foregroundStyle(theme.textSecondary)
                            }
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
                .frame(maxHeight: 160)
            } else {
                Text("等待执行...").font(Typo.sans(Typo.sm)).foregroundStyle(theme.textMuted)
                    .frame(maxWidth: .infinity).padding(.vertical, 16)
            }
        }
        .padding(.bottom, 24)

        if let summary = execution?.resultSummary {
            Card(borderColor: theme.success.opacity(0.2)) {
                Text("结果摘要").font(Typo.sans(Typo.xs)).foregroundStyle(theme.success).padding(.bottom, 4)
                Text(summary).font(Typo.sans(Typo.sm)).foregroundStyle(theme.textSecondary)
            }
            .padding(.bottom, 24)
        }
        if let error = execution?.errorMessage {
            Card(borderColor: theme.danger.opacity(0.2)) {
                Text("错误").font(Typo.sans(Typo.xs)).foregroundStyle(theme.danger).padding(.bottom, 4)
                Text(error).font(Typo.sans(Typo.sm)).foregroundStyle(theme.textSecondary)
            }
            .padding(.bottom, 24)
        }

        VStack(spacing: 8) {
            if status == .running, execution != nil {
                HStack(spacing: 8) {
                    AppButton("暂停", icon: "pause", variant: .secondary, fullWidth: true) { store.pauseAIExecution(task.id) }
                    AppButton("取消", icon: "xmark", variant: .danger, fullWidth: true) {
                        store.cancelAIExecution(task.id)
                        router.go(.tasks)
                    }
                }
            }
            if status == .waitingAuth, execution != nil {
                AppButton("授权继续", icon: "shield", variant: .accent, fullWidth: true) { store.authorizeAI(task.id) }
            }
            if status == .waitingInput, execution != nil {
                AppButton("继续执行", icon: "play", variant: .accent, fullWidth: true) { store.authorizeAI(task.id) }
            }
            if task.status == .waitingHuman {
                HStack(spacing: 8) {
                    AppButton("审核完成", icon: "checkmark", variant: .accent, fullWidth: true) {
                        store.completeAIReview(task.id)
                        router.go(.today)
                    }
                    AppButton("查看详情", icon: "eye", variant: .secondary, fullWidth: true) { router.push(.taskDetail(task.id)) }
                }
            }
        }
    }
}
