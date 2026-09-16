import XCTest
@testable import KeJi

final class ReportsScopeTests: XCTestCase {
    func testReportUnknownIsNotZeroAnd79PercentCannotShowTotal() throws {
        let r = try JSONCoding.decoder.decode(DailyReport.self, from: Data(#"{"local_date":"2026-09-14","revision":2,"status":"draft","coverage":0.79,"total_score":95,"human_seconds":0}"#.utf8))
        XCTAssertEqual(r.humanSeconds, 0)
        XCTAssertNil(r.aiSeconds)
        XCTAssertNil(r.waitingSeconds)
        XCTAssertFalse(r.hasTotal)
        XCTAssertNil(r.estimatedValueMinor)
        XCTAssertNil(r.actualSpendMinor)
    }

    func testServerProjectionScopesFactsAndDedupesWithoutMergingParallelAttempts() {
        let start = ISO8601DateFormatter().date(from: "2026-09-14T20:00:00Z")!
        let end = start.addingTimeInterval(600)
        let h = ReportPhaseFact(id: "h", taskId: "A", track: .human, state: "known", start: start, end: end)
        let review = ReportPhaseFact(id: "review", taskId: "A", track: .human, state: "known", start: start.addingTimeInterval(300), end: end)
        let a = ReportPhaseFact(id: "a", taskId: "A", track: .ai, state: "known", start: start, end: end)
        let b = ReportPhaseFact(id: "b", taskId: "A", track: .ai, state: "known", start: start, end: end)
        let other = ReportPhaseFact(id: "other", taskId: "B", track: .ai, state: "known", start: start, end: end)
        let zero = ReportPhaseFact(id: "zero", taskId: "A", track: .waiting, state: "known", start: start, end: start)
        let p = ReportPresentation(facts: [h,review,a,a,b,other,zero], taskIds: ["A"])
        XCTAssertEqual(p.human, .seconds(600))
        XCTAssertEqual(p.ai, .seconds(1200))
        XCTAssertEqual(p.waiting, .seconds(0))
        XCTAssertEqual(p.evidenceCoverage, 1)
        let unknown = ReportPhaseFact(id: "unknown", taskId: "A", track: .ai, state: "unknown", start: start, end: end)
        XCTAssertEqual(ReportPresentation(facts: [a,unknown]).ai, .unknown)
        XCTAssertEqual(ReportPresentation(facts: []).ai, .empty)
        XCTAssertEqual(ReportMeasurement.unknown.text, "未知")
        XCTAssertEqual(ReportMeasurement.empty.text, "无记录")
        XCTAssertEqual(ReportMeasurement.seconds(0).text, "0 秒")
    }

    func testLocalProjectionUsesIANAClippingIncludingDSTAndOpenUnknown() {
        for (day, hours) in [("2026-03-08", 23), ("2026-11-01", 25)] {
            let zone = TimeZone(identifier: "America/New_York")!
            let bounds = reportDayInterval(day, timeZone: zone)!
            var s = session("dst", task: "A")
            s.startedAt = bounds.start; s.endedAt = bounds.end; s.durationSeconds = 999999
            XCTAssertEqual(ReportPresentation(sessions: [s], day: day, timeZone: zone).human, .seconds(hours * 3600))
            s.endedAt = nil
            XCTAssertEqual(ReportPresentation(sessions: [s], day: day, timeZone: zone).human, .unknown)
        }
        let zone = TimeZone(identifier: "Asia/Dubai")!
        var s = session("midnight", task: "A")
        s.startedAt = ISO8601DateFormatter().date(from: "2026-09-14T19:50:00Z")!
        s.endedAt = s.startedAt.addingTimeInterval(1200)
        for day in ["2026-09-14", "2026-09-15"] {
            XCTAssertEqual(ReportPresentation(sessions: [s,s], day: day, timeZone: zone).human, .seconds(600))
        }
    }
    private func task(_ id: String, project: String) -> TaskItem {
        TaskItem(id: id, projectId: project, goalId: nil, title: id, description: "", executorType: .ai,
                 aiProvider: nil, collaborationMode: nil, status: .planned, priority: .medium,
                 estimatedMinutes: 0, dueDate: nil, scheduledStart: nil, scheduledEnd: nil,
                 createdAt: Date(), completedAt: nil, resultSummary: nil, updatedAt: Date())
    }
    private func session(_ id: String, task: String) -> TimeSession {
        TimeSession(id: id, taskId: task, type: .humanFocus, executor: "human", startedAt: Date(),
                    endedAt: nil, durationSeconds: 60, source: .timer, confidence: .exact, note: nil, updatedAt: Date())
    }

    func testProjectScopeStaysWithinProject() {
        let tasks = [task("t1", project: "A"), task("t2", project: "B")]
        let sessions = [session("s1", task: "t1"), session("s2", task: "t2"), session("s3", task: "t1")]

        let all = sessionsInScope(.all, tasks: tasks, sessions: sessions)
        XCTAssertEqual(all.count, 3)

        let projectA = sessionsInScope(.project("A"), tasks: tasks, sessions: sessions)
        XCTAssertEqual(Set(projectA.map { $0.id }), ["s1", "s3"])   // no s2 (project B)
    }
}
