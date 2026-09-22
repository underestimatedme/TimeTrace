import XCTest
@testable import KeJi

private final class BoundaryHTTP: URLProtocol {
    static var handle: ((BoundaryHTTP) -> Void)!
    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    override func startLoading() { Self.handle(self) }
    override func stopLoading() {}
    func reply(_ status: Int = 200, _ json: String) {
        client?.urlProtocol(self, didReceive: HTTPURLResponse(url: request.url!, statusCode: status,
            httpVersion: nil, headerFields: ["Content-Type": "application/json"])!, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: Data(json.utf8))
        client?.urlProtocolDidFinishLoading(self)
    }
}

@MainActor final class SessionBoundaryTests: XCTestCase {
    private var api: APIClient!
    private var session: URLSession!
    private var store: AppStore!
    private var sync: SyncEngine!
    private var directory: URL!
    private var drafts: FeedbackDraftStore!
    private let alice = SessionTokens(accessToken: "test-alice", refreshToken: "test-alice-refresh", expiresIn: 900)
    private let bob = SessionTokens(accessToken: "test-bob", refreshToken: "test-bob-refresh", expiresIn: 900)
    private let aliceBootstrap = #"{"code":0,"data":{"user":{"id":"alice","is_guest":false},"state":{}}}"#
    private let bobBootstrap = #"{"code":0,"data":{"user":{"id":"bob","is_guest":false},"state":{}}}"#
    private let receipt = #"{"code":0,"data":{"ticket_id":"ticket-test","body":"Alice feedback","status":"received"}}"#
    private let refreshedAlice = #"{"code":0,"data":{"access_token":"test-alice-fresh","refresh_token":"test-alice-rotated","expires_in":900}}"#

    override func setUpWithError() throws {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [BoundaryHTTP.self]
        session = URLSession(configuration: configuration)
        api = APIClient(baseURL: URL(string: "https://session-tests.invalid/api/v1")!,
                        keychain: KeychainStore(account: "boundary-" + UUID().uuidString), session: session)
        store = AppStore()
        sync = SyncEngine(store: store, client: api, enabled: true)
        store.onDirty = nil
        directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        drafts = FeedbackDraftStore(directory: directory)
    }

    override func tearDownWithError() throws {
        api.clearTokens()
        session.invalidateAndCancel()
        BoundaryHTTP.handle = nil
        if FileManager.default.fileExists(atPath: directory.path) { try FileManager.default.removeItem(at: directory) }
    }

    private func establishAlice() async {
        api.storeTokens(alice)
        let bootstrap = aliceBootstrap
        BoundaryHTTP.handle = { $0.reply(200, bootstrap) }
        await sync.pull()
        XCTAssertEqual(sync.user?.id, "alice")
    }

    private func assertDraftRetained(_ model: FeedbackModel) throws {
        XCTAssertNil(model.receipt)
        XCTAssertNotNil(model.error)
        XCTAssertEqual(try drafts.load(userID: "alice", draftID: "composer")?.text, "Alice feedback")
    }

    func testFeedbackDelayed401NeverRetriesUnderSwitchedAccount() async throws {
        try await feedbackAfterSwitch(status: 401)
    }

    func testFeedbackDelayedSuccessCannotClearPreviousAccountDraft() async throws {
        try await feedbackAfterSwitch(status: 200)
    }

    func testFeedbackSameAccountNewSessionInvalidatesOldRequest() async throws {
        try await feedbackAfterSwitch(status: 401, sameAccount: true)
    }

