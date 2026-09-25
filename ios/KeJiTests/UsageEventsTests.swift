import XCTest
@testable import KeJi

/// 「帮助改进刻迹」匿名使用统计：只收白名单事件与白名单字段，绝不带任务标题、提示词、路径或账号。
@MainActor final class UsageEventsTests: XCTestCase {
    private var directory: URL!
    private var defaults: UserDefaults!
    private let suite = "keji-usage-tests"

    override func setUp() async throws {
        directory = FileManager.default.temporaryDirectory.appendingPathComponent("usage-\(UUID().uuidString)")
        defaults = UserDefaults(suiteName: suite)
        defaults.removePersistentDomain(forName: suite)
    }

    override func tearDown() async throws {
        try? FileManager.default.removeItem(at: directory)
        defaults.removePersistentDomain(forName: suite)
    }

    private final class Recorder {
        var batches: [UsageEventsBody] = []
        var failure: Error?
    }

    private func logger(offline: Bool = false, recorder: Recorder = Recorder()) -> UsageEvents {
        let logger = UsageEvents()
        logger.configure(fileURL: directory.appendingPathComponent("events.json"), defaults: defaults,
                         offline: offline, appVersion: "0.2.0 (1)") { body in
            if let failure = recorder.failure { throw failure }
            recorder.batches.append(body)
        }
        logger.persistSynchronously = true
        return logger
    }

    // MARK: - Sanitizer

    func testSanitizerKeepsOnlyAllowlistedKeysAndTruncates() {
        let long = String(repeating: "长", count: 80)
        let event = UsageSanitizer.sanitize(.dispatchFailed, props: [
            "tool": .string("codex"), "scheduled": .bool(true), "error_code": .number(42230),
            "title": .string("修复登录页"), "prompt": .string("帮我改代码"), "repo_path": .string("/Users/me/repo"),
            "account": .string("me@example.com"), "source": .string(long),
        ], at: Date(timeIntervalSince1970: 0))
        XCTAssertEqual(Set(event.props.keys), ["tool", "scheduled", "error_code", "source"])
        XCTAssertEqual(event.props["source"], .string(String(repeating: "长", count: 64)))
        XCTAssertEqual(event.name, "dispatch_failed")
    }

    func testSanitizerDropsNonFiniteNumbersAndUnlistedKeysForEachEvent() {
        let event = UsageSanitizer.sanitize(.quotaViewed, props: ["pools": .number(.nan), "screen": .string("ai")], at: Date())
        XCTAssertTrue(event.props.isEmpty)
        // Scalars count like the server's rune count: an emoji flag is two scalars.
        let flags = String(repeating: "🇨🇳", count: 40)
        let truncated = UsageSanitizer.sanitize(.screenView, props: ["screen": .string(flags)], at: Date())
        guard case .string(let value)? = truncated.props["screen"] else { return XCTFail("screen missing") }
        XCTAssertEqual(value.unicodeScalars.count, 64)
        for name in UsageEventName.allCases {
            XCTAssertLessThanOrEqual(UsageSanitizer.allowedKeys[name, default: []].count, 8)
            for key in UsageSanitizer.allowedKeys[name, default: []] {
                XCTAssertNotNil(key.range(of: "^[a-z_]{1,32}$", options: .regularExpression), key)
            }
        }
    }

    func testEventsEncodeLikeTheServerContract() throws {
        let event = UsageSanitizer.sanitize(.pairingStep, props: ["step": .string("approve"), "result": .string("ok")],
                                            at: ISO8601.date(from: "2026-09-15T10:00:00.000Z")!)
        let data = try JSONCoding.encoder.encode(UsageEventsBody(events: [event], appVersion: "0.2.0 (1)"))
        let json = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
        XCTAssertEqual(json["app_version"] as? String, "0.2.0 (1)")
        let first = try XCTUnwrap((json["events"] as? [[String: Any]])?.first)
        XCTAssertEqual(first["name"] as? String, "pairing_step")
        XCTAssertEqual(first["at"] as? String, "2026-09-15T10:00:00.000Z")
        XCTAssertEqual(first["props"] as? [String: String], ["step": "approve", "result": "ok"])
    }

