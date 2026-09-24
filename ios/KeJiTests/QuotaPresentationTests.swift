import XCTest
@testable import KeJi

final class QuotaPresentationTests: XCTestCase {
    func testQuotaUnknownIsNotFull() {
        XCTAssertEqual(quotaLabel(remaining: nil, fresh: true), "未知")
        XCTAssertEqual(quotaLabel(remaining: 100, fresh: false), "待核验")
        XCTAssertEqual(quotaLabel(remaining: 62, fresh: true), "62%")
    }

    func testEdgeCases() {
        XCTAssertEqual(quotaLabel(remaining: 0, fresh: true), "0%")
        XCTAssertEqual(quotaLabel(remaining: -1, fresh: true), "未知")     // out of range, not clamped
        XCTAssertEqual(quotaLabel(remaining: 101, fresh: true), "未知")
        XCTAssertEqual(quotaLabel(remaining: .nan, fresh: true), "未知")
        XCTAssertEqual(availabilityLabel("blocked"), "已用尽")
        XCTAssertEqual(availabilityLabel("available"), "可用")
        XCTAssertEqual(availabilityLabel("unknown"), "待核验")
    }

    func testWindowDisplayHandlesStaleFreshUnknown() {
        let now = Date()
        func win(_ used: Double?, observed: TimeInterval, expires: TimeInterval) -> QuotaWindow {
            QuotaWindow(poolId: "p", scope: "weekly", kind: "codex", usedPercent: used, resetAt: nil,
                        observedAt: now.addingTimeInterval(observed), expiresAt: now.addingTimeInterval(expires),
                        source: "runner", confidence: "exact")
        }
        XCTAssertEqual(win(100, observed: -7200, expires: -3600).displayLabel, "待核验") // stale -> re-verify
        XCTAssertEqual(win(40, observed: -60, expires: 3600).displayLabel, "60%")        // fresh -> remaining
        XCTAssertEqual(win(nil, observed: -60, expires: 3600).displayLabel, "未知")       // unknown reading
    }
    private func win(_ pool: String, _ scope: String, used: Double?, fresh: Bool, now: Date) -> QuotaWindow {
        QuotaWindow(poolId: pool, scope: scope, kind: "codex", usedPercent: used, resetAt: now.addingTimeInterval(1800),
                    observedAt: fresh ? now.addingTimeInterval(-300) : now.addingTimeInterval(-7200),
                    expiresAt: fresh ? now.addingTimeInterval(3600) : now.addingTimeInterval(-3600),
                    source: "runner", confidence: "exact")
    }

    /// Claude 的 7 天窗与 Codex 的周窗（secondary）都归入「本周」。
    func testScopeLabelsCoverClaudeAndCodexWindows() {
        let now = Date()
        XCTAssertEqual(win("p", "seven_day", used: 10, fresh: true, now: now).scopeLabel, "本周")
        XCTAssertEqual(win("p", "secondary", used: 10, fresh: true, now: now).scopeLabel, "本周")
        XCTAssertEqual(win("p", "five_hour", used: 10, fresh: true, now: now).scopeLabel, "短时")
    }

    /// 重置时刻用绝对时间：今天、一周内用星期、更远用日期。
    func testResetMomentIsAbsolute() {
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = TimeZone.current
        let now = cal.date(from: DateComponents(year: 2026, month: 9, day: 25, hour: 9, minute: 0))!
        XCTAssertEqual(Format.resetMoment(now.addingTimeInterval(5 * 3600), now: now), "今天 14:00")
        XCTAssertEqual(Format.resetMoment(now.addingTimeInterval(2 * 86400 + 5 * 3600), now: now), "周日 14:00")
        XCTAssertEqual(Format.resetMoment(now.addingTimeInterval(10 * 86400), now: now), "10月5日 09:00")
    }

    /// 卡片显示套餐等级，周额度副行带绝对重置时刻。
    func testToolCardShowsTierAndWeeklyResetMoment() {
        let now = Date()
        var weekly = win("pool-claude", "seven_day", used: 45, fresh: true, now: now)
        weekly.resetAt = now.addingTimeInterval(3600)
        let pool = AccountQuotaPool(poolId: "pool-claude", provider: "claude", availability: "available",
                                    windows: [win("pool-claude", "five_hour", used: 20, fresh: true, now: now), weekly], planTier: "max")
        let card = ToolQuotaCard(pool: pool, now: now)
        XCTAssertEqual(card.tier, "套餐 Max")
        XCTAssertTrue(card.detail.hasPrefix("周额度剩余 55% · "), card.detail)
        XCTAssertTrue(card.detail.hasSuffix(" 重置"), card.detail)
        let unknown = ToolQuotaCard(pool: AccountQuotaPool(poolId: "p", provider: "codex", availability: "unknown", windows: []), now: now)
        XCTAssertEqual(unknown.tier, "套餐未知")
    }

    /// 工具卡片按真实额度池渲染：短时窗口做主数值，周窗口做副行。
    func testToolCardUsesShortWindowAsHeadlineAndWeeklyAsDetail() {
        let now = Date()
        let pool = AccountQuotaPool(poolId: "pool-codex", provider: "codex", availability: "available",
                                    windows: [win("pool-codex", "short", used: 20, fresh: true, now: now),
                                              win("pool-codex", "weekly", used: 45, fresh: true, now: now)])
        let card = ToolQuotaCard(pool: pool, now: now)
        XCTAssertEqual(card.name, "Codex")
        XCTAssertEqual(card.capability, "可派发 · 可恢复")
        XCTAssertEqual(card.headline, "80%")
        XCTAssertEqual(card.meterPercent, 80)
        XCTAssertTrue(card.detail.hasPrefix("周额度剩余 55%"), card.detail)   // followed by the reset moment
    }

    /// 读数过期只显示「待核验」，进度条不画，绝不显示成满额。
    func testStaleReadingShowsPendingVerificationAndNoMeter() {
        let now = Date()
        let pool = AccountQuotaPool(poolId: "pool-claude", provider: "claude", availability: "unknown",
                                    windows: [win("pool-claude", "weekly", used: 100, fresh: false, now: now)])
        let card = ToolQuotaCard(pool: pool, now: now)
        XCTAssertEqual(card.name, "Claude Code")
        XCTAssertEqual(card.headline, "待核验")
        XCTAssertNil(card.meterPercent)
        // 主数值就是这个周窗口（脚注已写明「本周窗口」），副行改说账号可用性，不重复同一条读数。
        XCTAssertEqual(card.detail, "账号额度：待核验")
    }

    /// 没有 provider 就不编工具名；未适配的工具不声称可派发。
    func testUnknownProviderKeepsPoolIdAndClaimsNoDispatch() {
        let now = Date()
        let pool = AccountQuotaPool(poolId: "pool-x", provider: "", availability: "unknown", windows: [])
        let card = ToolQuotaCard(pool: pool, now: now)
        XCTAssertEqual(card.name, "pool-x")
        XCTAssertEqual(card.capability, "记录 · 待适配")
        XCTAssertEqual(card.headline, "未知")
        XCTAssertNil(card.meterPercent)
    }
}
