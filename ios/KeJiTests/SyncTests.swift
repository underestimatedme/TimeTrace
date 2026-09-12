import XCTest
@testable import KeJi

private final class StubHTTPProtocol: URLProtocol {
    static var handler: ((URLRequest) throws -> (Int, Data))?
    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    override func startLoading() {
        do {
            let (status, data) = try Self.handler!(request)
            let response = HTTPURLResponse(url: request.url!, statusCode: status, httpVersion: nil,
                                           headerFields: ["Content-Type": "application/json"])!
            client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
            client?.urlProtocol(self, didLoad: data)
            client?.urlProtocolDidFinishLoading(self)
        } catch { client?.urlProtocol(self, didFailWithError: error) }
    }
    override func stopLoading() {}
}

@MainActor
final class HTTPClientTests: XCTestCase {
    private var client: APIClient!
    private var session: URLSession!

    override func setUp() {
        super.setUp()
        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [StubHTTPProtocol.self]
        session = URLSession(configuration: config)
        client = APIClient(baseURL: URL(string: "https://keji-tests.invalid/api/v1")!,
                           keychain: KeychainStore(account: "qa-" + UUID().uuidString), session: session)
    }

    override func tearDown() {
        client.clearTokens()
        session.invalidateAndCancel()
        StubHTTPProtocol.handler = nil
        super.tearDown()
    }

