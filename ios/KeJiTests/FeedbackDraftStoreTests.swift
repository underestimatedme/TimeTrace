import XCTest
@testable import KeJi

@MainActor final class FeedbackDraftStoreTests: XCTestCase {
    private func directory() throws -> URL {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        addTeardownBlock { try? FileManager.default.removeItem(at: url) }
        return url
    }

    func testDraftContentAndKeySurviveRecreationAndAreScopedByAccountAndDraft() throws {
        let dir = try directory()
        let first = FeedbackModel(userID: "alice", draftID: "one", storage: FeedbackDraftStore(directory: dir))
        first.text = "Cannot open my task"
        let key = first.draft.idempotencyKey
        let reopened = FeedbackModel(userID: "alice", draftID: "one", storage: FeedbackDraftStore(directory: dir))
        XCTAssertEqual(reopened.text, "Cannot open my task")
        XCTAssertEqual(reopened.draft.idempotencyKey, key)
        for (user, draft) in [("bob", "one"), ("alice", "two")] {
            let other = FeedbackModel(userID: user, draftID: draft, storage: FeedbackDraftStore(directory: dir))
            XCTAssertEqual(other.text, "")
            XCTAssertNotEqual(other.draft.idempotencyKey, key)
        }
    }

    func testFailedSubmissionPersistsBeforeNetworkAndReusesFrozenPayloadAndKey() async throws {
        let dir = try directory()
        let storage = FeedbackDraftStore(directory: dir)
        let first = FeedbackModel(userID: "alice", storage: storage)
        first.text = "Cannot open my task"
        let key = first.draft.idempotencyKey
        await first.submit { draft in
            let persisted = try XCTUnwrap(storage.load(userID: "alice", draftID: "composer"))
            XCTAssertEqual(persisted, draft)
            XCTAssertTrue(persisted.attempted)
            throw URLError(.networkConnectionLost)
        }
        XCTAssertNotNil(first.error)
        XCTAssertNil(first.receipt)
        XCTAssertFalse(first.submitting)
        first.text = "changed while the server may already have accepted"
        XCTAssertEqual(first.text, "Cannot open my task")
        let next = FeedbackModel(userID: "alice", storage: FeedbackDraftStore(directory: dir))
        XCTAssertEqual(next.draft.idempotencyKey, key)
        await next.submit { draft in
            XCTAssertEqual(draft.idempotencyKey, key)
            return FeedbackReceipt(ticketId: "ticket-1", body: draft.text, status: "received")
        }
        XCTAssertEqual(next.receipt?.ticketId, "ticket-1")
        XCTAssertNil(try storage.load(userID: "alice", draftID: "composer"))
    }

    func testOfflineOrUnconfirmedResponseNeverClaimsSubmissionOrClearsDraft() async throws {
        let storage = FeedbackDraftStore(directory: try directory())
        let model = FeedbackModel(userID: "alice", storage: storage)
        model.text = "Need help"
        await model.submit(using: nil)
        XCTAssertTrue(model.status.contains("仅本机草稿"))
        XCTAssertNil(model.receipt)
        await model.submit { _ in FeedbackReceipt(ticketId: "", body: "Need help", status: "received") }
        XCTAssertNil(model.receipt)
        XCTAssertNotNil(try storage.load(userID: "alice", draftID: "composer"))
    }

    func testPersistenceFailurePreventsNetworkRequest() async throws {
        let file = try directory().appendingPathComponent("file")
        try Data().write(to: file)
        let model = FeedbackModel(userID: "alice", storage: FeedbackDraftStore(directory: file))
        model.text = "Need help"
        await model.submit { _ in XCTFail("unsaved draft sent"); throw URLError(.badURL) }
        XCTAssertNotNil(model.error)
        XCTAssertNil(model.receipt)
    }

    func testAccountSwitchDuringSubmissionCannotClearOtherAccountDraft() async throws {
        let storage = FeedbackDraftStore(directory: try directory())
        let alice = FeedbackModel(userID: "alice", storage: storage)
        alice.text = "Alice draft"
        var continuation: CheckedContinuation<FeedbackReceipt, Never>?
        let request = Task { await alice.submit { _ in await withCheckedContinuation { continuation = $0 } } }
        while continuation == nil { await Task.yield() }
        XCTAssertTrue(alice.submitting)
        let bob = FeedbackModel(userID: "bob", storage: storage)
        XCTAssertEqual(bob.text, "")
        bob.text = "Bob draft"
        continuation?.resume(returning: FeedbackReceipt(ticketId: "alice-ticket", body: "Alice draft", status: "received"))
        await request.value
        XCTAssertNil(bob.receipt)
        XCTAssertEqual(try storage.load(userID: "bob", draftID: "composer")?.text, "Bob draft")
    }

    func testFeedbackPayloadContainsOnlyApprovedFieldsAndRejectsSecrets() throws {
        let draft = FeedbackDraft.new(text: "Please help", attachDiagnostics: true)
        let endpoint = try Endpoint.feedback(draft)
        let data = try JSONCoding.encoder.encode(AnyEncodable(try XCTUnwrap(endpoint.body)))
        let payload = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
        // include_diagnostics 是 Valley 契约里唯一的附加字段，且只是一个布尔 opt-in，不带任何环境内容。
        XCTAssertEqual(Set(payload.keys), ["body", "idempotency_key", "include_diagnostics"])
        XCTAssertEqual(payload["body"] as? String, "Please help")
        XCTAssertEqual(payload["idempotency_key"] as? String, draft.idempotencyKey)
        XCTAssertEqual(payload["include_diagnostics"] as? Bool, true)
        for secret in ["token=abc", "Authorization: Bearer abc", "me@example.com", "API_KEY=abc", "environment_snapshot: {}", #"{"token":"secret"}"#, #"{"environment":{"HOME":"private"}}"#] {
            XCTAssertThrowsError(try Endpoint.feedback(.new(text: secret)))
        }
    }

    func testReplayReceiptAlreadyProcessedBySupportStillConfirmsSubmission() async throws {
        for status in ["open", "in_progress", "resolved", "closed"] {
            let storage = FeedbackDraftStore(directory: try directory())
            let model = FeedbackModel(userID: "alice", storage: storage)
            model.text = "Help"
            await model.submit { draft in FeedbackReceipt(ticketId: "processed", body: draft.text, status: status) }
            XCTAssertEqual(model.receipt?.ticketId, "processed")
            XCTAssertNil(try storage.load(userID: "alice", draftID: "composer"))
        }
    }
}
