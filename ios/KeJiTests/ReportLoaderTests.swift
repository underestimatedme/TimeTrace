import XCTest
@testable import KeJi

@MainActor final class ReportLoaderTests: XCTestCase {
    private func report(_ day: String, zone: String = "UTC") throws -> DailyReport {
        try JSONCoding.decoder.decode(DailyReport.self, from: Data("""
        {"local_date":"\(day)","revision":7,"status":"draft","coverage":0.9,"total_score":95,
         "breakdown":{"zone":"\(zone)","evidence_coverage":1,"facts":[
          {"id":"h","task_id":"task","track":"human","state":"known","start":"\(day)T00:00:00Z","end":"\(day)T00:10:00Z"}]}}
        """.utf8))
    }

    func testDayChangeThenGETFailureUsesCurrentLocalProjectionAndNoOldRevision() async throws {
        let loader = ReportLoader()
        let first = ReportContext(date: "2026-09-14", zone: "UTC")
        let second = ReportContext(date: "2026-09-15", zone: "UTC")
        await loader.load(context: first) { try report(first.date) }
        XCTAssertEqual(loader.presentation(for: first, sessions: []).human, .seconds(600))
        // Before the second task even starts, old state is already ineligible.
        XCTAssertNil(loader.currentReport(for: second))
        await loader.load(context: second) { throw URLError(.notConnectedToInternet) }
        let start = ISO8601.date(from: "2026-09-15T00:00:00Z")!
        let local = TimeSession(id: "today", taskId: "task", type: .humanFocus, executor: "human", startedAt: start,
                                endedAt: start.addingTimeInterval(120), durationSeconds: 999, source: .timer,
                                confidence: .exact, note: nil, updatedAt: start)
        XCTAssertEqual(loader.presentation(for: second, sessions: [local]).human, .seconds(120))
        XCTAssertNil(loader.currentReport(for: second))
        XCTAssertNotNil(loader.error)
        XCTAssertFalse(loader.loading)
    }

    func testSlowPreviousDayCannotBlockOrOverwriteNewRequest() async throws {
        let loader = ReportLoader()
        let first = ReportContext(date: "2026-09-14", zone: "UTC")
        let second = ReportContext(date: "2026-09-15", zone: "UTC")
        var suspended: CheckedContinuation<DailyReport, Never>?
        let old = Task { await loader.load(context: first) { await withCheckedContinuation { suspended = $0 } } }
        while suspended == nil { await Task.yield() }
        await loader.load(context: second) { try report(second.date) }
        XCTAssertEqual(loader.currentReport(for: second)?.localDate, second.date)
        suspended?.resume(returning: try report(first.date))
        await old.value
        XCTAssertEqual(loader.currentReport(for: second)?.localDate, second.date)
        XCTAssertNil(loader.currentReport(for: first))
        XCTAssertFalse(loader.loading)
    }

    func testTimeZoneChangeRejectsSameDateSnapshot() async throws {
        let loader = ReportLoader()
        let context = ReportContext(date: "2026-09-14", zone: "Asia/Dubai")
        await loader.load(context: context) { try report(context.date) }
        XCTAssertNil(loader.currentReport(for: context))
        XCTAssertEqual(loader.presentation(for: context, sessions: []).human, .empty)
        XCTAssertTrue(loader.error?.contains("报告日期或时区不匹配") == true)
    }
}
