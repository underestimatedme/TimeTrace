import XCTest
@testable import KeJi

/// Proves the iOS models decode Valley's actual wire shapes (snake_case, RFC3339)
/// and that endpoint paths match the server routes.
final class WorkspaceContractTests: XCTestCase {
    func testRemoteJobRetainsPlanIdentityForReviewEvidence() throws {
        let json = Data(#"{"id":"job-7","task_id":"task-2","plan_id":"plan-3","runner_id":"runner-1","workspace_id":"ws-1","tool_profile_id":"codex-1","status":"awaiting_review","revision":4,"created_at":"2026-09-15T06:00:00Z","updated_at":"2026-09-15T07:00:00Z"}"#.utf8)
        let job = try JSONCoding.decoder.decode(RemoteJob.self, from: json)
        XCTAssertEqual(job.planId, "plan-3")
        XCTAssertEqual(job.status, .awaitingReview)
    }
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
    /// 分派策略的四个选项与 Valley normalizeExecutionPolicy 接受的 mode 一一对应。
    func testExecutionModesMatchValleyContract() {
        XCTAssertEqual(PlanExecutionMode.allCases.map(\.rawValue), ["balanced", "speed", "saver", "manual"])
        XCTAssertEqual(PlanExecutionMode.allCases.map(\.label), ["均衡", "速度优先", "节省额度", "手动"])
        XCTAssertEqual(PlanExecutionPolicy(mode: "saver", preferredProfileId: nil, allowAutoResume: true,
                                           maxAdditionalSpendMinor: 0).executionMode, .saver)
    }

    /// 运行中锁定：只有尚未执行的真实 Plan 才能改分派策略。
    func testExecutionPolicyIsLockedOnceExecutionStarts() {
        func plan(_ id: String, _ status: PlanState) -> PlanItem {
            PlanItem(id: id, taskId: "t", revision: 1, title: id, priority: 2, status: status, criteria: [],
                     dependsOn: [], estimatedHumanMinutes: 0, estimatedAiMinutes: 0, workWeight: 1, risk: 2,
                     executionPolicy: .balanced, createdAt: Date(), updatedAt: Date())
        }
        XCTAssertTrue(canEditExecutionPolicy(plan("p", .ready)))
        XCTAssertTrue(canEditExecutionPolicy(plan("p", .draft)))
        for locked: PlanState in [.queued, .running, .waitingQuota, .awaitingReview, .accepted, .cancelled, .failed] {
            XCTAssertFalse(canEditExecutionPolicy(plan("p", locked)), "\(locked) must lock the policy")
        }
        XCTAssertFalse(canEditExecutionPolicy(plan("draft-t", .ready)), "local drafts are not on the server yet")
    }

    func testUpdatePolicyPatchesPlanWithRevisionAndZeroSpend() throws {
        let policy = PlanExecutionPolicy(mode: "speed", preferredProfileId: nil, allowAutoResume: false, maxAdditionalSpendMinor: 0)
        let endpoint = Endpoint.updatePlanPolicy(id: "p1", expectedRevision: 3, policy: policy)
        XCTAssertEqual(endpoint.path, "/plans/p1")
        XCTAssertEqual(endpoint.method, .patch)
        let body = try JSONSerialization.jsonObject(with: JSONCoding.encoder.encode(
            UpdatePlanPolicyBody(expectedRevision: 3, executionPolicy: policy))) as? [String: Any]
        XCTAssertEqual(body?["expected_revision"] as? Int, 3)
        let sent = body?["execution_policy"] as? [String: Any]
        XCTAssertEqual(sent?["mode"] as? String, "speed")
        XCTAssertEqual(sent?["max_additional_spend_minor"] as? Int, 0)
    }
}
