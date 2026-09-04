import Foundation
import Observation

/// Offline-first sync: local store is truth; dirty entities are pushed (debounced 2s) and the
/// merged snapshot returned by the server is applied back, preserving in-flight dirty entities.
@Observable @MainActor
final class SyncEngine {
    enum Status: Equatable {
        case idle, syncing, offline
        case error(String)

        var label: String {
            switch self {
            case .idle: return "已同步"
            case .syncing: return "同步中…"
            case .offline: return "离线"
            case .error(let m): return "同步失败：\(m)"
            }
        }
    }

    private(set) var status: Status = .idle
    private(set) var user: UserInfo?
    private(set) var lastSyncAt: Date?

    let store: AppStore
    let client: APIClient
    let enabled: Bool

    @ObservationIgnored private var pushTask: _Concurrency.Task<Void, Never>?
    @ObservationIgnored private var inFlight = false
    @ObservationIgnored private var sessionTask: _Concurrency.Task<Bool, Never>?
    private static let userKey = "keji.sync.user"

    init(store: AppStore, client: APIClient, enabled: Bool) {
        self.store = store
        self.client = client
        self.enabled = enabled
        if !enabled { status = .offline }
        if let data = UserDefaults.standard.data(forKey: SyncEngine.userKey) {
            user = try? JSONCoding.decoder.decode(UserInfo.self, from: data)
        }
        store.onDirty = { [weak self] in self?.schedulePush() }
    }

    var isLoggedIn: Bool { (user?.isGuest == false) }
    var hasSession: Bool { client.hasSession }

    // MARK: - Session

    /// Creates a guest session if there are no tokens yet. Concurrent callers
    /// (a pull on appear racing a debounced push) share one in-flight request so
    /// only a single guest account is ever created.
    func ensureSession() async -> Bool {
        guard enabled else { return false }
        if client.hasSession { return true }
        if let running = sessionTask { return await running.value }
        let task = _Concurrency.Task<Bool, Never> { [client] in
            do {
                let tokens = try await client.send(Endpoint.guest, as: SessionTokens.self)
                client.storeTokens(tokens)
                return true
            } catch {
                self.fail(error)
                return false
            }
        }
        sessionTask = task
        let ok = await task.value
        sessionTask = nil
        return ok
    }

    func sendCode(identifier: String) async throws {
        guard enabled else { throw APIError.offline }
        _ = try await client.send(Endpoint.sendCode(identifier: identifier), as: SendCodeResponse.self)
    }

    /// Upgrades the guest (bearer attached when available) and pulls the merged state.
    func login(identifier: String, code: String) async throws {
        guard enabled else { throw APIError.offline }
        let tokens = try await client.send(Endpoint.login(identifier: identifier, code: code), as: SessionTokens.self)
        client.storeTokens(tokens)
        await syncOnForeground()
    }

    func logout() async {
        guard enabled else { return }
        if client.hasSession {
            _ = try? await client.send(Endpoint.logout, as: RevokedResponse.self)
        }
        client.clearTokens()
        setUser(nil)
        status = .idle
    }

    /// Deletes the server account and wipes local data (spec: user and all data are deleted).
    func deleteAccount() async throws {
        guard enabled else { throw APIError.offline }
        _ = try await client.send(Endpoint.deleteAccount, as: DeletedResponse.self)
        client.clearTokens()
        setUser(nil)
        store.clearAll()
        status = .idle
    }

    // MARK: - Pull / push

    /// `GET /bootstrap` → replace local state except dirty/deleted entities.
    func pull() async {
        guard enabled, !inFlight else { return }
        inFlight = true
        defer { inFlight = false }
        guard await ensureSession() else { return }
        status = .syncing
        do {
            let bootstrap = try await client.send(Endpoint.bootstrap, as: Bootstrap.self)
            apply(bootstrap)
            status = .idle
        } catch {
            fail(error)
        }
    }

