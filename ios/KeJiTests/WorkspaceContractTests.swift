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

    func testRunnerToolDecodesPlanTierAndToleratesItsAbsence() throws {
        let with = Data(#"{"id":"claude-default","provider":"claude","version":"local","status":"available","plan_tier":"max","updated_at":"2026-09-25T00:00:00Z"}"#.utf8)
        XCTAssertEqual(try JSONCoding.decoder.decode(RunnerTool.self, from: with).planTier, "max")
        let without = Data(#"{"id":"codex-default","provider":"codex","version":"local","status":"available","updated_at":"2026-09-25T00:00:00Z"}"#.utf8)
        XCTAssertEqual(try JSONCoding.decoder.decode(RunnerTool.self, from: without).planTier, "")
    }

    func testRemoteJobDecodesNotBeforeAndOutputTail() throws {
        let json = Data(#"{"id":"j","task_id":"t","runner_id":"r","workspace_id":"w","tool_profile_id":"codex-default","status":"queued","revision":1,"not_before":"2026-09-27T14:00:00Z","output_tail":"3 passed\n","created_at":"2026-09-25T00:00:00Z","updated_at":"2026-09-25T00:00:00Z"}"#.utf8)
        let job = try JSONCoding.decoder.decode(RemoteJob.self, from: json)
        XCTAssertEqual(job.notBefore, Date(timeIntervalSince1970: 1790517600))
        XCTAssertEqual(job.outputTail, "3 passed\n")
    }

    func testRemoteJobRequestEncodesNotBeforeInRFC3339() throws {
        let request = RemoteJobRequest(taskId: "t", runnerId: "r", workspaceId: "w", toolProfileId: "codex-default",
                                       prompt: "p", idempotencyKey: "k", expectedTaskRevision: 1, planId: "plan",
                                       notBefore: Date(timeIntervalSince1970: 1790517600))
        let body = String(decoding: try JSONCoding.encoder.encode(request), as: UTF8.self)
        XCTAssertTrue(body.contains(#""not_before":"2026-09-27T14:00:00"#), body)
        let immediate = RemoteJobRequest(taskId: "t", runnerId: "r", workspaceId: "w", toolProfileId: "codex-default",
                                         prompt: "p", idempotencyKey: "k", expectedTaskRevision: 1, planId: "plan")
        XCTAssertFalse(String(decoding: try JSONCoding.encoder.encode(immediate), as: UTF8.self).contains("not_before"))
    }

    func testQuotaWindowIdentityIncludesLimitAndWindow() throws {
        let json = Data(#"""
        {"pools":[{"pool_id":"p","provider":"codex","plan_tier":"plus","availability":"available","windows":[
          {"pool_id":"p","scope":"primary","kind":"codex","limit_id":"codex","window_mins":300,"used_percent":10,"observed_at":"2026-09-25T00:00:00Z","expires_at":"2026-09-25T05:00:00Z","source":"runner","confidence":"exact"},
          {"pool_id":"p","scope":"primary","kind":"codex","limit_id":"codex-mini","window_mins":300,"used_percent":20,"observed_at":"2026-09-25T00:00:00Z","expires_at":"2026-09-25T05:00:00Z","source":"runner","confidence":"exact"}]}],
          "observed_at":"2026-09-25T00:00:00Z"}
        """#.utf8)
        let quota = try JSONCoding.decoder.decode(AccountQuota.self, from: json)
        XCTAssertEqual(quota.pools[0].planTier, "plus")
        XCTAssertEqual(Set(quota.pools[0].windows.map(\.id)).count, 2)
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
    /// 自动续跑可以在等待额度时修改（设计稿：关闭后只补额度、需手动继续）；已结束的 Plan 不可改。
    func testAutoResumeStaysEditableWhileWaitingButNotAfterTheEnd() {
        func plan(_ id: String, _ status: PlanState) -> PlanItem {
            PlanItem(id: id, taskId: "t", revision: 1, title: id, priority: 2, status: status, criteria: [],
                     dependsOn: [], estimatedHumanMinutes: 0, estimatedAiMinutes: 0, workWeight: 1, risk: 2,
                     executionPolicy: .balanced, createdAt: Date(), updatedAt: Date())
        }
        for open: PlanState in [.draft, .ready, .queued, .running, .waitingQuota, .waitingLocalAuth, .awaitingReview] {
            XCTAssertTrue(canEditAutoResume(plan("p", open)), "\(open) should allow changing auto-resume")
        }
        for closed: PlanState in [.accepted, .cancelled, .failed, .unknown] {
            XCTAssertFalse(canEditAutoResume(plan("p", closed)), "\(closed) is final")
        }
        XCTAssertFalse(canEditAutoResume(plan("draft-t", .ready)))
    }
    /// Valley 首发只给来源链接（link_only），事件为空，并注明公共信号不替代个人额度核验。
    func testResetSignalsDecodesValleyLinkOnlyShape() throws {
        let json = #"{"integration_status":"link_only","sources":[{"name":"BetterOPC","url":"https://betteropc.com"}],"signals":[],"cache_age_seconds":0,"note":"尚无确认可用的公共信号接口或抓取许可；仅提供来源链接。公共信号不替代个人额度核验。"}"#
        let response = try JSONCoding.decoder.decode(ResetSignalsResponse.self, from: Data(json.utf8))
        XCTAssertEqual(response.integrationStatus, "link_only")
        XCTAssertEqual(response.sources.first?.name, "BetterOPC")
        XCTAssertEqual(response.sources.first?.url.absoluteString, "https://betteropc.com")
        XCTAssertTrue(response.signals.isEmpty)
        XCTAssertNil(response.fetchedAt)
        XCTAssertEqual(Endpoint.resetSignals.path, "/reset-signals")
    }

    /// 生效时间缺失时保持未知，不从「今天」推算；只有 confirmed 才算已确认。
    func testResetSignalWithoutEffectiveTimeStaysUnknown() throws {
        let json = #"{"id":"s1","source_url":"https://betteropc.com/x","published_at":"2026-09-18T08:00:00Z","effective_at":null,"products":["codex"],"plans":["plus"],"confidence":"possible","fetched_at":"2026-09-18T09:00:00Z","expires_at":"2026-09-19T09:00:00Z","revision":1}"#
        let signal = try JSONCoding.decoder.decode(ResetSignal.self, from: Data(json.utf8))
        XCTAssertNil(signal.effectiveAt)
        XCTAssertEqual(signal.effectiveText, "生效时间未知")
        XCTAssertEqual(signal.confidenceLabel, "可能")
        XCTAssertFalse(signal.canRefreshQuota, "possible 不能触发额度核验")
        var confirmed = signal; confirmed.confidence = "confirmed"
        XCTAssertEqual(confirmed.confidenceLabel, "已确认")
        XCTAssertTrue(confirmed.canRefreshQuota)
    }
    /// 反馈走 Valley 的 POST /feedback：body / idempotency_key / include_diagnostics。
    func testFeedbackRequestMatchesValleyContract() throws {
        let draft = FeedbackDraft(idempotencyKey: "key-1", text: "  额度页看不到周窗口  ", attachDiagnostics: true)
        let endpoint = try Endpoint.feedback(draft)
        XCTAssertEqual(endpoint.path, "/feedback")
        XCTAssertEqual(endpoint.method, .post)
        let body = try JSONSerialization.jsonObject(with: JSONCoding.encoder.encode(FeedbackBody(draft: draft))) as? [String: Any]
        XCTAssertEqual(body?["body"] as? String, "额度页看不到周窗口", "提交前去掉首尾空白")
        XCTAssertEqual(body?["idempotency_key"] as? String, "key-1")
        XCTAssertEqual(body?["include_diagnostics"] as? Bool, true)
    }

    func testFeedbackReceiptDecodesValleyShape() throws {
        let json = #"{"ticket_id":"fb_123","body":"额度页看不到周窗口","status":"open","include_diagnostics":false,"created_at":"2026-09-19T08:00:00Z","updated_at":"2026-09-19T08:00:00Z"}"#
        let ticket = try JSONCoding.decoder.decode(FeedbackReceipt.self, from: Data(json.utf8))
        XCTAssertEqual(ticket.ticketId, "fb_123")
        XCTAssertEqual(ticket.status, "open")
        XCTAssertEqual(ticket.body, "额度页看不到周窗口")
    }

    /// 含凭据/邮箱/环境信息的反馈在客户端就被拒绝，不会构造请求。
    func testFeedbackEndpointRefusesUnsafeDraft() {
        XCTAssertThrowsError(try Endpoint.feedback(FeedbackDraft.new(text: "token=secret")))
    }

    /// 重试必须沿用同一个幂等键，服务端才会返回同一张单而不是重复建单；
    /// 内容改了才算新的一条反馈。
    func testFeedbackRetryReusesIdempotencyKeyUnlessTextChanges() {
        let pending = FeedbackDraft(idempotencyKey: "key-1", text: "同一条反馈", attachDiagnostics: false)
        XCTAssertEqual(FeedbackDraft.next(pending: pending, text: "同一条反馈", attachDiagnostics: false).idempotencyKey, "key-1")
        XCTAssertEqual(FeedbackDraft.next(pending: pending, text: "同一条反馈 ", attachDiagnostics: false).idempotencyKey, "key-1",
                       "只差首尾空白算同一条")
        XCTAssertNotEqual(FeedbackDraft.next(pending: pending, text: "另一条反馈", attachDiagnostics: false).idempotencyKey, "key-1")
        XCTAssertNotEqual(FeedbackDraft.next(pending: nil, text: "同一条反馈", attachDiagnostics: false).idempotencyKey, "")
    }
}
