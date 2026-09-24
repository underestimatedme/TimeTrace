import XCTest
@testable import KeJi

private final class PlanHTTPProtocol: URLProtocol {
    static var handler: ((URLRequest) throws -> (Int, Data))!
    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    override func startLoading() {
        do {
            let (status, data) = try Self.handler(request)
            client?.urlProtocol(self, didReceive: HTTPURLResponse(url: request.url!, statusCode: status,
                                httpVersion: nil, headerFields: nil)!, cacheStoragePolicy: .notAllowed)
            client?.urlProtocol(self, didLoad: data)
            client?.urlProtocolDidFinishLoading(self)
        } catch { client?.urlProtocol(self, didFailWithError: error) }
    }
    override func stopLoading() {}
}

@MainActor
final class PlanWorkflowTests: XCTestCase {
    private var api: APIClient!
    private var session: URLSession!
    private var store: AppStore!
    private var plan: PlanItem!

    override func setUp() {
        super.setUp()
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [PlanHTTPProtocol.self]
        session = URLSession(configuration: configuration)
        api = APIClient(baseURL: URL(string: "https://plans.invalid/api/v1")!,
                        keychain: KeychainStore(account: "plan-test-" + UUID().uuidString), session: session)
        api.storeTokens(SessionTokens(accessToken: "test", refreshToken: "", expiresIn: 900))
        store = AppStore()
        store.workspaceClient = WorkspaceClient(client: api)
        store.tasks = SampleData.createWorkspaceFixture().state.tasks
        plan = SampleData.createWorkspaceFixture().state.plans[0]
        plan.status = .awaitingReview
        plan.revision = 7
        plan.criteria = ["Tests pass", "Result reviewed"]
        store.plans = [plan]
    }

    override func tearDown() {
        api.clearTokens()
        session.invalidateAndCancel()
        PlanHTTPProtocol.handler = nil
        super.tearDown()
    }

    private func response<T: Encodable>(_ value: T, code: Int = 0) throws -> Data {
        try JSONSerialization.data(withJSONObject: ["code": code, "message": "revision conflict",
            "data": JSONSerialization.jsonObject(with: JSONCoding.encoder.encode(value))])
    }

    private var results: [CriterionResultBody] {
        [.init(index: 0, accepted: true), .init(index: 1, accepted: true)]
    }

    func testAcceptanceSubmitsCompleteReviewAndOnlyAppliesServerReceipt() async throws {
        var accepted = plan!
        accepted.status = .accepted
        accepted.revision = 8
        let reply = try response(accepted)
        let id = plan.id
        var calls = 0
        PlanHTTPProtocol.handler = { request in
            calls += 1
            XCTAssertEqual(request.url?.path, "/api/v1/plans/\(id)/accept")
            XCTAssertEqual(request.httpMethod, "POST")
            let body = try Self.body(request)
            XCTAssertEqual(body["expected_revision"] as? Int, 7)
            XCTAssertEqual(body["evidence_ids"] as? [String], ["job-1"])
            let criteria = body["criteria"] as? [[String: Any]]
            XCTAssertEqual(criteria?.count, 2)
            XCTAssertEqual(criteria?.map { $0["index"] as? Int }, [0, 1])
            XCTAssertEqual(criteria?.map { $0["accepted"] as? Bool }, [true, true])
            return (200, reply)
        }
        let ok = await store.acceptPlan(plan.id, expectedRevision: 7, evidenceIDs: ["job-1"], criteria: results)
        XCTAssertTrue(ok)
        XCTAssertEqual(calls, 1)
        XCTAssertEqual(store.plan(plan.id)?.status, .accepted)
        XCTAssertEqual(store.plan(plan.id)?.revision, 8)
    }

    func testConflictAdoptsCurrentPlanButNeverRetriesAcceptance() async throws {
        var current = plan!
        current.revision = 9
        current.status = .cancelled
        let reply = try response(current, code: 40901)
        var calls = 0
        PlanHTTPProtocol.handler = { _ in calls += 1; return (409, reply) }
        let ok = await store.acceptPlan(plan.id, expectedRevision: 7, evidenceIDs: ["job-1"], criteria: results)
        XCTAssertFalse(ok)
        XCTAssertEqual(calls, 1)
        XCTAssertEqual(store.plan(plan.id)?.revision, 9)
        XCTAssertEqual(store.plan(plan.id)?.status, .cancelled)
        XCTAssertNotNil(store.planErrors[plan.id])
    }