    /// Debounced 2s after any `markDirty`.
    func schedulePush() {
        guard enabled, store.hasOnboarded else { return }
        pushTask?.cancel()
        pushTask = _Concurrency.Task { [weak self] in
            try? await _Concurrency.Task.sleep(nanoseconds: 2_000_000_000)
            guard !_Concurrency.Task.isCancelled else { return }
            await self?.pushDirty()
        }
    }

    func pushDirty() async {
        guard enabled, store.hasPendingSync else { return }
        if inFlight {
            schedulePush()
            return
        }
        inFlight = true
        defer { inFlight = false }
        guard await ensureSession() else { return }
        status = .syncing

        let dirty = store.dirty
        let deleted = store.deleted
        let sendSettings = store.settingsDirty
        let sendFocus = store.activeFocusDirty
        let sendTools = store.aiToolsDirty
        let request = buildRequest(dirty: dirty, deleted: deleted, settings: sendSettings,
                                   activeFocus: sendFocus, aiTools: sendTools)
        do {
            let bootstrap = try await client.send(Endpoint.sync(request), as: Bootstrap.self)
            store.clearDirty(dirty, deleted: deleted, settings: sendSettings, activeFocus: sendFocus, aiTools: sendTools)
            apply(bootstrap)
            status = .idle
            if store.hasPendingSync { schedulePush() }
        } catch {
            fail(error)
        }
    }

    /// Push if anything is pending, otherwise pull.
    func syncOnForeground() async {
        guard enabled, store.hasOnboarded else { return }
        if store.hasPendingSync { await pushDirty() } else { await pull() }
    }

    func buildRequest(dirty: [SyncEntity: Set<String>], deleted: [SyncEntity: Set<String>],
                      settings: Bool, activeFocus: Bool, aiTools: Bool) -> SyncRequest {
        func ids(_ e: SyncEntity) -> Set<String> { dirty[e] ?? [] }
        let upserts = SyncUpserts(
            projects: store.projects.filter { ids(.projects).contains($0.id) },
            goals: store.goals.filter { ids(.goals).contains($0.id) },
            tasks: store.tasks.filter { ids(.tasks).contains($0.id) },
            timeSessions: store.timeSessions.filter { ids(.timeSessions).contains($0.id) },
            aiExecutions: store.aiExecutions.filter { ids(.aiExecutions).contains($0.id) },
            experiments: store.experiments.filter { ids(.experiments).contains($0.id) })
        let deletes = SyncDeletes(
            projects: Array(deleted[.projects] ?? []).sorted(),
            goals: Array(deleted[.goals] ?? []).sorted(),
            tasks: Array(deleted[.tasks] ?? []).sorted(),
            timeSessions: Array(deleted[.timeSessions] ?? []).sorted(),
            aiExecutions: Array(deleted[.aiExecutions] ?? []).sorted(),
            experiments: Array(deleted[.experiments] ?? []).sorted())
        var focus: SyncActiveFocus = .unchanged
        if activeFocus {
            focus = store.activeFocus.map { .set($0) } ?? .clear
        }
        return SyncRequest(clientTime: Date(), upserts: upserts, deletes: deletes,
                           settings: settings ? store.settings : nil, activeFocus: focus,
                           aiTools: aiTools ? store.aiTools : nil)
    }

    // MARK: - Internals

    private func apply(_ bootstrap: Bootstrap) {
        if let u = bootstrap.user { setUser(u) }
        store.applySnapshot(bootstrap.state)
        lastSyncAt = Date()
    }

    private func setUser(_ u: UserInfo?) {
        user = u
        if let u, let data = try? JSONCoding.encoder.encode(u) {
            UserDefaults.standard.set(data, forKey: SyncEngine.userKey)
        } else {
            UserDefaults.standard.removeObject(forKey: SyncEngine.userKey)
        }
    }

    private func fail(_ error: Error) {
        if let api = error as? APIError {
            status = api.code == -3 ? .offline : .error(api.message)
        } else {
            status = .error(error.localizedDescription)
        }
    }
}
