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
            header.padding(.bottom, 14)

            collaborationFlow(waiting: waitingTasks.first, ai: aiTasks.first)
                .padding(.bottom, 19)

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
                        .accessibilityHidden(true)
                }
                Text("AI 活跃时间 ÷ 人工投入时间").font(Typo.sans(Typo.xs)).foregroundStyle(theme.textMuted).padding(.top, 8)
            }
            .padding(.top, 8)
        }
    }

    // MARK: - Pieces

    /// .gl-home-header + .gl-hero —— 30px 问候语、42px 头像、183px 雪山 banner 与目标进度格。
    private var header: some View {
        let completedToday = store.tasks.filter { $0.status == .completed && isToday($0.completedAt) }.count
        let totalToday = store.tasks.filter { $0.dueDate == today || isToday($0.scheduledStart) }.count
        let goal = store.goals.first { $0.status == .active } ?? store.goals.first
        return VStack(alignment: .leading, spacing: 0) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 0) {
                    Text(Format.date(store.now))
                        .font(Typo.sans(Glass.small)).foregroundStyle(theme.textMuted)
                        .padding(.bottom, 3)
                    Text("\(Format.greeting(now: store.now))，\(store.settings.name)")
                        .font(Typo.sans(Glass.display, weight: .bold))
                        .kerning(Glass.displayTracking)
                        .foregroundStyle(theme.text)
                        .lineLimit(2).minimumScaleFactor(0.7)
                }
                Spacer(minLength: 12)
                HStack(spacing: 14) {
                    Button { router.push(.reports(.all)) } label: {
                        VStack(spacing: 2) {
                            Image(systemName: "chart.bar.doc.horizontal").font(.system(size: 20, weight: .light))
                            Text("报告").font(Typo.sans(Glass.tiny))
                        }
                        .foregroundStyle(theme.accent)
                        .frame(width: 44, height: 44)
                        .background(theme.panel, in: RoundedRectangle(cornerRadius: Glass.buttonRadius, style: .continuous))
                        .overlay(RoundedRectangle(cornerRadius: Glass.buttonRadius, style: .continuous)
                            .stroke(theme.border, lineWidth: 1))
                    }
                    .buttonStyle(.plain)
                    .accessibilityIdentifier("reports.open")
                    avatar
                }
            }
            .padding(.bottom, 14)

            hero(goal: goal, completed: completedToday, total: totalToday)
        }
    }

    /// .gl-collaboration —— 「我 · 验收」与「AI · 执行」两端，中间是设计稿的光带。
    /// 两端都按真实数据显示：没有待验收就说已确认，没有 AI 执行就说当前空闲。
    @ViewBuilder
    private func collaborationFlow(waiting: TaskItem?, ai: TaskItem?) -> some View {
        HStack(alignment: .center, spacing: 4) {
            Button {
                if let waiting { router.push(.taskDetail(waiting.id)) } else { router.push(.reports(.all)) }
            } label: {
                HStack(spacing: 10) {
                    GlassOrb(symbol: "checkmark")
                    VStack(alignment: .leading, spacing: 2) {
                        Text("我 · 验收").font(Typo.sans(Glass.small, weight: .semibold)).foregroundStyle(theme.text)
                        Text(waiting == nil ? "暂无待确认" : "确认数据与结果")
                            .font(Typo.sans(Glass.tiny)).foregroundStyle(theme.textSecondary)
                    }
                }
            }
            .buttonStyle(.plain)

            Image("collaboration-ribbon")
                .resizable().scaledToFit()
                .frame(height: 26)
                .layoutPriority(-1)
                .accessibilityHidden(true)

            Button { router.go(.ai) } label: {
                HStack(spacing: 10) {
                    GlassOrb(symbol: "arrow.triangle.2.circlepath", soft: true)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(ai.flatMap { $0.aiProvider?.label } ?? "AI")
                            .font(Typo.sans(Glass.small, weight: .semibold)).foregroundStyle(theme.text)
                        Text(ai == nil ? "当前空闲" : "正在执行")
                            .font(Typo.sans(Glass.tiny)).foregroundStyle(theme.textSecondary)
                    }
                }
            }
            .buttonStyle(.plain)
        }
        .frame(maxWidth: .infinity, minHeight: 53, alignment: .leading)
    }

    /// .gl-avatar —— 白边 + 冰蓝光圈。
    private var avatar: some View {
        Button { router.go(.mine) } label: {
            Image("avatar")
                .resizable().scaledToFill()
                .frame(width: 42, height: 42)
                .clipShape(Circle())
                .overlay(Circle().stroke(Color.white, lineWidth: 2))
                .overlay(Circle().stroke(theme.accent.opacity(0.35), lineWidth: 1).padding(-2))
        }
        .buttonStyle(.plain)
        .accessibilityLabel("我的")
    }

    /// .gl-hero —— 雪山 banner 上叠版本目标与进度格。
    /// banner 放在 background 里：它不参与布局尺寸，否则 scaledToFill 会把整页撑宽。
    private func hero(goal: Goal?, completed: Int, total: Int) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            Text(goal == nil ? "今天" : "版本目标")
                .font(Typo.sans(Glass.small)).foregroundStyle(theme.textSecondary)
            Text(goal?.title ?? "先定一个目标")
                .font(Typo.sans(Glass.cardTitle, weight: .semibold))
                .kerning(-0.7)
                .foregroundStyle(theme.text)
                .lineLimit(2)
                .padding(.top, 6)
            Text(total > 0 ? "今日进度 \(completed)/\(total)" : "今天还没有安排任务")
                .font(Typo.sans(Glass.body)).foregroundStyle(theme.textSecondary)
                .padding(.top, 2)
            // .gl-goal-progress —— 用格子而不是一条进度条
            HStack(spacing: 3) {
                ForEach(0..<8, id: \.self) { index in
                    let filled = total > 0 && Double(index) < (Double(completed) / Double(total) * 8)
                    Capsule().fill(filled ? theme.accent : theme.border).frame(height: 6)
                }
            }
            .frame(width: 156)
            .padding(.top, 9)
            Spacer(minLength: 0)
            Text("连续专注 \(store.settings.streakDays) 天")
                .font(Typo.sans(Glass.tiny)).foregroundStyle(theme.textMuted)
        }
        .padding(20)
        .frame(maxWidth: .infinity, alignment: .leading)
        .frame(height: 183)
        .background(alignment: .trailing) {
            // .gl-app[data-theme=dark] .gl-hero>img{opacity:.26} —— 深色下压暗，保证文字可读
            Image("mountain-banner")
                .resizable()
                .aspectRatio(contentMode: .fill)
                .opacity(theme.isDark ? 0.26 : 1)
                .allowsHitTesting(false)
        }
        .clipShape(RoundedRectangle(cornerRadius: Glass.cardRadius, style: .continuous))
        .accessibilityElement(children: .combine)
    }

    private func centered(_ text: String) -> some View {
        Text(text).font(Typo.sans(Typo.sm)).foregroundStyle(theme.textMuted)
            .frame(maxWidth: .infinity).padding(.vertical, 16)
    }

    private func clockLine(_ text: String) -> some View {
        HStack(spacing: 4) {
            Image(systemName: "clock").font(.system(size: 11)).accessibilityHidden(true)
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
            Text("\(task.aiProvider?.label ?? "AI") 正在进行").font(Typo.sans(Typo.xs)).foregroundStyle(theme.ai).padding(.bottom, 4)
            Text(task.title).font(Typo.sans(Typo.sm, weight: .medium)).foregroundStyle(theme.text)
            clockLine("已运行 \(Format.durationOrUnmeasured(session?.durationSeconds))")
            HStack { AppButton("查看执行", variant: .ghost, size: .sm) { router.push(.ai(task.id)) } }.padding(.top, 12)
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel("\(task.aiProvider?.label ?? "AI") 正在进行：\(task.title)")
    }

    private func waitingCard(_ task: TaskItem) -> some View {
        let session = store.timeSessions.first { $0.taskId == task.id && $0.type == .waitingHuman && $0.endedAt == nil }
        // 没有等待会话＝没测到等待时长，按契约显示「未测量」，不能算成 0 秒。
        let waited: Int? = session.map { store.secondsSince($0.startedAt, at: store.now) }
        let provider = task.aiProvider?.label ?? "AI"
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
                Image(systemName: "chevron.right").font(.system(size: 13)).foregroundStyle(theme.textMuted).accessibilityHidden(true)
            }
            .padding(.vertical, 10).padding(.horizontal, 12)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}
