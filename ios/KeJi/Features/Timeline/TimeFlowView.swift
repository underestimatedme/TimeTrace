import SwiftUI

/// Timeline.tsx (named TimeFlowView to avoid SwiftUI.TimelineView).
struct TimeFlowView: View {
    @Environment(\.theme) private var theme
    @Environment(AppStore.self) private var store

    enum Range: String, CaseIterable { case today, week }
    /// 设计稿的轨道筛选：全部 / 我 / AI。
    enum Lane: String, CaseIterable {
        case all, human, ai
        var label: String { switch self { case .all: return "全部"; case .human: return "我"; case .ai: return "AI" } }
    }
    @State private var range: Range = .today
    @State private var lane: Lane = .all
    @State private var projectId: String?

    static func color(for type: TimeSessionType, theme: Theme) -> Color {
        switch type {
        case .humanFocus: return theme.accent.opacity(0.6)
        case .humanReview: return theme.accent.opacity(0.4)
        case .aiActive: return theme.ai.opacity(0.6)
        case .aiIdle: return theme.ai.opacity(0.3)
        case .waitingHuman: return theme.warning.opacity(0.5)
        case .waitingAI: return theme.warning.opacity(0.3)
        case .waitingExternal: return theme.warning.opacity(0.2)
        case .interruption: return theme.danger.opacity(0.4)
        case .rework: return theme.danger.opacity(0.3)
        }
    }

    var body: some View {
        let today = Format.dayKey(store.now)
        let weekStart = Format.dayKey(Format.calendar.date(byAdding: .day, value: -6, to: store.now) ?? store.now)
        let filtered = store.timeSessions
            .filter { range == .today ? Format.dayKey($0.startedAt) == today : Format.dayKey($0.startedAt) >= weekStart }
            .sorted { $0.startedAt < $1.startedAt }
        let parallel = Stats.parallelStats(store.timeSessions, day: range == .today ? today : nil)
        let lanes = TimelineLanes(sessions: filtered, tasks: store.tasks,
                                  scope: projectId.map { ReportScope.project($0) } ?? .all)

        TabPage {
            PageTitle(title: "时间线").padding(.bottom, 16)

            HStack(spacing: 8) {
                PillChip(label: "今天", selected: range == .today, horizontalPadding: 16) { range = .today }
                PillChip(label: "本周", selected: range == .week, horizontalPadding: 16) { range = .week }
                Spacer(minLength: 8)
                Menu {
                    Button("全部项目") { projectId = nil }
                    ForEach(store.projects) { project in
                        Button(project.name) { projectId = project.id }
                    }
                } label: {
                    HStack(spacing: 4) {
                        Text(projectId.flatMap { id in store.projects.first { $0.id == id }?.name } ?? "全部项目")
                            .font(Typo.sans(Typo.xs)).lineLimit(1)
                        Image(systemName: "chevron.down").font(.system(size: 10))
                    }
                    .foregroundStyle(theme.accent)
                }
                .accessibilityIdentifier("timeline.project")
            }
            .padding(.bottom, 12)

            GlassSegments(options: Lane.allCases.map { ($0, $0.label) }, selection: $lane)
                .padding(.bottom, 16)
                .accessibilityIdentifier("timeline.lane")

            TwoColumnGrid {
                MetricCard(label: "实际经过", value: Format.duration(parallel.wallClockSeconds))
                MetricCard(label: "并发峰值", value: "\(parallel.concurrencyPeak)")
                MetricCard(label: "人工工作量", value: Format.duration(parallel.humanWorkloadSeconds))
                MetricCard(label: "AI 工作量", value: Format.duration(parallel.aiWorkloadSeconds))
            }
            .padding(.bottom, 24)

            SectionTitle("时间线")
            if lanes.isEmpty {
                Card {
                    Text("这个范围还没有时间记录").font(Typo.sans(Typo.sm)).foregroundStyle(theme.textMuted)
                        .frame(maxWidth: .infinity).padding(.vertical, 32)
                }
            } else {
                HStack(alignment: .top, spacing: 12) {
                    if lane != .ai {
                        laneColumn(title: "我", sessions: lanes.human, color: theme.accent, empty: "无人工记录")
                    }
                    if lane != .human {
                        laneColumn(title: "AI 工作", sessions: lanes.ai + lanes.waiting, color: theme.ai, empty: "无 AI 记录")
                    }
                }
                Text(lanes.summaryText)
                    .font(Typo.sans(Typo.xs)).foregroundStyle(theme.textMuted)
                    .padding(.top, 16)
                    .accessibilityIdentifier("timeline.summary")
            }

            SectionTitle("图例").padding(.top, 24)
            legend
        }
    }

