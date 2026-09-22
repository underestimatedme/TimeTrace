import Foundation
import Observation

/// Stores user-written feedback only. Atomic writes finish before networking.
final class FeedbackDraftStore {
    private let directory: URL

    init(directory: URL = URL.applicationSupportDirectory.appendingPathComponent("FeedbackDrafts", isDirectory: true)) {
        self.directory = directory
    }

    private func file(userID: String, draftID: String) -> URL {
        func component(_ value: String) -> String { value.utf8.map { String(format: "%02x", $0) }.joined() }
        return directory.appendingPathComponent(component(userID), isDirectory: true)
            .appendingPathComponent(component(draftID) + ".json")
    }

    func load(userID: String, draftID: String) throws -> FeedbackDraft? {
        let url = file(userID: userID, draftID: draftID)
        guard FileManager.default.fileExists(atPath: url.path) else { return nil }
        return try JSONCoding.decoder.decode(FeedbackDraft.self, from: Data(contentsOf: url))
    }

    func save(_ draft: FeedbackDraft, userID: String, draftID: String) throws {
        let url = file(userID: userID, draftID: draftID)
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try JSONCoding.encoder.encode(draft).write(to: url, options: [.atomic, .completeFileProtection])
    }

    func removeConfirmed(_ draft: FeedbackDraft, userID: String, draftID: String) throws {
        guard try load(userID: userID, draftID: draftID) == draft else { return }
        try FileManager.default.removeItem(at: file(userID: userID, draftID: draftID))
    }
}

struct FeedbackReceipt: Codable, Equatable {
    var ticketId: String
    var body: String
    var status: String
}

@Observable @MainActor
final class FeedbackModel {
    let userID: String
    let draftID: String
    private let storage: FeedbackDraftStore
    private(set) var draft = FeedbackDraft.new(text: "")
    private(set) var error: String?
    private(set) var submitting = false
    private(set) var receipt: FeedbackReceipt?

    init(userID: String, draftID: String = "composer", storage: FeedbackDraftStore) {
        self.userID = userID
        self.draftID = draftID
        self.storage = storage
        do {
            if let saved = try storage.load(userID: userID, draftID: draftID) { draft = saved }
        } catch { self.error = "草稿读取失败，请稍后重试。" }
    }

    var text: String {
        get { draft.text }
        set {
            guard !draft.attempted, receipt == nil, !submitting else { return }
            draft.text = newValue
            persist()
        }
    }

    /// 诊断信息是 opt-in；一旦请求可能已到达服务端就不再改，保证重试发送同一份内容。
    var attachDiagnostics: Bool {
        get { draft.attachDiagnostics }
        set {
            guard !draft.attempted, receipt == nil, !submitting else { return }
            draft.attachDiagnostics = newValue
            persist()
        }
    }

    var canSubmit: Bool { !submitting && receipt == nil && draft.isValid }
    var status: String {
        if let receipt { return "已提交 · 工单 \(receipt.ticketId)" }
        if submitting { return "提交中…" }
        if let error { return error }
        return "仅本机草稿，尚未提交。"
    }

    @discardableResult private func persist() -> Bool {
        do {
            try storage.save(draft, userID: userID, draftID: draftID)
            error = nil
            return true
        } catch {
            self.error = "草稿保存失败，未提交。请检查本机存储后重试。"
            return false
        }
    }

    func submit(using client: WorkspaceClient?) async {
        guard let client else { _ = persist(); return }
        do {
            let identity = try client.feedbackSession(for: userID)
            await submit(validate: { try client.validateFeedbackSession(identity) }) {
                try await client.submitFeedback($0, identity: identity)
            }
        } catch { self.error = "账号会话已变化；仅本机草稿已保留。" }
    }

    func submit(validate: () throws -> Void = {}, _ send: (FeedbackDraft) async throws -> FeedbackReceipt) async {
        guard canSubmit else { return }
        draft.text = draft.text.trimmingCharacters(in: .whitespacesAndNewlines)
        draft.attempted = true
        guard persist() else { return }
        let sent = draft
        submitting = true
        defer { submitting = false }
        do {
            let confirmed = try await send(sent)
            // Recheck after the model's own await, immediately before clearing
            // persistent state; a valid earlier response is not enough.
            try validate()
            guard !confirmed.ticketId.isEmpty, confirmed.body == sent.text,
                  ["received", "open", "in_progress", "resolved", "closed"].contains(confirmed.status) else {
                throw APIError(code: -8, message: "服务端未确认收到反馈")
            }
            try storage.removeConfirmed(sent, userID: userID, draftID: draftID)
            receipt = confirmed
            draft.text = ""
            error = nil
        } catch {
            self.error = "提交未确认；仅本机草稿已保留，可重试。"
        }
    }
}
