import SwiftUI

extension ResetProvider {
    /// 与两个工具主题的强调色一致：Codex 绿、Claude 橙。
    var color: Color { self == .codex ? Theme.codex.accent : Theme.claude.accent }
    var badge: String { self == .codex ? "C" : "✳︎" }
}

/// 公共重置日历（数据来自 BetterOPC，经 Valley 缓存）。按用户本地时区分天、周一开头；
/// 每个月显示时按需拉取并缓存在内存里。公共信号不代表个人额度已恢复。
struct ResetCalendarSection: View {
    @Environment(\.theme) private var theme
    @Environment(AppStore.self) private var store
    let response: ResetSignalsResponse
    @State private var month = ResetCalendar.monthStart(Date(), calendar: .current)
    @State private var selectedDay: ResetCalendarDay?
    private let calendar = Calendar.current

    private var monthKey: String { ResetCalendar.monthKey(month, calendar: calendar) }

    var body: some View {
        let events = store.knownResetEvents
        let days = ResetCalendar.days(events: events, month: month, calendar: calendar)
        SectionTitle("公共重置日历")
        Card(padding: 16, radius: Glass.groupRadius) {
            HStack {
                monthButton("chevron.left", label: "上个月", id: "reset.prevMonth", by: -1)
                Spacer()
                Text(ResetCalendar.monthTitle(month, calendar: calendar))
                    .font(Typo.sans(Glass.body, weight: .semibold)).foregroundStyle(theme.text)
                    .accessibilityIdentifier("reset.monthTitle")
                Spacer()
                monthButton("chevron.right", label: "下个月", id: "reset.nextMonth", by: 1)
            }
            .padding(.bottom, 10)

            // 一个月最多 42 格，不用 Lazy：滚出屏幕的行也要留在无障碍树里。
            VStack(spacing: 4) {
                HStack(spacing: 4) {
                    ForEach(ResetCalendar.weekdaySymbols, id: \.self) { symbol in
                        Text(symbol).font(Typo.sans(Typo.xs)).foregroundStyle(theme.textMuted)
                            .frame(maxWidth: .infinity)
                    }
                }
                ForEach(weeks(days), id: \.self) { week in
                    HStack(spacing: 4) {
                        ForEach(0..<7, id: \.self) { column in
                            if let index = week[column], days.indices.contains(index) {
                                let day = days[index]
                                Button { if !day.events.isEmpty { selectedDay = day } } label: { dayCell(day) }
                                    .buttonStyle(.plain)
                                    .accessibilityLabel(accessibilityLabel(day))
                                    .accessibilityIdentifier("reset.day.\(day.key)")
                            } else {
                                Color.clear.frame(maxWidth: .infinity, minHeight: 46).accessibilityHidden(true)
                            }
                        }
                    }
                }
            }
            .accessibilityElement(children: .contain)
            .accessibilityIdentifier("reset.calendar")

            HStack(spacing: 12) {
                ForEach(ResetProvider.allCases, id: \.self) { provider in
                    HStack(spacing: 4) { badge(provider); Text("\(provider.label) 已重置") }
                }
                HStack(spacing: 4) { announcementDot; Text("公告") }
            }
            .font(Typo.sans(Typo.xs)).foregroundStyle(theme.textMuted)
            .padding(.top, 10)
        }
        Text(ResetCalendar.latestResetSummary(events: events, calendar: calendar))
            .font(Typo.sans(Glass.small)).foregroundStyle(theme.textSecondary)
            .padding(.top, 10)
            .accessibilityIdentifier("reset.summary")
        Text(response.note.isEmpty ? "公共信号不代表你的个人额度已恢复。" : response.note)
            .font(Typo.sans(Glass.small)).foregroundStyle(theme.textMuted)
            .padding(.top, 4)
            .accessibilityIdentifier("reset.note")
        VStack(alignment: .leading, spacing: 4) {
            ForEach(response.sources) { source in
                Link(destination: source.url) {
                    HStack(spacing: 4) {
                        Text("数据来源：\(source.name)")
                        Image(systemName: "arrow.up.right").font(.system(size: 11)).accessibilityHidden(true)
                    }
                    .font(Typo.sans(Glass.small))
                }
                .accessibilityIdentifier("reset.source.\(source.name)")
            }
        }
        .padding(.top, 4).padding(.bottom, 24)
        .task(id: monthKey) { await store.loadResetMonth(month, calendar: calendar) }
        .sheet(item: $selectedDay) { day in ResetDaySheet(day: day, calendar: calendar) }
    }

