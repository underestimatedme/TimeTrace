import Foundation

/// 公共重置日历里的一天（用户本地时区）。
struct ResetCalendarDay: Identifiable, Equatable {
    var date: Date
    /// 本地 yyyy-MM-dd
    var key: String
    var day: Int
    /// 当天有 confirmed_reset 的工具，Codex 在前。
    var confirmedProviders: [ResetProvider]
    /// 当天还有不是「已重置」的公告。
    var hasAnnouncement: Bool
    /// 当天全部事件，按时间先后。
    var events: [ResetEvent]
    var id: String { key }
}

/// 把服务端（UTC）的事件按用户本地日历分到每一天。纯函数，时区由调用方的 Calendar 决定。
enum ResetCalendar {
    static let weekdaySymbols = ["一", "二", "三", "四", "五", "六", "日"]

    private static func formatter(_ pattern: String, _ calendar: Calendar) -> DateFormatter {
        let f = DateFormatter()
        f.locale = Locale(identifier: "zh_CN")
        f.calendar = calendar
        f.timeZone = calendar.timeZone
        f.dateFormat = pattern
        return f
    }

    static func monthStart(_ date: Date, calendar: Calendar) -> Date {
        calendar.date(from: calendar.dateComponents([.year, .month], from: date)) ?? date
    }

    static func shift(_ month: Date, by months: Int, calendar: Calendar) -> Date {
        monthStart(calendar.date(byAdding: .month, value: months, to: monthStart(month, calendar: calendar)) ?? month,
                   calendar: calendar)
    }

    static func monthKey(_ month: Date, calendar: Calendar) -> String {
        formatter("yyyy-MM", calendar).string(from: month)
    }

    static func monthTitle(_ month: Date, calendar: Calendar) -> String {
        formatter("yyyy年M月", calendar).string(from: month)
    }

    static func dayTitle(_ date: Date, calendar: Calendar) -> String {
        formatter("M月d日", calendar).string(from: date)
    }

    static func timeText(_ date: Date, calendar: Calendar) -> String {
        formatter("HH:mm", calendar).string(from: date)
    }

    /// 周一开头的网格里，1 号前面要空几格。
    static func leadingBlanks(month: Date, calendar: Calendar) -> Int {
        let weekday = calendar.component(.weekday, from: monthStart(month, calendar: calendar)) // 1 = 周日
        return (weekday + 5) % 7
    }

    /// 服务端的天是 UTC：本地月份前后各多要一天，保证任何时区下都拿全。
    static func fetchRange(month: Date, calendar: Calendar) -> (from: String, to: String) {
        let start = monthStart(month, calendar: calendar)
        let days = calendar.range(of: .day, in: .month, for: start)?.count ?? 31
        let from = calendar.date(byAdding: .day, value: -1, to: start) ?? start
        let to = calendar.date(byAdding: .day, value: days, to: start) ?? start
        let f = formatter("yyyy-MM-dd", calendar)
        return (f.string(from: from), f.string(from: to))
    }

    static func days(events: [ResetEvent], month: Date, calendar: Calendar) -> [ResetCalendarDay] {
        let start = monthStart(month, calendar: calendar)
        let count = calendar.range(of: .day, in: .month, for: start)?.count ?? 0
        let keyFormatter = formatter("yyyy-MM-dd", calendar)
        var byKey: [String: [ResetEvent]] = [:]
        for event in events { byKey[keyFormatter.string(from: event.occurredAt), default: []].append(event) }
        return (0..<count).compactMap { offset in
            guard let date = calendar.date(byAdding: .day, value: offset, to: start) else { return nil }
            let key = keyFormatter.string(from: date)
            let dayEvents = (byKey[key] ?? []).sorted { $0.occurredAt < $1.occurredAt }
            let confirmed = Set(dayEvents.filter(\.isConfirmedReset).compactMap(\.resetProvider))
            return ResetCalendarDay(date: date, key: key, day: offset + 1,
                                    confirmedProviders: ResetProvider.allCases.filter(confirmed.contains),
                                    hasAnnouncement: dayEvents.contains { !$0.isConfirmedReset },
                                    events: dayEvents)
        }
    }

    /// 「最近一次重置：Codex 9月23日 02:23 · Claude 7月16日 11:58」，只算 confirmed_reset。
    static func latestResetSummary(events: [ResetEvent], calendar: Calendar) -> String {
        let parts: [String] = ResetProvider.allCases.compactMap { provider in
            guard let latest = events.filter({ $0.isConfirmedReset && $0.resetProvider == provider })
                .map(\.occurredAt).max() else { return nil }
            return "\(provider.label) \(dayTitle(latest, calendar: calendar)) \(timeText(latest, calendar: calendar))"
        }
        return parts.isEmpty ? "最近没有已确认的公共重置" : "最近一次重置：" + parts.joined(separator: " · ")
    }
}
