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
        case "weekly", "week", "seven_day", "secondary": return "本周"
        case "monthly", "month": return "本月"
        default: return scope
        }
    }

    /// 「周三 14:00 重置」；没有重置时刻就没有这行。
    func resetText(now: Date = Date()) -> String? {
        resetAt.map { Format.resetMoment($0, now: now) + " 重置" }
    }
}

private let shortScopes: Set<String> = ["short", "five_hour", "primary"]
private let weeklyScopes: Set<String> = ["weekly", "week", "seven_day", "secondary"]

/// 一个额度池在 AI 页上的呈现：短时窗口做主数值，周窗口做副行。
/// 读数过期只说「待核验」，没有读数只说「未知」——都不画进度条。
struct ToolQuotaCard: Identifiable, Equatable {
    let id: String
    let name: String
    let capability: String
    /// 「套餐 Max」/「套餐未知」，来自工具清单，不是猜的。
    let tier: String
    let headline: String
    let meterPercent: Double?
    let detail: String
    let availability: String
    let footnote: String

    init(pool: AccountQuotaPool, now: Date = Date()) {
        id = pool.poolId
        name = ToolQuotaCard.toolName(provider: pool.provider, poolId: pool.poolId)
        capability = ToolQuotaCard.capability(provider: pool.provider)
        availability = availabilityLabel(pool.availability)
        tier = pool.planTier.isEmpty ? "套餐未知" : "套餐 " + pool.planTier.prefix(1).uppercased() + pool.planTier.dropFirst()

        let short = pool.windows.first { shortScopes.contains($0.scope) }
        let weekly = pool.windows.first { weeklyScopes.contains($0.scope) }
        let headlineWindow = short ?? pool.windows.first
        headline = headlineWindow?.displayLabel ?? "未知"
        meterPercent = headlineWindow.flatMap { $0.isFresh(now: now) ? $0.remainingPercent : nil }

        if let weekly, weekly.id != headlineWindow?.id {
            let reset = weekly.resetText(now: now).map { " · " + $0 } ?? ""
            if !weekly.isFresh(now: now) { detail = "周额度待核验" + reset }
            else if let remaining = weekly.remainingPercent { detail = "周额度剩余 \(Int(remaining.rounded()))%" + reset }
            else { detail = "周额度未知" + reset }
        } else {
            detail = "账号额度：\(availabilityLabel(pool.availability))"
        }

        if let observed = headlineWindow?.observedAt {
            footnote = "\(headlineWindow?.scopeLabel ?? "")窗口 · \(Format.time(observed)) 更新"
        } else {
            footnote = "尚无采样"
        }
    }

    /// 只在认识的 provider 上给工具名，不认识就显示池 id，不瞎猜。
    private static func toolName(provider: String, poolId: String) -> String {
        switch provider {
        case "claude": return "Claude Code"
        case "codex": return "Codex"
        case "gemini": return "Gemini CLI"
        case "cursor": return "Cursor"
        default: return poolId
        }
    }

    /// 能力分层来自 Runner 的实际适配情况，不因为「已连接」就声称可派发。
    private static func capability(provider: String) -> String {
        switch provider {
        case "claude", "codex": return "可派发 · 可恢复"
        case "cursor": return "记录 · 提醒"
        default: return "记录 · 待适配"
        }
    }
}