    // MARK: - Consent, offline, buffer

    func testDefaultOnAndTurningOffStopsRecordingAndClearsBuffer() {
        let events = logger()
        XCTAssertTrue(events.isEnabled, "default on")
        events.record(.appOpen)
        XCTAssertEqual(events.buffered.count, 1)
        events.isEnabled = false
        XCTAssertTrue(events.buffered.isEmpty)
        events.record(.appOpen)
        XCTAssertTrue(events.buffered.isEmpty)
        // The choice survives a relaunch and the cleared buffer stays cleared.
        let relaunched = logger()
        XCTAssertFalse(relaunched.isEnabled)
        XCTAssertTrue(relaunched.buffered.isEmpty)
    }

    func testOfflineModeDropsSilently() {
        let events = logger(offline: true)
        events.record(.appOpen)
        XCTAssertTrue(events.buffered.isEmpty)
    }

    func testBufferIsBoundedAndSurvivesRelaunch() {
        let recorder = Recorder()
        recorder.failure = APIError.transport(URLError(.notConnectedToInternet))
        let events = logger(recorder: recorder)
        events.flushThreshold = 10_000
        for i in 0..<(UsageEvents.capacity + 5) {
            events.record(.screenView, ["screen": .string("s\(i)")])
        }
        XCTAssertEqual(events.buffered.count, UsageEvents.capacity)
        XCTAssertEqual(events.buffered.first?.props["screen"], .string("s5"), "oldest events are dropped first")
        let relaunched = logger(recorder: recorder)
        XCTAssertEqual(relaunched.buffered.count, UsageEvents.capacity)
        XCTAssertEqual(relaunched.buffered.last?.props["screen"], .string("s\(UsageEvents.capacity + 4)"))
    }

    // MARK: - Flush

    func testFlushSendsBatchesOfAtMostOneHundredAndClears() async {
        let recorder = Recorder()
        let events = logger(recorder: recorder)
        events.flushThreshold = 10_000
        for _ in 0..<150 { events.record(.appOpen) }
        await events.flush()
        XCTAssertEqual(recorder.batches.map(\.events.count), [100, 50])
        XCTAssertEqual(recorder.batches.first?.appVersion, "0.2.0 (1)")
        XCTAssertTrue(events.buffered.isEmpty)
    }

    func testTransportFailureKeepsEventsButRejectedBatchIsDropped() async {
        let recorder = Recorder()
        let events = logger(recorder: recorder)
        events.flushThreshold = 10_000
        events.record(.appOpen)
        recorder.failure = APIError.transport(URLError(.timedOut))
        await events.flush()
        XCTAssertEqual(events.buffered.count, 1)
        recorder.failure = APIError.noSession
        await events.flush()
        XCTAssertEqual(events.buffered.count, 1)
        // A 422 means the client sent something the server will never take: drop it.
        recorder.failure = APIError(code: 42230, message: "invalid usage events")
        await events.flush()
        XCTAssertTrue(events.buffered.isEmpty)
    }

    func testReachingThresholdFlushesInBackground() async throws {
        let recorder = Recorder()
        let events = logger(recorder: recorder)
        for _ in 0..<UsageEvents.defaultFlushThreshold { events.record(.appOpen) }
        for _ in 0..<50 where recorder.batches.isEmpty { try await Task.sleep(nanoseconds: 20_000_000) }
        XCTAssertEqual(recorder.batches.first?.events.count, UsageEvents.defaultFlushThreshold)
        XCTAssertTrue(events.buffered.isEmpty)
    }

    func testDisabledLoggerNeverSends() async {
        let recorder = Recorder()
        let events = logger(recorder: recorder)
        events.record(.appOpen)
        events.isEnabled = false
        await events.flush()
        XCTAssertTrue(recorder.batches.isEmpty)
    }
}
