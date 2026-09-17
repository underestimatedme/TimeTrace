import SwiftUI

/// Today.tsx
struct TodayView: View {
    @Environment(\.theme) private var theme
    @Environment(AppStore.self) private var store
    @Environment(AppRouter.self) private var router

    private var today: String { Format.dayKey(store.now) }

    private func isToday(_ date: Date?) -> Bool {
        guard let date else { return false }
        return Format.dayKey(date) == today
    }

    var body: some View {
        let stats = Stats.todayStats(store.timeSessions, tasks: store.tasks, day: today)
        let humanTask = store.runningHumanTask()
        let aiTasks = store.runningAITasks()
        let waitingTasks = store.waitingHumanTasks()
        let upcoming = store.tasks
            .filter { isToday($0.scheduledStart) && !TaskStatus.terminal.contains($0.status) }
            .sorted { ($0.scheduledStart ?? .distantPast) < ($1.scheduledStart ?? .distantPast) }

        TabPage {
            header.padding(.bottom, 24)

            SectionTitle("现在")
            if humanTask != nil || !aiTasks.isEmpty {
                VStack(spacing: 12) {
                    if let humanTask { humanCard(humanTask) }
                    ForEach(aiTasks) { aiCard($0) }
                }
            } else {
                Card { centered("当前没有进行中的任务") }
            }
            Spacer().frame(height: 24)

            if !waitingTasks.isEmpty {
                SectionTitle("等待你")
                VStack(spacing: 12) { ForEach(waitingTasks) { waitingCard($0) } }
                Spacer().frame(height: 24)
            }

            SectionTitle("接下来")
            if upcoming.isEmpty {
                Card { centered("今天暂无计划任务") }
            } else {
                VStack(spacing: 0) { ForEach(upcoming.prefix(5)) { upcomingRow($0) } }
            }
            Spacer().frame(height: 24)

            SectionTitle("今日数据摘要")
            TwoColumnGrid {
                MetricCard(label: "人工投入", value: Format.duration(stats.human))
                MetricCard(label: "AI 活跃", value: Format.duration(stats.ai))
                MetricCard(label: "等待损耗", value: Format.duration(stats.waiting))
                MetricCard(label: "完成任务", value: "\(stats.completed)")
            }
            Card(borderColor: theme.accent.opacity(0.1)) {
                HStack {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("时间杠杆").font(Typo.sans(Typo.xs)).foregroundStyle(theme.textMuted)
                        Text(Format.leverage(stats.leverage)).font(Typo.mono(Typo.xl)).foregroundStyle(theme.accent)
                    }
                    Spacer()
                    Image(systemName: "bolt").font(.system(size: 20)).foregroundStyle(theme.accent.opacity(0.4))
                }
                Text("AI 活跃时间 ÷ 人工投入时间").font(Typo.sans(Typo.xs)).foregroundStyle(theme.textMuted).padding(.top, 8)
            }
            .padding(.top, 8)
        }
    }

    // MARK: - Pieces

    private var header: some View {
        let completedToday = store.tasks.filter { $0.status == .completed && isToday($0.completedAt) }.count
        let totalToday = store.tasks.filter { $0.dueDate == today || isToday($0.scheduledStart) }.count
        let progress = totalToday > 0 ? Double(completedToday) / Double(totalToday) * 100 : 0
        return VStack(alignment: .leading, spacing: 0) {
            HStack {
                Text(Format.date(store.now)).font(Typo.sans(Typo.xs)).foregroundStyle(theme.textMuted)
                Spacer()
                Button { router.push(.reports(.all)) } label: {
                    HStack(spacing: 3) {
                        Image(systemName: "chart.bar.doc.horizontal").font(.system(size: 12))
                        Text("报告").font(Typo.sans(Typo.xs))
                    }
                    .foregroundStyle(theme.accent)
                }
                .buttonStyle(.plain)
                .accessibilityIdentifier("reports.open")
            }
            .padding(.bottom, 4)
            Text("\(Format.greeting(now: store.now))，\(store.settings.name)")
                .font(Typo.sans(Typo.xl2, weight: .light)).foregroundStyle(theme.text)
            HStack(alignment: .center, spacing: 16) {
                VStack(spacing: 4) {
                    HStack {
                        Text("今日进度")
                        Spacer()
                        Text("\(completedToday)/\(totalToday > 0 ? "\(totalToday)" : "—")").monospacedDigit()
                    }
                    .font(Typo.sans(Typo.xs)).foregroundStyle(theme.textSecondary)
                    ProgressBar(value: progress)
                }
                VStack(alignment: .trailing, spacing: 2) {
                    Text("连续专注").font(Typo.sans(Typo.xs)).foregroundStyle(theme.textMuted)
                    Text("\(store.settings.streakDays) 天").font(Typo.mono(Typo.sm)).foregroundStyle(theme.accent)
                }
            }
            .padding(.top, 12)
        }
    }

    private func centered(_ text: String) -> some View {
        Text(text).font(Typo.sans(Typo.sm)).foregroundStyle(theme.textMuted)
            .frame(maxWidth: .infinity).padding(.vertical, 16)
    }

    private func clockLine(_ text: String) -> some View {
        HStack(spacing: 4) {
            Image(systemName: "clock").font(.system(size: 11))
            Text(text).monospacedDigit()
        }
        .font(Typo.sans(Typo.xs)).foregroundStyle(theme.textMuted).padding(.top, 4)
    }

    private func humanCard(_ task: TaskItem) -> some View {
        Card(borderColor: theme.accent.opacity(0.2)) {
            Text("我正在进行").font(Typo.sans(Typo.xs)).foregroundStyle(theme.accent).padding(.bottom, 4)
            Text(task.title).font(Typo.sans(Typo.sm, weight: .medium)).foregroundStyle(theme.text)
            clockLine("已专注 \(Format.duration(store.focusElapsedSeconds()))")
            HStack(spacing: 8) {
                AppButton("暂停", icon: "pause", variant: .secondary, size: .sm) { router.push(.focus(task.id)) }
                AppButton("完成", icon: "checkmark", variant: .accent, size: .sm) { store.completeFocus() }
                AppButton("详情", variant: .ghost, size: .sm) { router.push(.taskDetail(task.id)) }
            }
            .padding(.top, 12)
        }
    }

    private func aiCard(_ task: TaskItem) -> some View {
        let session = store.timeSessions.first { $0.taskId == task.id && $0.type == .aiActive && $0.endedAt == nil }
        return Card(borderColor: theme.ai.opacity(0.2)) {
            Text("\(task.aiProvider?.rawValue ?? "AI") 正在进行").font(Typo.sans(Typo.xs)).foregroundStyle(theme.ai).padding(.bottom, 4)
            Text(task.title).font(Typo.sans(Typo.sm, weight: .medium)).foregroundStyle(theme.text)
            clockLine("已运行 \(Format.durationOrUnmeasured(session?.durationSeconds))")
            HStack { AppButton("查看执行", variant: .ghost, size: .sm) { router.push(.ai(task.id)) } }.padding(.top, 12)
        }
    }

    private func waitingCard(_ task: TaskItem) -> some View {
        let session = store.timeSessions.first { $0.taskId == task.id && $0.type == .waitingHuman && $0.endedAt == nil }
        // 没有等待会话＝没测到等待时长，按契约显示「未测量」，不能算成 0 秒。
        let waited: Int? = session.map { store.secondsSince($0.startedAt, at: store.now) }
        let provider = task.aiProvider?.rawValue ?? "AI"
        return Card(borderColor: theme.warning.opacity(0.2)) {
            Text(waited.map { "\(provider) 结果待确认 · 已等待 \(Format.duration($0))" }
                 ?? "\(provider) 结果待确认 · 等待时长未测量")
                .font(Typo.sans(Typo.xs)).foregroundStyle(theme.warning).monospacedDigit().padding(.bottom, 4)
            Text(task.title).font(Typo.sans(Typo.sm, weight: .medium)).foregroundStyle(theme.text)
            HStack(spacing: 8) {
                AppButton("立即审核", variant: .accent, size: .sm) { router.push(.taskDetail(task.id)) }
                AppButton("标记完成", variant: .secondary, size: .sm) {
                    if let plan = store.plans(forTask: task.id).first(where: { $0.status == .awaitingReview }) {
                        router.push(.plan(plan.id))
                    } else if store.workspaceClient != nil {
                        router.push(.taskDetail(task.id))
                    } else { store.completeAIReview(task.id) }
                }
            }
            .padding(.top, 12)
        }
    }

    private func upcomingRow(_ task: TaskItem) -> some View {
        let project = store.project(task.projectId)
        return Button { router.push(.taskDetail(task.id)) } label: {
            HStack(spacing: 12) {
                Text(task.scheduledStart.map(Format.time) ?? "")
                    .font(Typo.mono(Typo.xs)).foregroundStyle(theme.accent).frame(width: 48, alignment: .leading)
                VStack(alignment: .leading, spacing: 2) {
                    Text(task.title).font(Typo.sans(Typo.sm)).foregroundStyle(theme.text).lineLimit(1)
                    if let project { Text(project.name).font(Typo.sans(Typo.xs)).foregroundStyle(theme.textMuted) }
                }
                Spacer(minLength: 0)
                Image(systemName: "chevron.right").font(.system(size: 13)).foregroundStyle(theme.textMuted)
            }
            .padding(.vertical, 10).padding(.horizontal, 12)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}
