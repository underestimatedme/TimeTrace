import Foundation

/// 定时执行的时间窗，与 Valley 的 not_before 校验一致：至少 2 分钟后、最多 30 天内。
/// 返回 nil 表示可用；否则是一句能照着改的提示。
func scheduleWindowError(_ date: Date, now: Date = Date()) -> String? {
    if date < now.addingTimeInterval(120) { return "执行时间至少要在 2 分钟后，请重新选择。" }
    if date > now.addingTimeInterval(30 * 86400) { return "执行时间最多只能安排到 30 天内，请重新选择。" }
    return nil
}

/// Valley 拒绝执行时刻时（422）给用户看的话。
let scheduleRejectedText = "执行时间必须在 2 分钟后、30 天内，请重新选择后再派发。"