    func testGuestThenAuthenticatedSyncAndBootstrap() async throws {
        let state = SampleData.createEmptyData().state
        let encoded = try JSONCoding.encoder.encode(Bootstrap(user: UserInfo(id: "qa", isGuest: true), state: state, serverTime: nil))
        let response = try JSONSerialization.data(withJSONObject: ["code": 0, "data": JSONSerialization.jsonObject(with: encoded)])
        StubHTTPProtocol.handler = { request in
            if request.url!.path.hasSuffix("/auth/guest") {
                XCTAssertEqual(request.httpMethod, "POST")
                XCTAssertNil(request.value(forHTTPHeaderField: "Authorization"))
                return (201, Data(#"{"code":0,"data":{"access_token":"qa-access","refresh_token":"qa-refresh","expires_in":900}}"#.utf8))
            }
            XCTAssertEqual(request.value(forHTTPHeaderField: "Authorization"), "Bearer qa-access")
            XCTAssertEqual(request.httpMethod, request.url!.path.hasSuffix("/sync") ? "POST" : "GET")
            return (200, response)
        }
        client.storeTokens(try await client.send(.guest, as: SessionTokens.self))
        let request = SyncRequest(clientTime: Date(), upserts: SyncUpserts(), deletes: SyncDeletes(), settings: state.settings)
        let synced = try await client.send(.sync(request), as: Bootstrap.self)
        XCTAssertEqual(synced.user?.id, "qa")
        let pulled = try await client.send(.bootstrap, as: Bootstrap.self)
        XCTAssertEqual(pulled.state, synced.state)
    }

    func testUnauthorizedRefreshesAndRetriesWithNewToken() async throws {
        client.storeTokens(SessionTokens(accessToken: "old", refreshToken: "refresh", expiresIn: 900))
        StubHTTPProtocol.handler = { request in
            if request.url!.path.hasSuffix("/auth/refresh") {
                return (200, Data(#"{"code":0,"data":{"access_token":"new","refresh_token":"rotated","expires_in":900}}"#.utf8))
            }
            if request.value(forHTTPHeaderField: "Authorization") == "Bearer old" {
                return (401, Data(#"{"code":40100,"message":"expired"}"#.utf8))
            }
            XCTAssertEqual(request.value(forHTTPHeaderField: "Authorization"), "Bearer new")
            return (200, Data(#"{"code":0,"data":{"state":{}}}"#.utf8))
        }
        _ = try await client.send(.bootstrap, as: Bootstrap.self)
        XCTAssertEqual(client.tokens?.accessToken, "new")
        XCTAssertEqual(client.tokens?.refreshToken, "rotated")
    }

    func testTransportFailureIsReportedAsOfflineError() async {
        StubHTTPProtocol.handler = { _ in throw URLError(.notConnectedToInternet) }
        do {
            _ = try await client.send(.contentVersion, as: ContentVersion.self)
            XCTFail("Expected offline error")
        } catch {
            XCTAssertEqual((error as? APIError)?.code, -3)
        }
    }

    func testContinuousEditsDoNotStarveScheduledSync() async throws {
        let store = AppStore()
        store.completeOnboarding(useSample: false)
        client.storeTokens(SessionTokens(accessToken: "qa", refreshToken: "qa", expiresIn: 900))
        let engine = SyncEngine(store: store, client: client, enabled: true)
        let pushed = expectation(description: "Sync occurs while changes continue")
        pushed.assertForOverFulfill = false
        let state = try JSONSerialization.jsonObject(with: JSONCoding.encoder.encode(store.snapshot))
        let response = try JSONSerialization.data(withJSONObject: ["code": 0, "data": ["state": state]])
        StubHTTPProtocol.handler = { request in
            XCTAssertTrue(request.url!.path.hasSuffix("/sync"))
            pushed.fulfill()
            return (200, response)
        }
        for index in 0..<8 {
            store.updateSettings { $0.name = "edit-\(index)" }
            try await _Concurrency.Task.sleep(nanoseconds: 300_000_000)
        }
        await fulfillment(of: [pushed], timeout: 1)
        XCTAssertNotNil(engine.lastSyncAt)
    }
}

@MainActor
final class SyncTests: XCTestCase {
    private func json(_ value: Encodable) throws -> [String: Any] {
        let data = try JSONCoding.encoder.encode(AnyEncodable(value))
        return try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
    }

    func testSyncRequestEncodesSnakeCaseAndTriStateActiveFocus() throws {
        let now = Date(timeIntervalSince1970: 1_757_000_000)
        var request = SyncRequest(clientTime: now, upserts: SyncUpserts(), deletes: SyncDeletes(tasks: ["t1"]))

        var obj = try json(request)
        XCTAssertNotNil(obj["client_time"])
        XCTAssertFalse(obj.keys.contains("active_focus"), "absent when unchanged")
        XCTAssertNil(obj["settings"])
        let deletes = try XCTUnwrap(obj["deletes"] as? [String: Any])
        XCTAssertEqual(deletes["tasks"] as? [String], ["t1"])
        XCTAssertEqual(Set(deletes.keys), ["projects", "goals", "tasks", "time_sessions", "ai_executions", "experiments"])
        let upserts = try XCTUnwrap(obj["upserts"] as? [String: Any])
        XCTAssertEqual(Set(upserts.keys), ["projects", "goals", "tasks", "time_sessions", "ai_executions", "experiments"])

        request.activeFocus = .clear
        obj = try json(request)
        XCTAssertTrue(obj.keys.contains("active_focus"))
        XCTAssertTrue(obj["active_focus"] is NSNull, "explicit null clears")

        request.activeFocus = .set(ActiveFocus(taskId: "t2", startedAt: now, accumulatedSeconds: 5))
        obj = try json(request)
        let focus = try XCTUnwrap(obj["active_focus"] as? [String: Any])
        XCTAssertEqual(focus["task_id"] as? String, "t2")
        XCTAssertEqual(focus["accumulated_seconds"] as? Int, 5)
        XCTAssertEqual(focus["started_at"] as? String, "2025-09-04T15:33:20.000Z")
    }

    func testTaskEncodesSnakeCaseKeys() throws {
        let task = SampleData.createSampleData().state.tasks[2] // t3, ai task
        let obj = try json(task)
        XCTAssertEqual(obj["executor_type"] as? String, "ai")
        XCTAssertEqual(obj["ai_provider"] as? String, "claude")
        XCTAssertEqual(obj["collaboration_mode"] as? String, "ai_independent")
        XCTAssertEqual(obj["status"] as? String, "ai_running")
        XCTAssertEqual(obj["due_date"] as? String, Format.dayKey(Date()))
        XCTAssertNotNil(obj["estimated_minutes"])
        XCTAssertNotNil(obj["scheduled_start"])
        XCTAssertNotNil(obj["updated_at"])
    }

    func testBootstrapDecodesFixture() throws {
        let fixture = """
        {"code":0,"message":"ok","request_id":"abc","data":{
          "user":{"id":"u1","nickname":"游客","is_guest":true,"account_label":null},
          "server_time":"2026-09-04T10:00:00.123456789+08:00",
          "state":{
            "projects":[{"id":"p1","name":"刻迹","description":"","icon":"⏳","color":"#d4845a","status":"active",
                         "created_at":"2026-08-01T00:00:00Z","updated_at":"2026-09-01T00:00:00.5Z"}],
            "goals":null,
            "tasks":[{"id":"t1","project_id":"p1","goal_id":null,"title":"任务","description":"d","executor_type":"collaboration",
                      "ai_provider":"codex","collaboration_mode":"alternating","status":"waiting_human","priority":"urgent",
                      "estimated_minutes":45,"due_date":"2026-09-04","scheduled_start":"2026-09-04T09:00:00Z",
                      "created_at":"2026-09-03T00:00:00Z","updated_at":"2026-09-04T00:00:00Z"}],
            "time_sessions":[{"id":"s1","task_id":"t1","type":"ai_active","executor":"codex","started_at":"2026-09-04T09:00:00Z",
                              "ended_at":null,"duration_seconds":120,"source":"simulated","confidence":"exact","updated_at":"2026-09-04T09:02:00Z"}],
            "ai_executions":[{"id":"e1","task_id":"t1","provider":"codex","model":"gpt-4o","status":"running",
                              "started_at":"2026-09-04T09:00:00Z","active_seconds":120,"elapsed_seconds":120,"waiting_human_seconds":0,
                              "token_input":10,"token_output":5,"estimated_cost":0.01,"tool_call_count":1,"files_changed":0,
                              "logs":null,"current_step":"生成代码","updated_at":"2026-09-04T09:02:00Z"}],
            "experiments":[],
            "settings":{"name":"我","weekly_time_goal_hours":30,"work_start_hour":10,"work_end_hour":19,
                        "default_focus_minutes":50,"streak_days":3,"theme":"cursor","updated_at":"2026-09-04T00:00:00Z"},
            "ai_tools":[{"provider":"claude","name":"Claude Code","connected":true,"last_sync":"2026-09-04T09:00:00Z"}],
            "active_focus":{"task_id":"t1","started_at":"2026-09-04T09:30:00Z","accumulated_seconds":60}
          }}}
        """
        let envelope = try JSONCoding.decoder.decode(APIEnvelope<Bootstrap>.self, from: Data(fixture.utf8))
        XCTAssertEqual(envelope.code, 0)
        XCTAssertEqual(envelope.requestId, "abc")
        let boot = try XCTUnwrap(envelope.data)
        XCTAssertEqual(boot.user?.id, "u1")
        XCTAssertEqual(boot.user?.isGuest, true)
        XCTAssertNotNil(boot.serverTime)
        XCTAssertEqual(boot.state.projects.count, 1)
        XCTAssertEqual(boot.state.goals.count, 0)
        XCTAssertEqual(boot.state.tasks.first?.status, .waitingHuman)
        XCTAssertEqual(boot.state.tasks.first?.dueDate, "2026-09-04")
        XCTAssertEqual(boot.state.tasks.first?.collaborationMode, .alternating)
        XCTAssertEqual(boot.state.timeSessions.first?.executor, "codex")
        XCTAssertEqual(boot.state.aiExecutions.first?.logs.count, 0)
        XCTAssertEqual(boot.state.settings.theme, .cursor)
        XCTAssertEqual(boot.state.settings.defaultFocusMinutes, 50)
        XCTAssertEqual(boot.state.aiTools.first?.connected, true)
        XCTAssertEqual(boot.state.activeFocus?.accumulatedSeconds, 60)
    }

    func testErrorEnvelopeDecodes() throws {
        let data = Data(#"{"code":40100,"message":"token expired"}"#.utf8)
        let env = try JSONCoding.decoder.decode(APIEnvelope<Bootstrap>.self, from: data)
        XCTAssertEqual(env.code, 40100)
        XCTAssertNil(env.data)
    }

    func testSessionTokensExpiry() throws {
        let data = Data(#"{"access_token":"a","refresh_token":"r","expires_in":900}"#.utf8)
        let tokens = try JSONCoding.decoder.decode(SessionTokens.self, from: data)
        XCTAssertEqual(tokens.expiresIn, 900)
        XCTAssertFalse(tokens.isExpiringSoon())
        XCTAssertTrue(tokens.isExpiringSoon(now: Date().addingTimeInterval(850)))
    }

    func testApplySnapshotPreservesDirtyEntities() {
        let store = AppStore()
        store.completeOnboarding(useSample: true)
        store.clearDirty(store.dirty, deleted: store.deleted, settings: true, activeFocus: true, aiTools: true)
        XCTAssertFalse(store.hasPendingSync)

        // local edit → dirty
        store.updateTask("t7") { $0.title = "本地修改" }
        store.deleteTask("t20")

        var remote = store.snapshot
        remote.tasks = remote.tasks.map { t in
            var t = t
            if t.id == "t7" { t.title = "服务端旧值" }
            return t
        }
        remote.tasks.append(SampleData.createSampleData().state.tasks.first { $0.id == "t20" }!) // server still has t20
        remote.tasks.removeAll { $0.id == "t1" } // server deleted t1
        remote.settings.name = "服务端名字"

        store.applySnapshot(remote)
        XCTAssertEqual(store.task("t7")?.title, "本地修改", "dirty entity kept")
        XCTAssertNil(store.task("t20"), "locally deleted entity not resurrected")
        XCTAssertNil(store.task("t1"), "server deletion applied")
        XCTAssertEqual(store.settings.name, "服务端名字")

        // build request from dirty state
        let engine = SyncEngine(store: store, client: APIClient(baseURL: URL(string: "http://localhost:1")!, keychain: KeychainStore(account: "tests")), enabled: false)
        let request = engine.buildRequest(dirty: store.dirty, deleted: store.deleted, settings: false, activeFocus: false, aiTools: false)
        XCTAssertEqual(request.upserts.tasks.map(\.id), ["t7"])
        XCTAssertEqual(request.deletes.tasks, ["t20"])
        XCTAssertEqual(request.activeFocus, .unchanged)
        XCTAssertTrue(request.hasChanges)
    }

    func testResolveBaseURLPrecedence() {
        let fromArg = APIClient.resolveBaseURL(arguments: ["app", "--api-base-url", "http://a.test/v1"], environment: ["KEJI_API_BASE_URL": "http://b.test"])
        XCTAssertEqual(fromArg.absoluteString, "http://a.test/v1")
        let fromEnv = APIClient.resolveBaseURL(arguments: [], environment: ["KEJI_API_BASE_URL": "http://b.test"])
        XCTAssertEqual(fromEnv.absoluteString, "http://b.test")
        let fallback = APIClient.resolveBaseURL(arguments: [], environment: [:], bundle: Bundle(for: SyncTests.self))
        XCTAssertEqual(fallback.absoluteString, APIClient.defaultBaseURL)
    }

    func testAcknowledgementPreservesEditsMadeWhileRequestIsInFlight() {
        let store = AppStore()
        store.completeOnboarding(useSample: true)
        let sent = store.snapshot
        let checkpoint = store.syncCheckpoint()
        store.updateTask("t7") { $0.title = "请求期间的新编辑" }
        store.updateSettings { $0.theme = .light }
        store.pauseFocus()
        store.markAIToolsDirty()
        store.deleteTask("t20")
        store.acknowledge(checkpoint, settings: true, activeFocus: true, aiTools: true)
        store.applySnapshot(sent)
        XCTAssertEqual(store.task("t7")?.title, "请求期间的新编辑")
        XCTAssertEqual(store.settings.theme, .light)
        XCTAssertNil(store.activeFocus)
        XCTAssertNil(store.task("t20"))
        XCTAssertTrue(store.dirty[.tasks]?.contains("t7") == true)
        XCTAssertTrue(store.aiToolsDirty)
        XCTAssertFalse(store.dirty[.tasks]?.contains("t1") == true)
    }

    func testPersistenceRoundTripKeepsPendingChangesAndFocus() throws {
        let store = AppStore()
        store.completeOnboarding(useSample: true)
        store.updateTask("t7") { $0.title = "离线编辑" }
        store.deleteTask("t20")
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString + ".json")
        let persistence = StateStore(url: url)
        defer { persistence.clear() }
        persistence.save(store.persisted)
        let restored = AppStore()
        restored.load(try XCTUnwrap(persistence.load()))
        XCTAssertEqual(restored.task("t7")?.title, "离线编辑")
        let focus = try XCTUnwrap(restored.activeFocus)
        let originalFocus = try XCTUnwrap(store.activeFocus)
        XCTAssertEqual(focus.taskId, originalFocus.taskId)
        XCTAssertEqual(focus.accumulatedSeconds, originalFocus.accumulatedSeconds)
        // RFC3339 storage deliberately normalizes sub-millisecond precision.
        XCTAssertEqual(focus.startedAt.timeIntervalSince1970, originalFocus.startedAt.timeIntervalSince1970, accuracy: 0.001)
        XCTAssertEqual(restored.dirty, store.dirty)
        XCTAssertEqual(restored.deleted, store.deleted)
        XCTAssertTrue(restored.hasOnboarded)
    }
}
