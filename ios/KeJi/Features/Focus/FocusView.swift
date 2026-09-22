import SwiftUI

/// Focus.tsx: ring progress, pause reasons, 标记被打断, note.
struct FocusView: View {
    @Environment(\.theme) private var theme
    @Environment(AppStore.self) private var store
    @Environment(AppRouter.self) private var router
    let taskId: String

    private let pauseReasons = ["临时休息", "收到消息", "开会", "等待 AI", "切换任务", "其他"]
    @State private var showPauseMenu = false
    @State private var note = ""

    var body: some View {
        SubPageScaffold(title: "专注计时") {
            if let task = store.task(taskId) {
                content(task)
            } else {
                MissingPlaceholder(text: "任务不存在")
            }
        }
    }

    private func elapsed(for task: TaskItem) -> Int {
        guard let focus = store.activeFocus, focus.taskId == task.id else { return 0 }
        return store.focusElapsedSeconds()
    }

    @ViewBuilder
    private func content(_ task: TaskItem) -> some View {
        let project = store.project(task.projectId)
        let elapsed = elapsed(for: task)
        let target = task.estimatedMinutes * 60
        let remaining = max(0, target - elapsed)
        let progress = target > 0 ? Double(elapsed) / Double(target) : 0
        let todayTotal = Stats.humanSeconds(store.timeSessions, day: Format.dayKey(store.now), asOf: store.now)

        VStack(spacing: 0) {
            if let project {
                Text("\(project.icon) \(project.name)").font(Typo.sans(Typo.xs)).foregroundStyle(theme.textMuted).padding(.bottom, 8)
            }
            Text(task.title).font(Typo.sans(Typo.lg, weight: .medium)).foregroundStyle(theme.text)
                .multilineTextAlignment(.center).padding(.bottom, 32)

            ZStack {
                Circle().stroke(theme.border, lineWidth: 6)
                Circle()
                    .trim(from: 0, to: CGFloat(min(1, progress)))
                    .stroke(theme.accent, style: StrokeStyle(lineWidth: 6, lineCap: .round))
                    .rotationEffect(.degrees(-90))
                    .animation(.linear(duration: 1), value: progress)
                VStack(spacing: 4) {
                    Text(Format.duration(elapsed)).font(Typo.mono(Typo.xl3)).foregroundStyle(theme.accent)
                        .lineLimit(1).minimumScaleFactor(0.5)
                    Text("剩余 \(Format.duration(remaining))").font(Typo.sans(Typo.xs)).foregroundStyle(theme.textMuted)
                }
                .padding(.horizontal, 20)
            }
            .frame(width: 192, height: 192)
            .padding(.bottom, 32)

            Card {
                Text("今日累计专注").font(Typo.sans(Typo.xs)).foregroundStyle(theme.textMuted)
                Text(Format.duration(todayTotal)).font(Typo.mono(Typo.lg)).foregroundStyle(theme.text)
            }
            .padding(.bottom, 24)
        }
        .padding(.vertical, 32)

        if showPauseMenu {
            VStack(spacing: 8) {
                Text("选择暂停原因").font(Typo.sans(Typo.sm)).foregroundStyle(theme.textSecondary)
                    .frame(maxWidth: .infinity, alignment: .leading).padding(.bottom, 4)
                ForEach(pauseReasons, id: \.self) { reason in
                    AppButton(reason, variant: .secondary, fullWidth: true) { pause(reason) }
                }
                AppButton("取消", variant: .ghost, fullWidth: true) { showPauseMenu = false }
            }
        } else {
            VStack(spacing: 8) {
                HStack(spacing: 8) {
                    AppButton("暂停", icon: "pause", variant: .secondary, fullWidth: true) { showPauseMenu = true }
                    AppButton("完成", icon: "checkmark", variant: .accent, fullWidth: true) {
                        store.completeFocus(note: note.isEmpty ? nil : note)
                        router.go(.today)
                    }
                }
                AppButton("标记被打断", icon: "exclamationmark.triangle", variant: .ghost, fullWidth: true) {
                    store.markInterruption(reason: "被打断")
                    showPauseMenu = true
                }
                AppTextEditor(placeholder: "添加备注...", text: $note, minHeight: 64).padding(.top, 8)
            }
        }
    }

    private func pause(_ reason: String) {
        store.pauseFocus(reason: reason)
        showPauseMenu = false
        router.go(.today)
    }
}