    private func feedbackAfterSwitch(status: Int, sameAccount: Bool = false) async throws {
        await establishAlice()
        let model = FeedbackModel(userID: "alice", storage: drafts)
        model.text = "Alice feedback"
        let waiting = expectation(description: "first feedback held")
        var held: BoundaryHTTP?
        var feedbackRequests = 0
        var refreshRequests = 0
        let success = receipt, bootstrap = sameAccount ? aliceBootstrap : bobBootstrap
        BoundaryHTTP.handle = { transport in
            if transport.request.url!.path.hasSuffix("/feedback") {
                feedbackRequests += 1
                if feedbackRequests == 1 { held = transport; waiting.fulfill() }
                else { transport.reply(200, success) }
            } else if transport.request.url!.path.hasSuffix("/auth/refresh") {
                refreshRequests += 1
                transport.reply(200, #"{"code":0,"data":{"access_token":"test-bob-fresh","refresh_token":"test-bob-rotated","expires_in":900}}"#)
            } else { transport.reply(200, bootstrap) }
        }
        let sending = Task { await model.submit(using: WorkspaceClient(client: api)) }
        await fulfillment(of: [waiting], timeout: 5)
        api.storeTokens(sameAccount ? alice : bob)
        await sync.pull()
        XCTAssertEqual(sync.user?.id, sameAccount ? "alice" : "bob")
        held?.reply(status, status == 401 ? #"{"code":40100,"message":"expired"}"# : receipt)
        await sending.value
        XCTAssertEqual(feedbackRequests, 1)
        XCTAssertEqual(refreshRequests, 0)
        try assertDraftRetained(model)
    }

    func testFeedbackCannotStartWithAnotherAccountsCurrentSession() async throws {
        await establishAlice()
        api.storeTokens(bob)
        let bootstrap = bobBootstrap
        BoundaryHTTP.handle = { $0.reply(200, bootstrap) }
        await sync.pull()
        var requests = 0
        let success = receipt
        BoundaryHTTP.handle = { requests += 1; $0.reply(200, success) }
        let model = FeedbackModel(userID: "alice", storage: drafts)
        model.text = "Alice feedback"
        await model.submit(using: WorkspaceClient(client: api))
        XCTAssertEqual(requests, 0)
        try assertDraftRetained(model)
    }

    func testRefreshCannotOverwriteNewSession() async {
        await establishAlice()
        let waiting = expectation(description: "refresh held")
        var held: BoundaryHTTP?
        BoundaryHTTP.handle = { held = $0; waiting.fulfill() }
        let refreshing = Task { await api.refreshSession() }
        await fulfillment(of: [waiting], timeout: 5)
        api.storeTokens(bob)
        held?.reply(200, refreshedAlice)
        let refreshed = await refreshing.value
        XCTAssertFalse(refreshed)
        XCTAssertEqual(api.tokens?.accessToken, bob.accessToken)
    }

    func testFeedbackRefreshInFlightCannotOverwriteSessionOrRetryOldBody() async throws {
        await establishAlice()
        let model = FeedbackModel(userID: "alice", storage: drafts)
        model.text = "Alice feedback"
        let waiting = expectation(description: "feedback refresh held")
        var held: BoundaryHTTP?
        var feedbackRequests = 0
        let success = receipt, bootstrap = bobBootstrap
        BoundaryHTTP.handle = { transport in
            if transport.request.url!.path.hasSuffix("/auth/refresh") { held = transport; waiting.fulfill() }
            else if transport.request.url!.path.hasSuffix("/feedback") {
                feedbackRequests += 1
                transport.reply(feedbackRequests == 1 ? 401 : 200,
                    feedbackRequests == 1 ? #"{"code":40100,"message":"expired"}"# : success)
            } else { transport.reply(200, bootstrap) }
        }
        let sending = Task { await model.submit(using: WorkspaceClient(client: api)) }
        await fulfillment(of: [waiting], timeout: 5)
        api.storeTokens(bob)
        await sync.pull()
        held?.reply(200, refreshedAlice)
        await sending.value
        XCTAssertEqual(api.tokens?.accessToken, bob.accessToken)
        XCTAssertEqual(feedbackRequests, 1)
        try assertDraftRetained(model)
    }

    func testFeedbackSameSessionRefreshCanConfirmAndClearDraft() async throws {
        await establishAlice()
        let model = FeedbackModel(userID: "alice", storage: drafts)
        model.text = "Alice feedback"
        var requests = 0
        let fresh = refreshedAlice, success = receipt
        BoundaryHTTP.handle = { transport in
            if transport.request.url!.path.hasSuffix("/auth/refresh") { transport.reply(200, fresh) }
            else {
                requests += 1
                transport.reply(requests == 1 ? 401 : 200,
                    requests == 1 ? #"{"code":40100,"message":"expired"}"# : success)
            }
        }
        await model.submit(using: WorkspaceClient(client: api))
        XCTAssertEqual(requests, 2)
        XCTAssertEqual(model.receipt?.ticketId, "ticket-test")
        XCTAssertNil(try drafts.load(userID: "alice", draftID: "composer"))
    }

    func testLogoutWindowBlocksPullPushAndGuestAndRejectsLateBootstrap() async throws {
        await establishAlice()
        store.updatePreferences { $0.reduceMotion = true }
        store.updateSettings { $0.name = "pending edit" }
        let loggingOut = expectation(description: "logout held")
        let pullObserved = expectation(description: "pull returned or reached transport")
        var logout: BoundaryHTTP?
        var lateBootstrap: BoundaryHTTP?
        var forbiddenRequests = 0
        let bootstrap = aliceBootstrap, tokens = refreshedAlice
        BoundaryHTTP.handle = { transport in
            if transport.request.url!.path.hasSuffix("/auth/logout") {
                XCTAssertEqual(transport.request.value(forHTTPHeaderField: "Authorization"), "Bearer test-alice")
                logout = transport; loggingOut.fulfill()
            } else {
                forbiddenRequests += 1
                if transport.request.url!.path.hasSuffix("/bootstrap") {
                    lateBootstrap = transport; pullObserved.fulfill()
                } else { transport.reply(200, transport.request.url!.path.hasSuffix("/auth/guest") ? tokens : bootstrap) }
            }
        }
        let exiting = Task { await sync.logout() }
        await fulfillment(of: [loggingOut], timeout: 5)
        XCTAssertFalse(api.hasSession, "local credentials must disappear before remote logout returns")
        let pulling = Task {
            await sync.pull()
            if lateBootstrap == nil { pullObserved.fulfill() }
        }
        await fulfillment(of: [pullObserved], timeout: 5)
        let guestAllowed = await sync.ensureSession()
        XCTAssertFalse(guestAllowed)
        let pushing = Task { await sync.pushDirty() }
        logout?.reply(200, #"{"code":0,"data":{}}"#)
        await exiting.value
        XCTAssertNil(sync.user)
        XCTAssertEqual(store.preferences, .defaults)
        lateBootstrap?.reply(200, aliceBootstrap)
        await pulling.value
        await pushing.value
        await sync.syncOnForeground()
        XCTAssertEqual(forbiddenRequests, 0)
        XCTAssertFalse(api.hasSession)
        XCTAssertNil(sync.user, "feedback route must remain signed out")
        XCTAssertEqual(store.preferences, .defaults)
    }

    func testGuestResponseAfterLogoutCannotCreateSession() async {
        api.clearTokens()
        let waiting = expectation(description: "guest held")
        var held: BoundaryHTTP?
        BoundaryHTTP.handle = { held = $0; waiting.fulfill() }
        let creating = Task { await sync.ensureSession() }
        await fulfillment(of: [waiting], timeout: 5)
        await sync.logout()
        held?.reply(200, refreshedAlice)
        let created = await creating.value
        XCTAssertFalse(created)
        XCTAssertFalse(api.hasSession)
        XCTAssertNil(sync.user)
    }

    func testExplicitLoginAfterLogoutCanEstablishFreshAccount() async throws {
        await establishAlice()
        BoundaryHTTP.handle = { $0.reply(200, #"{"code":0,"data":{}}"#) }
        await sync.logout()
        store.completeOnboarding(useSample: false)
        let bootstrap = bobBootstrap
        BoundaryHTTP.handle = { transport in
            if transport.request.url!.path.hasSuffix("/auth/login") {
                transport.reply(200, #"{"code":0,"data":{"access_token":"test-bob","refresh_token":"test-bob-refresh","expires_in":900}}"#)
            } else { transport.reply(200, bootstrap) }
        }
        try await sync.login(identifier: "test-login", code: "000000")
        XCTAssertEqual(sync.user?.id, "bob")
        XCTAssertEqual(api.tokens?.accessToken, bob.accessToken)
    }

    func testLoginInvalidatedDebounceDoesNotBlockNextEdit() async throws {
        try await assertDebounceSurvivesSessionChange(waitForOldTimer: true)
    }

    func testLoginReplacesPendingDebounceAndCoalescesImmediateEdits() async throws {
        try await assertDebounceSurvivesSessionChange(waitForOldTimer: false)
    }

    func testLogoutCancelledDebounceDoesNotBlockNewLoginEdits() async throws {
        try await assertDebounceSurvivesSessionChange(waitForOldTimer: false, logoutFirst: true)
    }

    private func assertDebounceSurvivesSessionChange(waitForOldTimer: Bool, logoutFirst: Bool = false) async throws {
        await establishAlice()
        store.completeOnboarding(useSample: false)
        let bootstrap = bobBootstrap
        var pushes = 0
        var pushed: XCTestExpectation?
        BoundaryHTTP.handle = { transport in
            if transport.request.url!.path.hasSuffix("/auth/login") {
                transport.reply(200, #"{"code":0,"data":{"access_token":"test-bob","refresh_token":"test-bob-refresh","expires_in":900}}"#)
            } else {
                if transport.request.url!.path.hasSuffix("/sync") { pushes += 1; pushed?.fulfill() }
                transport.reply(200, bootstrap)
            }
        }
        store.onDirty = { [sync] in sync?.schedulePush() }
        store.updateSettings { $0.name = "before login" }
        await Task.yield()
        if logoutFirst { await sync.logout() }
        try await sync.login(identifier: "test-login", code: "000000")
        XCTAssertEqual(sync.user?.id, "bob")
        if waitForOldTimer { try await Task.sleep(nanoseconds: 2_200_000_000) }
        pushes = 0
        pushed = expectation(description: "new edit is automatically pushed")
        pushed?.assertForOverFulfill = true
        store.updateSettings { $0.name = "after login" }
        store.updateSettings { $0.name = "coalesced edit" }
        await fulfillment(of: [pushed!], timeout: 4)
        // Observe another entire debounce window: the two edits must not leave
        // a duplicate scheduled push after the first request is acknowledged.
        try await Task.sleep(nanoseconds: 2_200_000_000)
        XCTAssertEqual(pushes, 1)
        store.onDirty = nil
    }
}
