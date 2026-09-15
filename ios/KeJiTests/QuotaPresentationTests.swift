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
}
