import XCTest
@testable import KeJi

/// Proves the iOS models decode Valley's actual wire shapes (snake_case, RFC3339)
/// and that endpoint paths match the server routes.
final class WorkspaceContractTests: XCTestCase {
    func testAccountQuotaDecodesValleyShape() throws {
        let json = Data(#"""
        {"pools":[{"pool_id":"pool-codex","availability":"blocked","windows":[
          {"pool_id":"pool-codex","scope":"weekly","kind":"codex","used_percent":100,
           "observed_at":"2026-09-15T06:00:00Z","expires_at":"2026-09-15T07:00:00Z",
           "source":"runner","confidence":"exact"}]}],
         "observed_at":"2026-09-15T06:30:00Z"}
        """#.utf8)
        let quota = try JSONCoding.decoder.decode(AccountQuota.self, from: json)
        XCTAssertEqual(quota.pools.count, 1)
        XCTAssertEqual(quota.pools[0].availability, "blocked")
        XCTAssertEqual(quota.pools[0].windows.first?.usedPercent, 100)
        XCTAssertNil(quota.pools[0].windows.first?.resetAt)   // omitted -> nil, not zero-time
    }

    func testDailyReportDecodesAndEmptyState() throws {
        let json = Data(#"""
        {"local_date":"2026-09-15","revision":2,"status":"draft","human_seconds":1800,
         "ai_seconds":600,"waiting_seconds":120,"coverage":0.4,"evidence_ids":["e1"],
         "baseline_version":"v1","estimated_value_minor":0,"actual_spend_minor":0,
         "generated_at":"2026-09-15T07:00:00Z"}
        """#.utf8)
        let r = try JSONCoding.decoder.decode(DailyReport.self, from: json)
        XCTAssertEqual([r.humanSeconds, r.aiSeconds, r.waitingSeconds], [1800, 600, 120])
        XCTAssertNil(r.totalScore)
        XCTAssertFalse(r.hasTotal)      // low coverage -> no fabricated total
        XCTAssertEqual(r.evidenceIds, ["e1"])

        let empty = try JSONCoding.decoder.decode(DailyReport.self,
                                                  from: Data(#"{"local_date":"2026-01-01","status":"empty","evidence_ids":[]}"#.utf8))
        XCTAssertTrue(empty.isEmpty)
    }

    func testEndpointPaths() {
        XCTAssertEqual(Endpoint.accountQuota.path, "/quota")
        XCTAssertEqual(Endpoint.taskPlans(taskID: "t1").path, "/tasks/t1/plans")
        XCTAssertEqual(Endpoint.acceptPlan(id: "p1", expectedRevision: 2, evidenceIDs: [], criteria: []).path, "/plans/p1/accept")
        XCTAssertEqual(Endpoint.cancelPlan(id: "p1", expectedRevision: 2).path, "/plans/p1/cancel")
        XCTAssertEqual(Endpoint.report(date: "2026-09-15").path, "/reports?date=2026-09-15")
        XCTAssertEqual(Endpoint.generateReport(date: "2026-09-15", zone: "UTC").method, .post)
    }
}
