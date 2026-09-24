import Foundation

/// Port of design/src/lib/format.ts.
enum Format {
    static var calendar: Calendar { Calendar.current }

    private static func formatter(_ pattern: String) -> DateFormatter {
        let f = DateFormatter()
        f.locale = Locale(identifier: "zh_CN")
        f.calendar = calendar
        f.dateFormat = pattern
        return f
    }

    private static let dayKeyFormatter = formatter("yyyy-MM-dd")
    private static let timeFormatter = formatter("HH:mm")
    private static let dateFormatter = formatter("M月d日 EEEE")
    private static let dateShortFormatter = formatter("M/d")
    private static let numberFormatter: NumberFormatter = {
        let f = NumberFormatter()
        f.numberStyle = .decimal
        f.locale = Locale(identifier: "en_US")
        return f
    }()

    /// `1 小时 5 分钟` / `5 分 3 秒` / `5 分钟` / `42 秒`
    static func duration(_ seconds: Int) -> String {
        let s0 = max(0, seconds)
        let h = s0 / 3600
        let m = (s0 % 3600) / 60
        let s = s0 % 60
        if h > 0 { return "\(h) 小时 \(m) 分钟" }
        if m > 0 { return s > 0 ? "\(m) 分 \(s) 秒" : "\(m) 分钟" }
        return "\(s) 秒"
    }

    static func duration(_ seconds: Double) -> String { duration(Int(seconds.rounded(.down))) }

    /// `nil` 表示没有测量到，按数据契约必须显示「未测量」——不能 `?? 0` 渲染成「0 秒」。
    static func durationOrUnmeasured(_ seconds: Int?) -> String {
        guard let seconds else { return "未测量" }
        return duration(seconds)
    }

    static func durationShort(_ seconds: Int) -> String {
        let h = seconds / 3600
        let m = (seconds % 3600) / 60
        if h > 0 { return "\(h)h \(m)m" }
        return "\(m)m"
    }

    private static let weekdayTimeFormatter = formatter("EEE HH:mm")
    private static let dateTimeFormatter = formatter("M月d日 HH:mm")

    /// 绝对重置时刻：今天 → 「今天 14:00」；7 天内 → 「周三 14:00」；更远 → 「9月27日 14:00」。
    static func resetMoment(_ date: Date, now: Date = Date()) -> String {
        if calendar.isDate(date, inSameDayAs: now) { return "今天 " + time(date) }
        if date.timeIntervalSince(now) < 7 * 86400 { return weekdayTimeFormatter.string(from: date) }
        return dateTimeFormatter.string(from: date)
    }

    static func time(_ date: Date) -> String { timeFormatter.string(from: date) }
    static func date(_ date: Date) -> String { dateFormatter.string(from: date) }
    static func dateShort(_ date: Date) -> String { dateShortFormatter.string(from: date) }

    /// `yyyy-MM-dd` in the local calendar; used as the "date filter" equivalent of `startsWith(date)`.
    static func dayKey(_ date: Date) -> String { dayKeyFormatter.string(from: date) }

    static func dayKeyDate(_ key: String) -> Date? { dayKeyFormatter.date(from: key) }

    static func relative(_ date: Date, now: Date = Date()) -> String {
        let f = RelativeDateTimeFormatter()
        f.locale = Locale(identifier: "zh_CN")
        f.unitsStyle = .short
        return f.localizedString(for: date, relativeTo: now)
    }

    static func isToday(_ date: Date) -> Bool { calendar.isDateInToday(date) }

    static func greeting(now: Date = Date()) -> String {
        let hour = calendar.component(.hour, from: now)
        if hour < 6 { return "夜深了" }
        if hour < 12 { return "早上好" }
        if hour < 14 { return "中午好" }
        if hour < 18 { return "下午好" }
        return "晚上好"
    }

    static func leverage(_ value: Double) -> String {
        if value.isInfinite { return "∞×" }
        if value.isNaN { return "0.0×" }
        // JS toFixed(1) rounds half away from zero (1.25 → "1.3"); printf would give "1.2".
        let rounded = (value * 10).rounded(.toNearestOrAwayFromZero) / 10
        return String(format: "%.1f×", rounded)
    }

    static func percent(_ value: Double) -> String { "\(Int((value * 100).rounded()))%" }

    static func cost(_ value: Double) -> String { String(format: "$%.2f", value) }

    /// `toLocaleString()` equivalent (thousands separators).
    static func number(_ value: Int) -> String { numberFormatter.string(from: NSNumber(value: value)) ?? "\(value)" }
}