    func testOfflineAndRateLimitDoNotAcceptOrUnlockDependents() async throws {
        for status in [-1, 429] {
            PlanHTTPProtocol.handler = { _ in
                if status == -1 { throw URLError(.notConnectedToInternet) }
                return (429, Data(#"{"code":42900,"message":"quota exhausted"}"#.utf8))
            }
            let ok = await store.acceptPlan(plan.id, expectedRevision: 7, evidenceIDs: ["job-1"], criteria: results)
            XCTAssertFalse(ok)
            XCTAssertEqual(store.plan(plan.id)?.status, .awaitingReview)
            XCTAssertEqual(store.plan(plan.id)?.revision, 7)
            XCTAssertNotNil(store.planErrors[plan.id])
            XCTAssertFalse(store.planBusy.contains(plan.id))
        }
    }

    func testIncompleteReviewNeverContactsServer() async {
        PlanHTTPProtocol.handler = { _ in XCTFail("invalid review reached server"); throw URLError(.badURL) }
        let ok = await store.acceptPlan(plan.id, expectedRevision: 7, evidenceIDs: [], criteria: [])
        XCTAssertFalse(ok)
        XCTAssertEqual(store.plan(plan.id)?.status, .awaitingReview)
    }

    func testRefreshCreatesAnExplicitPlanForSyncedDraftThenReplacesDraft() async throws {
        let id = store.addTask(store.tasks[0])
        store.clearDirty([.tasks: [id]], deleted: [:], settings: false, activeFocus: false, aiTools: false)
        var created = plan!
        created.id = "new-plan"
        created.taskId = id
        created.status = .ready
        let reply = try response(created)
        let empty = try response([PlanItem]())
        var methods: [String] = []
        PlanHTTPProtocol.handler = { request in
            methods.append(request.httpMethod!)
            XCTAssertEqual(request.url?.path, "/api/v1/tasks/\(id)/plans")
            if request.httpMethod == "POST" {
                let body = try Self.body(request)
                XCTAssertEqual(body["status"] as? String, "ready")
                XCTAssertNotNil(body["title"])
                return (201, reply)
            }
            return (200, empty)
        }
        await store.refreshPlans(taskID: id)
        XCTAssertEqual(methods, ["GET", "POST"])
        XCTAssertEqual(store.plans(forTask: id).map(\.id), ["new-plan"])
    }

    func testRefreshReplacesStalePlanStateAndDoesNotInventPlanForEmptyTask() async throws {
        var current = plan!
        current.status = .running
        current.revision = 11
        let reply = try response([current])
        PlanHTTPProtocol.handler = { _ in (200, reply) }
        await store.refreshPlans(taskID: plan.taskId)
        XCTAssertEqual(store.plan(plan.id)?.status, .running)
        XCTAssertEqual(store.plan(plan.id)?.revision, 11)
        let empty = try response([PlanItem]())
        PlanHTTPProtocol.handler = { request in XCTAssertEqual(request.httpMethod, "GET"); return (200, empty) }
        await store.refreshPlans(taskID: plan.taskId)
        XCTAssertTrue(store.plans(forTask: plan.taskId).isEmpty)
    }

    func testDispatchSendsPlanAndTaskRevisionAndPersistsEvidenceJob() async throws {
        store.plans[0].status = .ready
        store.plans[0].title = "Review quota"
        store.plans[0].criteria = ["Attach report"]
        store.tasks[0].description = "Capture remaining quota"
        let date = Date(timeIntervalSince1970: 1_789_500_000)
        store.tasks[0].updatedAt = date
        let job = RemoteJob(id: "job-1", taskId: plan.taskId, runnerId: "runner", workspaceId: "workspace",
                            toolProfileId: "tool", status: .queued, revision: 1, createdAt: date, updatedAt: date)
        let reply = try response(job)
        var current = plan!
        current.status = .queued
        let plans = try response([current])
        PlanHTTPProtocol.handler = { request in
            if request.httpMethod == "POST" {
                XCTAssertEqual(request.url?.path, "/api/v1/remote-jobs")
                let body = try Self.body(request)
                XCTAssertEqual(body["plan_id"] as? String, current.id)
                XCTAssertEqual(body["expected_task_revision"] as? Int64, 1_789_500_000_000)
                XCTAssertEqual(body["runner_id"] as? String, "runner")
                XCTAssertEqual(body["prompt"] as? String, "Review quota\n\nCapture remaining quota\n\n验收项：\n- Attach report")
                XCTAssertFalse((body["idempotency_key"] as? String ?? "").isEmpty)
                return (201, reply)
            }
            return (200, plans)
        }
        let ok = await store.dispatchPlan(plan.id, runnerID: "runner", workspaceID: "workspace", toolID: "tool")
        XCTAssertTrue(ok)
        XCTAssertEqual(store.planJobs[plan.id]?.id, "job-1")
        XCTAssertEqual(store.plan(plan.id)?.status, .queued)
        let reloaded = AppStore()
        reloaded.load(try JSONCoding.decoder.decode(PersistedState.self, from: JSONCoding.encoder.encode(store.persisted)))
        XCTAssertEqual(reloaded.planJobs[plan.id]?.id, "job-1")
    }

    /// 派发可以带执行时刻：请求体里有 RFC 3339 的 not_before，幂等键也随之不同。
    func testScheduledDispatchSendsNotBeforeAndChangesIdempotencyKey() async throws {
        store.plans[0].status = .ready
        var job = RemoteJob(id: "job-2", taskId: plan.taskId, runnerId: "r", workspaceId: "w", toolProfileId: "t",
                            status: .queued, revision: 1, resultSummary: nil, prompt: nil, createdAt: Date(), updatedAt: Date(), planId: plan.id)
        job.notBefore = Date(timeIntervalSince1970: 1_790_517_600)
        let reply = try response(job)
        var current = plan!
        current.status = .queued
        let plans = try response([current])
        var keys: [String?] = []
        PlanHTTPProtocol.handler = { request in
            if request.httpMethod == "POST" {
                let body = try Self.body(request)
                XCTAssertTrue((body["not_before"] as? String ?? "").hasPrefix("2026-09-27T14:00:00"), "\(body)")
                keys.append(body["idempotency_key"] as? String)
                return (201, reply)
            }
            return (200, plans)
        }
        let ok = await store.dispatchPlan(plan.id, runnerID: "r", workspaceID: "w", toolID: "t",
                                          notBefore: Date(timeIntervalSince1970: 1_790_517_600))
        XCTAssertTrue(ok)
        XCTAssertEqual(store.planJobs[plan.id]?.notBefore, Date(timeIntervalSince1970: 1_790_517_600))

        // Same plan, no time: a different request, so a different key.
        store.plans[0].status = .ready
        store.planJobs = [:]
        PlanHTTPProtocol.handler = { request in
            if request.httpMethod == "POST" {
                let body = try Self.body(request)
                XCTAssertNil(body["not_before"])
                keys.append(body["idempotency_key"] as? String)
                return (201, reply)
            }
            return (200, plans)
        }
        _ = await store.dispatchPlan(plan.id, runnerID: "r", workspaceID: "w", toolID: "t")
        XCTAssertEqual(keys.count, 2)
        XCTAssertNotEqual(keys[0], keys[1])
    }

    func testDispatchFailureHasNoJobAndNoSuccessfulStatus() async throws {
        store.plans[0].status = .ready
        PlanHTTPProtocol.handler = { _ in (429, Data(#"{"code":42900,"message":"quota exhausted"}"#.utf8)) }
        let ok = await store.dispatchPlan(plan.id, runnerID: "r", workspaceID: "w", toolID: "t")
        XCTAssertFalse(ok)
        XCTAssertNil(store.planJobs[plan.id])
        XCTAssertEqual(store.plan(plan.id)?.status, .ready)
        XCTAssertNotNil(store.planErrors[plan.id])
    }

    func testCancellationAndExplicitRetryUseCurrentRevision() async throws {
        for action in ["cancel", "retry"] {
            store.plans[0].status = action == "retry" ? .failed : .running
            var receipt = store.plans[0]
            receipt.status = action == "retry" ? .ready : .cancelled
            receipt.revision = 8
            let reply = try response(receipt)
            PlanHTTPProtocol.handler = { request in
                XCTAssertTrue(request.url!.path.hasSuffix("/\(action)"))
                XCTAssertEqual(try Self.body(request)["expected_revision"] as? Int, 7)
                return (200, reply)
            }
            let ok: Bool
            if action == "retry" { ok = await store.retryPlan(plan.id, expectedRevision: 7) }
            else { ok = await store.cancelPlan(plan.id, expectedRevision: 7) }
            XCTAssertTrue(ok)
            XCTAssertEqual(store.plan(plan.id)?.status, receipt.status)
            store.plans[0].revision = 7
        }
    }

    func testForegroundSyncRefreshesAuthoritativePlans() async throws {
        store.hasOnboarded = true
        var snapshot = SampleData.createWorkspaceFixture().state
        snapshot.plans = []
        let bootstrap = try response(Bootstrap(user: nil, state: snapshot, serverTime: nil))
        var current = plan!
        current.status = .running
        current.revision = 12
        let plansReply = try response([current])
        PlanHTTPProtocol.handler = { request in
            (200, request.url!.path.hasSuffix("/bootstrap") ? bootstrap : plansReply)
        }
        let sync = SyncEngine(store: store, client: api, enabled: true)
        await sync.syncOnForeground()
        XCTAssertEqual(store.plan(plan.id)?.status, .running)
        XCTAssertEqual(store.plan(plan.id)?.revision, 12)
    }

    func testLoadingLegacyCompletedTaskDoesNotFabricateAcceptedPlan() {
        var snapshot = SampleData.createWorkspaceFixture().state
        snapshot.plans = []
        snapshot.tasks[0].completedAt = Date()
        let loaded = AppStore()
        loaded.load(PersistedState(state: snapshot))
        XCTAssertTrue(loaded.plans.isEmpty)
    }

    func testLegacyReviewCannotCompleteTaskWithAuthoritativePlan() {
        store.tasks[0].status = .waitingHuman
        let sessions = store.timeSessions
        store.completeAIReview(plan.taskId)
        XCTAssertEqual(store.task(plan.taskId)?.status, .waitingHuman)
        XCTAssertNil(store.task(plan.taskId)?.completedAt)
        XCTAssertEqual(store.timeSessions, sessions)
    }

    func testHumanAndExternalTasksCannotDispatchAIJobs() async throws {
        store.plans[0].status = .ready
        let reply = try response(store.plans)
        var requests = 0
        PlanHTTPProtocol.handler = { _ in requests += 1; return (200, reply) }
        for executor in [ExecutorType.human, .external] {
            store.tasks[0].executorType = executor
            let sent = await store.dispatchPlan(plan.id, runnerID: "r", workspaceID: "w", toolID: "t")
            XCTAssertFalse(sent)
            XCTAssertNotNil(store.planErrors[plan.id])
        }
        XCTAssertEqual(requests, 0, "unsupported executor must be rejected before loading or dispatching a runner")
    }

    func testOldAcceptedCacheCannotUnlockDependenciesOffline() throws {
        var state = store.snapshot
        state.plans[0].status = .accepted
        var dependent = state.plans[0]
        dependent.id = "dependent"
        dependent.dependsOn = [plan.id]
        dependent.status = .ready
        state.plans.append(dependent)
        let oldCache = try JSONCoding.encoder.encode(PersistedState(state: state))
        let loaded = AppStore()
        loaded.load(try JSONCoding.decoder.decode(PersistedState.self, from: oldCache))
        XCTAssertNotEqual(loaded.plan(plan.id)?.status, .accepted)
        XCTAssertFalse(canDispatchPlan(dependent, allPlans: loaded.plans))
        XCTAssertNotNil(loaded.planErrors[plan.id])
    }

    func testServerConfirmedAcceptedCacheSurvivesOfflineReload() throws {
        var accepted = plan!
        accepted.status = .accepted
        store.applyPlan(accepted)
        let loaded = AppStore()
        loaded.load(try JSONCoding.decoder.decode(PersistedState.self, from: JSONCoding.encoder.encode(store.persisted)))
        XCTAssertEqual(loaded.plan(plan.id)?.status, .accepted)
    }

    func testUnverifiedHighRevisionCannotOverrideFreshServerPlan() async throws {
        var state = store.snapshot
        state.plans[0].status = .accepted
        state.plans[0].revision = 99
        store.load(PersistedState(state: state))
        var current = plan!
        current.status = .ready
        current.revision = 3
        let reply = try response([current])
        PlanHTTPProtocol.handler = { _ in (200, reply) }
        await store.refreshPlans(taskID: plan.taskId)
        XCTAssertEqual(store.plan(plan.id)?.status, .ready)
        XCTAssertEqual(store.plan(plan.id)?.revision, 3)
        XCTAssertNil(store.planErrors[plan.id])
    }

    func testPlanRefreshFailureBlocksPreparationWithActualReason() async throws {
        store.hasOnboarded = true
        let bootstrap = try response(Bootstrap(user: nil, state: store.snapshot, serverTime: nil))
        PlanHTTPProtocol.handler = { request in
            if request.url!.path.hasSuffix("/plans") {
                return (429, Data(#"{"code":42900,"message":"quota exhausted"}"#.utf8))
            }
            return (200, bootstrap)
        }
        let sync = SyncEngine(store: store, client: api, enabled: true)
        store.preparePlanDispatch = { try await sync.prepareForPlanDispatch() }
        let prepared = await store.prepareTaskPlan(plan.taskId)
        XCTAssertNil(prepared)
        XCTAssertTrue(store.planErrors[plan.taskId]?.contains("quota exhausted") == true)
        XCTAssertNotEqual(sync.status, .idle)
    }

    func testConcurrentPlanRefreshSharesRequestAndCompletion() async throws {
        let started = expectation(description: "one shared Plan request")
        let gate = DispatchSemaphore(value: 0)
        let reply = try response(store.plans)
        var requests = 0
        PlanHTTPProtocol.handler = { _ in
            requests += 1
            started.fulfill()
            _ = gate.wait(timeout: .now() + 5)
            return (200, reply)
        }
        let first = Task { await store.refreshPlans(taskID: plan.taskId) }
        await fulfillment(of: [started], timeout: 3)
        var returned = false
        let second = Task { let result = await store.refreshPlans(taskID: plan.taskId); returned = true; return result }
        for _ in 0..<10 { await Task.yield() }
        XCTAssertFalse(returned)
        gate.signal()
        let results = await [first.value, second.value]
        XCTAssertEqual(results, [true, true])
        XCTAssertEqual(requests, 1)
    }

    func testConcurrentForegroundWaitsForPlanRefreshAndDoesNotReportIdleEarly() async throws {
        store.hasOnboarded = true
        let started = expectation(description: "Plan refresh pending")
        let gate = DispatchSemaphore(value: 0)
        let bootstrap = try response(Bootstrap(user: nil, state: store.snapshot, serverTime: nil))
        let plansReply = try response(store.plans)
        PlanHTTPProtocol.handler = { request in
            if request.url!.path.hasSuffix("/plans") {
                started.fulfill()
                _ = gate.wait(timeout: .now() + 5)
                return (200, plansReply)
            }
            return (200, bootstrap)
        }
        let sync = SyncEngine(store: store, client: api, enabled: true)
        let first = Task { await sync.syncOnForeground() }
        await fulfillment(of: [started], timeout: 3)
        XCTAssertEqual(sync.status, .syncing)
        var secondFinished = false
        let second = Task { await sync.syncOnForeground(); secondFinished = true }
        for _ in 0..<10 { await Task.yield() }
        XCTAssertFalse(secondFinished, "a coalesced caller must wait for the same completed snapshot and Plans")
        gate.signal()
        await first.value
        await second.value
        XCTAssertEqual(sync.status, .idle)
    }

    func testSaveAndStartIntentSurvivesInFlightSyncAndDispatchesOnceWithFreshRevision() async throws {
        store.hasOnboarded = true
        var task = store.tasks[0]
        task.executorType = .ai
        let taskID = store.addTask(task)
        let started = expectation(description: "foreground sync in flight")
        let gate = DispatchSemaphore(value: 0)
        var snapshot = store.snapshot
        snapshot.tasks[snapshot.tasks.count - 1].updatedAt = Date(timeIntervalSince1970: 1_789_600_123)
        let bootstrap = try response(Bootstrap(user: nil, state: snapshot, serverTime: nil))
        var createdPlan = plan!
        createdPlan.id = "created-plan"
        createdPlan.taskId = taskID
        createdPlan.status = .ready
        let createdReply = try response(createdPlan)
        let plansReply = try response([createdPlan])
        let empty = try response([PlanItem]())
        let job = RemoteJob(id: "one-job", taskId: taskID, runnerId: "r", workspaceId: "w", toolProfileId: "t",
                            status: .queued, revision: 1, createdAt: Date(), updatedAt: Date())
        let jobReply = try response(job)
        var created = false
        var dispatches = 0
        PlanHTTPProtocol.handler = { request in
            let path = request.url!.path
            if path.hasSuffix("/sync") {
                started.fulfill()
                _ = gate.wait(timeout: .now() + 5)
                return (200, bootstrap)
            }
            if path.hasSuffix("/bootstrap") { return (200, bootstrap) }
            if path.hasSuffix("/remote-jobs") {
                dispatches += 1
                let body = try Self.body(request)
                XCTAssertEqual(body["plan_id"] as? String, "created-plan")
                XCTAssertEqual(body["expected_task_revision"] as? Int64, 1_789_600_123_000)
                return (201, jobReply)
            }
            if path.contains(taskID), request.httpMethod == "POST" { created = true; return (201, createdReply) }
            return (200, path.contains(taskID) && created ? plansReply : empty)
        }
        let sync = SyncEngine(store: store, client: api, enabled: true)
        store.preparePlanDispatch = {
            try await sync.prepareForPlanDispatch()
        }
        let foreground = Task { await sync.syncOnForeground() }
        await fulfillment(of: [started], timeout: 3)
        var intentFinished = false
        let intent = Task { () -> Bool in
            defer { intentFinished = true }
            guard let plan = await store.prepareTaskPlan(taskID) else { return false }
            return await store.dispatchPlan(plan.id, runnerID: "r", workspaceID: "w", toolID: "t")
        }
        for _ in 0..<10 { await Task.yield() }
        XCTAssertFalse(intentFinished)
        gate.signal()
        await foreground.value
        let sent = await intent.value
        XCTAssertTrue(sent)
        XCTAssertEqual(dispatches, 1)
        XCTAssertEqual(store.planJobs["created-plan"]?.id, "one-job")
    }

    func testAcceptanceDebouncesWhileReceiptIsPending() async throws {
        let started = expectation(description: "request reached server")
        let gate = DispatchSemaphore(value: 0)
        var accepted = plan!
        accepted.status = .accepted
        let reply = try response(accepted)
        var calls = 0
        PlanHTTPProtocol.handler = { _ in
            calls += 1
            started.fulfill()
            _ = gate.wait(timeout: .now() + 5)
            return (200, reply)
        }
        let first = Task { await store.acceptPlan(plan.id, expectedRevision: 7, evidenceIDs: ["job-1"], criteria: results) }
        await fulfillment(of: [started], timeout: 3)
        XCTAssertTrue(store.planBusy.contains(plan.id))
        XCTAssertEqual(store.plan(plan.id)?.status, .awaitingReview)
        let second = await store.acceptPlan(plan.id, expectedRevision: 7, evidenceIDs: ["job-1"], criteria: results)
        XCTAssertFalse(second)
        gate.signal()
        let firstResult = await first.value
        XCTAssertTrue(firstResult)
        XCTAssertEqual(calls, 1)
    }

    nonisolated private static func body(_ request: URLRequest) throws -> [String: Any] {
        var data = request.httpBody ?? Data()
        if let stream = request.httpBodyStream {
            stream.open(); defer { stream.close() }
            var buffer = [UInt8](repeating: 0, count: 4096)
            while stream.hasBytesAvailable {
                let n = stream.read(&buffer, maxLength: buffer.count)
                if n <= 0 { break }
                data.append(contentsOf: buffer.prefix(n))
            }
        }
        return try JSONSerialization.jsonObject(with: data) as! [String: Any]
    }
}