    /// 周一开头按周切行：每格是 days 的下标，前后空格为 nil。
    private func weeks(_ days: [ResetCalendarDay]) -> [[Int?]] {
        let cells: [Int?] = Array(repeating: nil, count: ResetCalendar.leadingBlanks(month: month, calendar: calendar))
            + days.indices.map { Optional($0) }
        let padded = cells + Array(repeating: nil, count: (7 - cells.count % 7) % 7)
        return stride(from: 0, to: padded.count, by: 7).map { Array(padded[$0..<$0 + 7]) }
    }

    private func monthButton(_ symbol: String, label: String, id: String, by delta: Int) -> some View {
        Button { month = ResetCalendar.shift(month, by: delta, calendar: calendar) } label: {
            Image(systemName: symbol).font(.system(size: 14, weight: .semibold))
                .foregroundStyle(theme.textSecondary)
                .frame(width: 36, height: 32)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(label)
        .accessibilityIdentifier(id)
    }

    private func dayCell(_ day: ResetCalendarDay) -> some View {
        let isToday = calendar.isDateInToday(day.date)
        return VStack(spacing: 3) {
            Text("\(day.day)")
                .font(Typo.sans(Typo.sm, weight: isToday ? .semibold : .regular))
                .monospacedDigit()
                .foregroundStyle(isToday ? theme.accent : (day.events.isEmpty ? theme.textSecondary : theme.text))
            HStack(spacing: 2) {
                ForEach(day.confirmedProviders, id: \.self) { badge($0) }
                if day.confirmedProviders.isEmpty && day.hasAnnouncement { announcementDot }
            }
            .frame(height: 14)
        }
        .frame(maxWidth: .infinity, minHeight: 46)
        .background(RoundedRectangle(cornerRadius: 10)
            .fill(day.events.isEmpty ? Color.clear : theme.text.opacity(0.05)))
        .overlay(RoundedRectangle(cornerRadius: 10)
            .stroke(isToday ? theme.accent.opacity(0.5) : Color.clear, lineWidth: 1))
        .contentShape(Rectangle())
    }

    private func badge(_ provider: ResetProvider) -> some View {
        Text(provider.badge)
            .font(.system(size: 9, weight: .bold))
            .foregroundStyle(.white)
            .frame(width: 14, height: 14)
            .background(Circle().fill(provider.color))
            .accessibilityHidden(true)
    }

    private var announcementDot: some View {
        Circle().fill(theme.textMuted.opacity(0.6)).frame(width: 5, height: 5).accessibilityHidden(true)
    }

    private func accessibilityLabel(_ day: ResetCalendarDay) -> String {
        var parts = [ResetCalendar.dayTitle(day.date, calendar: calendar)]
        parts += day.confirmedProviders.map { "\($0.label) 已重置" }
        if day.hasAnnouncement { parts.append("有公告") }
        return parts.joined(separator: "，")
    }
}

/// 点开某一天：列出当天每条公共事件。
struct ResetDaySheet: View {
    @Environment(\.theme) private var theme
    @Environment(\.dismiss) private var dismiss
    let day: ResetCalendarDay
    let calendar: Calendar

    var body: some View {
        NavigationStack {
            List(day.events) { event in
                VStack(alignment: .leading, spacing: 6) {
                    HStack(alignment: .firstTextBaseline) {
                        if let provider = event.resetProvider {
                            Circle().fill(provider.color).frame(width: 8, height: 8).accessibilityHidden(true)
                        }
                        Text(event.productName).font(Typo.sans(Glass.body, weight: .semibold))
                        Spacer(minLength: 8)
                        Text(ResetCalendar.timeText(event.occurredAt, calendar: calendar))
                            .font(Typo.sans(Glass.small)).monospacedDigit().foregroundStyle(theme.textSecondary)
                    }
                    TintPill(text: event.kindLabel, color: event.isConfirmedReset ? theme.success : theme.warning)
                    if !event.text.isEmpty {
                        Text(event.text).font(Typo.sans(Glass.small)).foregroundStyle(theme.textSecondary)
                    }
                    if let url = event.sourceUrl {
                        Link("查看来源", destination: url).font(Typo.sans(Glass.small))
                    }
                }
                .padding(.vertical, 4)
                .accessibilityElement(children: .contain)
                .accessibilityIdentifier("reset.event.\(event.id)")
            }
            .navigationTitle(ResetCalendar.dayTitle(day.date, calendar: calendar))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .cancellationAction) { Button("关闭") { dismiss() } } }
        }
        .presentationDetents([.medium, .large])
    }
}
