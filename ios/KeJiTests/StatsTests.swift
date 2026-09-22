import XCTest
@testable import KeJi

final class StatsTests: XCTestCase {
    func testOpenHumanSessionsAccumulateAndClipAcrossMidnight() {
        let now = ISO8601.date(from: "2026-09-15T00:10:00Z")!
        let zone = TimeZone(identifier: "UTC")!
        let day = "2026-09-15"
        let midnight = reportDayInterval(day, timeZone: zone)!.start
        let previousDay = "2026-09-14"
        var open = session("open", type: .humanFocus, start: midnight.addingTimeInterval(-600), minutes: 1)
        open.endedAt = nil
        open.durationSeconds = 999999
        var overlap = open
        overlap.id = "overlap"; overlap.type = .humanReview
        XCTAssertEqual(Stats.humanSeconds([open, overlap], day: previousDay, timeZone: zone, asOf: now), 600)
        XCTAssertEqual(Stats.humanSeconds([open, overlap], day: day, timeZone: zone, asOf: now), 600)
        XCTAssertEqual(ReportPresentation(sessions: [open], day: day, timeZone: zone).human, .unknown)
    }

    func testReportMidnightClippingHumanUnionAndDistinctParallelAI() {
        let start = Calendar.current.date(from: DateComponents(year: 2026, month: 9, day: 14, hour: 23, minute: 50))!
        let human = session("human", type: .humanFocus, start: start, minutes: 20)
        let review = session("review", type: .humanReview, start: start.addingTimeInterval(300), minutes: 15)
        let a = session("attempt-a", type: .aiActive, start: start, minutes: 20)
        let b = session("attempt-b", type: .aiActive, start: start, minutes: 20)
        for day in ["2026-09-14", "2026-09-15"] {
            XCTAssertEqual(Stats.humanSeconds([human, review, human], day: day), 600)
            XCTAssertEqual(Stats.aiActiveSeconds([a, b, a], day: day), 1200)
        }
    }
    private func session(_ id: String, type: TimeSessionType, start: Date, minutes: Int, taskId: String = "t") -> TimeSession {
        TimeSession(id: id, taskId: taskId, type: type, executor: type == .aiActive ? "claude" : "human",
                    startedAt: start, endedAt: start.addingTimeInterval(Double(minutes * 60)),
                    durationSeconds: minutes * 60, source: .timer, confidence: .exact, note: nil, updatedAt: start)
    }

    func testFormatDuration() {
        XCTAssertEqual(Format.duration(3900), "1 小时 5 分钟")
        XCTAssertEqual(Format.duration(303), "5 分 3 秒")
        XCTAssertEqual(Format.duration(300), "5 分钟")
        XCTAssertEqual(Format.duration(42), "42 秒")
        XCTAssertEqual(Format.duration(0), "0 秒")
        XCTAssertEqual(Format.durationShort(3900), "1h 5m")
        XCTAssertEqual(Format.leverage(1.25), "1.3×")
        XCTAssertEqual(Format.percent(0.585), "59%")
        XCTAssertEqual(Format.cost(0.18), "$0.18")
        XCTAssertEqual(Format.number(12400), "12,400")
    }

    func testDeepWorkMergesAdjacentSessions() {
        let base = Calendar.current.date(bySettingHour: 9, minute: 0, second: 0, of: Date())!
        let sessions = [
            session("a", type: .humanFocus, start: base, minutes: 30),
            // 3-minute gap → merged into one 63-minute block
            session("b", type: .humanFocus, start: base.addingTimeInterval(33 * 60), minutes: 30),
            // 20-minute gap → separate block, exactly 25 min counts
            session("c", type: .humanFocus, start: base.addingTimeInterval(90 * 60), minutes: 25),
            // too short: ignored
            session("d", type: .humanFocus, start: base.addingTimeInterval(130 * 60), minutes: 10),
            session("e", type: .aiActive, start: base, minutes: 60),
        ]
        XCTAssertEqual(Stats.deepWorkSeconds(sessions), 63 * 60 + 25 * 60)
        XCTAssertEqual(Stats.deepWorkSeconds(sessions, day: "1999-01-01"), 0)
    }

    func testParallelStatsPeak() {
        let base = Calendar.current.date(bySettingHour: 10, minute: 0, second: 0, of: Date())!
        let sessions = [
            session("h1", type: .humanFocus, start: base, minutes: 60),
            session("a1", type: .aiActive, start: base.addingTimeInterval(10 * 60), minutes: 20),
            session("a2", type: .aiActive, start: base.addingTimeInterval(15 * 60), minutes: 10),
            session("h2", type: .humanReview, start: base.addingTimeInterval(90 * 60), minutes: 30),
            session("w", type: .waitingHuman, start: base, minutes: 500), // ignored
        ]
        let p = Stats.parallelStats(sessions)
        XCTAssertEqual(p.concurrencyPeak, 3)
        XCTAssertEqual(p.humanWorkloadSeconds, 90 * 60)
        XCTAssertEqual(p.aiWorkloadSeconds, 30 * 60)
        XCTAssertEqual(p.wallClockSeconds, 120 * 60)
        XCTAssertEqual(Stats.parallelStats([]), .empty)
    }

    func testLeverageAndPlanAccuracy() {
        XCTAssertEqual(Stats.timeLeverage(humanSeconds: 3600, aiSeconds: 5400), 1.5)
        XCTAssertEqual(Stats.timeLeverage(humanSeconds: 0, aiSeconds: 0), 0)
        XCTAssertTrue(Stats.timeLeverage(humanSeconds: 0, aiSeconds: 10).isInfinite)
        XCTAssertEqual(Stats.planAccuracy(plannedMinutes: 0, actualMinutes: 30), 1)
        XCTAssertEqual(Stats.planAccuracy(plannedMinutes: 100, actualMinutes: 142), 0.58, accuracy: 0.0001)
        XCTAssertEqual(Stats.planAccuracy(plannedMinutes: 10, actualMinutes: 100), 0)
    }

    func testTaskBreakdownAndWallClock() {
        let base = Date()
        let sessions = [
            session("1", type: .humanFocus, start: base, minutes: 30, taskId: "x"),
            session("2", type: .aiActive, start: base.addingTimeInterval(3600), minutes: 15, taskId: "x"),
            session("3", type: .waitingHuman, start: base.addingTimeInterval(5400), minutes: 5, taskId: "x"),
            session("4", type: .humanFocus, start: base, minutes: 99, taskId: "other"),
        ]
        let b = Stats.taskTimeBreakdown(sessions, taskId: "x")
        XCTAssertEqual(b.human, 1800)
        XCTAssertEqual(b.ai, 900)
        XCTAssertEqual(b.waitingHuman, 300)
        XCTAssertEqual(b.total, 5400 + 300)
    }

    func testComputedDailyStatsHasSevenDays() {
        let bundle = SampleData.createSampleData()
        let daily = Stats.dailyStats(sessions: bundle.state.timeSessions, tasks: bundle.state.tasks, days: 7)
        XCTAssertEqual(daily.count, 7)
        XCTAssertEqual(daily.last?.date, Format.dayKey(Date()))
        XCTAssertGreaterThan(daily.last?.humanSeconds ?? 0, 0)
    }
}
