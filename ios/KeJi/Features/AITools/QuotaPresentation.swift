import Foundation

/// How a quota reading is shown. A stale reading is "待核验" (re-verify), a
/// missing/invalid reading is "未知" — never silently formatted as 100%.
func quotaLabel(remaining: Double?, fresh: Bool) -> String {
    guard fresh else { return "待核验" }
    guard let remaining, remaining.isFinite, (0...100).contains(remaining) else { return "未知" }
    return "\(Int(remaining.rounded()))%"
}

/// Tri-state availability shown to the user, in words (never colour alone).
func availabilityLabel(_ availability: String) -> String {
    switch availability {
    case "available": return "可用"
    case "blocked": return "已用尽"
    default: return "待核验"
    }
}

extension QuotaWindow {
    /// A window is fresh when now is within [observed_at, expires_at).
    func isFresh(now: Date = Date()) -> Bool { now >= observedAt && now < expiresAt }

    /// Remaining percentage for display, or nil when the reading is unknown.
    var remainingPercent: Double? {
        guard let used = usedPercent else { return nil }
        return max(0, 100 - used)
    }

    var displayLabel: String { quotaLabel(remaining: remainingPercent, fresh: isFresh()) }

    var scopeLabel: String {
        switch scope {
        case "short", "five_hour", "primary": return "短时"
        case "weekly", "week": return "本周"
        case "monthly", "month": return "本月"
        default: return scope
        }
    }
}