    /// 一条轨一列：块里写任务名、类型和时长；等待用独立配色，且有文字标注。
    private func laneColumn(title: String, sessions: [TimeSession], color: Color, empty: String) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title).font(Typo.sans(Typo.xs, weight: .medium)).foregroundStyle(theme.textSecondary)
            if sessions.isEmpty {
                Text(empty).font(Typo.sans(Typo.xs)).foregroundStyle(theme.textMuted)
            }
            ForEach(sessions) { session in
                let waiting = Stats.waitingTypes.contains(session.type)
                Card(borderColor: (waiting ? theme.warning : color).opacity(0.25), padding: 12, radius: 12) {
                    Text(session.type.label)
                        .font(Typo.sans(Typo.xs))
                        .foregroundStyle(waiting ? theme.warning : color)
                    Text(store.task(session.taskId)?.title ?? "未知任务")
                        .font(Typo.sans(Typo.sm, weight: .medium)).foregroundStyle(theme.text)
                        .lineLimit(2).padding(.top, 4)
                    Text("\(Format.time(session.startedAt)) · \(Format.duration(session.durationSeconds))")
                        .font(Typo.sans(Typo.xs)).foregroundStyle(theme.textMuted).padding(.top, 4)
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func sessionRow(_ session: TimeSession) -> some View {
        let color = TimeFlowView.color(for: session.type, theme: theme)
        let title = store.task(session.taskId)?.title ?? "未知任务"
        return VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 12) {
                Text(session.startedAt.formatted(.dateTime.hour().minute()) + (session.endedAt.map { "–\(Format.time($0))" } ?? ""))
                    .font(Typo.mono(Typo.xs)).foregroundStyle(theme.textMuted)
                    .frame(width: 96, alignment: .leading).lineLimit(1).minimumScaleFactor(0.8)
                GeometryReader { geo in
                    let pos = position(session, width: geo.size.width)
                    ZStack(alignment: .leading) {
                        RoundedRectangle(cornerRadius: 8, style: .continuous).fill(theme.bgElevated)
                        RoundedRectangle(cornerRadius: 6, style: .continuous).fill(color)
                            .frame(width: pos.width).offset(x: pos.left).padding(.vertical, 4)
                    }
                    .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                }
                .frame(height: 32)
            }
            .padding(.vertical, 8)
            HStack(spacing: 8) {
                Text(session.type.label).font(Typo.sans(Typo.xs)).foregroundStyle(theme.bg)
                    .padding(.horizontal, 6).padding(.vertical, 2).background(color)
                    .clipShape(RoundedRectangle(cornerRadius: 4, style: .continuous))
                Text(title).font(Typo.sans(Typo.xs)).foregroundStyle(theme.textSecondary).lineLimit(1)
                Spacer(minLength: 0)
                Text(Format.duration(session.durationSeconds)).font(Typo.sans(Typo.xs)).foregroundStyle(theme.textMuted)
            }
            .padding(.leading, 108)
            .padding(.top, -4)
            .padding(.bottom, 8)
        }
    }

    /// Position within the session's own 24h day (the prototype uses the first session's day).
    private func position(_ session: TimeSession, width: CGFloat) -> (left: CGFloat, width: CGFloat) {
        let dayStart = Format.calendar.startOfDay(for: session.startedAt)
        let day: TimeInterval = 24 * 3600
        let s = session.startedAt.timeIntervalSince(dayStart)
        let e = (session.endedAt ?? store.now).timeIntervalSince(dayStart)
        let left = max(0, min(1, s / day)) * width
        let w = max((e - s) / day * width, width * 0.005)
        return (left, min(w, width - left))
    }

    private var legend: some View {
        FlowLayout(spacing: 8) {
            ForEach(TimeSessionType.allCases, id: \.self) { type in
                HStack(spacing: 6) {
                    RoundedRectangle(cornerRadius: 3).fill(TimeFlowView.color(for: type, theme: theme)).frame(width: 12, height: 12)
                    Text(type.label).font(Typo.sans(Typo.xs)).foregroundStyle(theme.textMuted)
                }
            }
        }
    }
}

/// Minimal wrapping HStack (`flex-wrap gap-2`).
struct FlowLayout: Layout {
    var spacing: CGFloat = 8

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let width = proposal.width ?? .infinity
        var x: CGFloat = 0, y: CGFloat = 0, rowHeight: CGFloat = 0
        for view in subviews {
            let size = view.sizeThatFits(.unspecified)
            if x + size.width > width, x > 0 { x = 0; y += rowHeight + spacing; rowHeight = 0 }
            x += size.width + spacing
            rowHeight = max(rowHeight, size.height)
        }
        return CGSize(width: width == .infinity ? x : width, height: y + rowHeight)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        var x = bounds.minX, y = bounds.minY, rowHeight: CGFloat = 0
        for view in subviews {
            let size = view.sizeThatFits(.unspecified)
            if x + size.width > bounds.maxX, x > bounds.minX { x = bounds.minX; y += rowHeight + spacing; rowHeight = 0 }
            view.place(at: CGPoint(x: x, y: y), proposal: ProposedViewSize(size))
            x += size.width + spacing
            rowHeight = max(rowHeight, size.height)
        }
    }
}
