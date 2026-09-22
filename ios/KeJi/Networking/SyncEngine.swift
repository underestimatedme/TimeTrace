import Foundation
import Observation

/// Offline-first sync: local store is truth; dirty entities are coalesced over 2s and the
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
    @ObservationIgnored private var pushTaskID: UUID?
    @ObservationIgnored private var inFlight = false
    @ObservationIgnored private var completionWaiters: [CheckedContinuation<Void, Never>] = []
    @ObservationIgnored private var sessionTask: _Concurrency.Task<Bool, Never>?
    @ObservationIgnored private var sessionGeneration: UInt64 = 0
    @ObservationIgnored private var loggingOut = false
    @ObservationIgnored private var sessionSuppressed = false
    private static let userKey = "keji.sync.user"

    init(store: AppStore, client: APIClient, enabled: Bool) {
        self.store = store
        self.client = client
        self.enabled = enabled
        if !enabled { status = .offline }
        if enabled, client.hasSession, let data = UserDefaults.standard.data(forKey: SyncEngine.userKey) {
            user = try? JSONCoding.decoder.decode(UserInfo.self, from: data)
        }
        // Offline mode has no account but must still keep preferences across launches,
        // so it owns a fixed local identity; online, preferences follow the account.
        store.loadPreferences(userID: enabled ? (client.hasSession ? user?.id : nil) : SyncEngine.offlineIdentity)
        store.onDirty = { [weak self] in self?.schedulePush() }
    }

    /// Identity used for local-only state (preferences, feedback drafts) when networking is disabled.
    static let offlineIdentity = "local-offline"

    var isLoggedIn: Bool { (user?.isGuest == false) }
    var hasSession: Bool { client.hasSession }

    private var canSynchronize: Bool { enabled && !loggingOut && !sessionSuppressed }
    private func isCurrent(_ generation: UInt64) -> Bool {
        canSynchronize && generation == sessionGeneration
    }

    // MARK: - Session

    /// Creates a guest session if there are no tokens yet. Concurrent callers
    /// (a pull on appear racing a debounced push) share one in-flight request so
    /// only a single guest account is ever created.
    func ensureSession() async -> Bool {
        guard canSynchronize else { return false }
        let generation = sessionGeneration
        if client.hasSession { return true }
        if let running = sessionTask {
            let result = await running.value
            return isCurrent(generation) && result
        }
        let task = _Concurrency.Task<Bool, Never> { [client] in
            do {
                let tokens = try await client.send(Endpoint.guest, as: SessionTokens.self)
                guard self.isCurrent(generation) else { return false }
                client.storeTokens(tokens)
                return true
            } catch {
                if self.isCurrent(generation) { self.fail(error) }
                return false
            }
        }
        sessionTask = task
        let ok = await task.value
        if generation == sessionGeneration { sessionTask = nil }
        return isCurrent(generation) && ok
    }

    func sendCode(identifier: String) async throws {
        guard enabled else { throw APIError.offline }
        guard !loggingOut else { throw APIError.sessionChanged }
        let generation = sessionGeneration
        _ = try await client.send(Endpoint.sendCode(identifier: identifier), as: SendCodeResponse.self)
        guard !loggingOut, generation == sessionGeneration else { throw APIError.sessionChanged }
    }

    /// Upgrades the guest (bearer attached when available) and pulls the merged state.
    func login(identifier: String, code: String) async throws {
        guard enabled else { throw APIError.offline }
        guard !loggingOut else { throw APIError.sessionChanged }
        let previousGeneration = sessionGeneration
        let tokens = try await client.send(Endpoint.login(identifier: identifier, code: code), as: SessionTokens.self)
        guard !loggingOut, previousGeneration == sessionGeneration else { throw APIError.sessionChanged }
        cancelScheduledPush()
        sessionGeneration &+= 1
        let generation = sessionGeneration
        sessionSuppressed = false // Only explicit login re-enables a logged-out engine.
        client.storeTokens(tokens)
        setUser(nil) // Do not show the previous account while bootstrap is pending.
        await waitForCompletion()
        guard isCurrent(generation) else { throw APIError.sessionChanged }
        await syncOnForeground()
        guard isCurrent(generation) else { throw APIError.sessionChanged }
    }

    func logout() async {
        guard enabled, !loggingOut else { return }
        loggingOut = true
        sessionSuppressed = true
        sessionGeneration &+= 1
        cancelScheduledPush()
        sessionTask?.cancel()
        sessionTask = nil
        let credentials = client.tokens
        client.clearTokens()
        let clearedGeneration = client.sessionGeneration
        setUser(nil)
        status = .idle
        if let credentials {
            try? await client.revokeSession(credentials)
        }
        // Close the window a second time. Never wipe a session independently
        // installed while the old account's remote revocation was in flight.
        sessionGeneration &+= 1
        if client.sessionGeneration == clearedGeneration { client.clearTokens() }
        setUser(nil)
        loggingOut = false
        status = .idle
    }

    /// Deletes the server account and wipes local data (spec: user and all data are deleted).
    func deleteAccount() async throws {
        guard canSynchronize else { throw APIError.noSession }
        let generation = sessionGeneration
        _ = try await client.send(Endpoint.deleteAccount, as: DeletedResponse.self)
        guard isCurrent(generation) else { throw APIError.sessionChanged }
        cancelScheduledPush()
        sessionGeneration &+= 1
        sessionSuppressed = true
        client.clearTokens()
        setUser(nil)
        store.clearAll()
        status = .idle
    }

    // MARK: - Pull / push

    private func waitForCompletion() async {
        while inFlight {
            await withCheckedContinuation { completionWaiters.append($0) }
        }
    }

    private func finishSync() {
        inFlight = false
        let waiters = completionWaiters
        completionWaiters = []
        for waiter in waiters { waiter.resume() }
    }

    /// Preserve a caller's dispatch intent until both projections are fresh.
    /// The second pull observes Task revisions changed by explicit Plan creation.
    func prepareForPlanDispatch() async throws {
        guard canSynchronize else { throw APIError.noSession }
        let generation = sessionGeneration
        await waitForCompletion()
        guard isCurrent(generation) else { throw APIError.sessionChanged }
        await syncOnForeground()
        guard isCurrent(generation) else { throw APIError.sessionChanged }
        try requireCompletedSync()
        await pull()
        guard isCurrent(generation) else { throw APIError.sessionChanged }
        try requireCompletedSync()
    }

    private func requireCompletedSync() throws {
        guard canSynchronize else { throw APIError.noSession }
        guard case .idle = status else { throw APIError(code: -7, message: status.label) }
    }

    private func refreshPlansBeforeCompletingSync() async throws {
        guard await store.refreshAllPlans() else {
            let reason = store.tasks.compactMap { store.planErrors[$0.id] }.first ?? "任务仍有待同步修改，请刷新后重试。"
            throw APIError(code: -7, message: "Plan 同步失败：" + reason)
        }
    }

    /// `GET /bootstrap` → replace local state except dirty/deleted entities.
    func pull() async {
        guard canSynchronize else { return }
        if inFlight { await waitForCompletion(); return }
        inFlight = true
        defer { finishSync() }
        status = .syncing
        let generation = sessionGeneration
        guard await ensureSession() else { return }
        guard isCurrent(generation) else { return }
        do {
            let bootstrap = try await client.send(Endpoint.bootstrap, as: Bootstrap.self)
            guard isCurrent(generation) else { return }
            apply(bootstrap)
            try await refreshPlansBeforeCompletingSync()
            guard isCurrent(generation) else { return }
            status = .idle
        } catch {
            if isCurrent(generation) { fail(error) }
        }
    }

    /// Push 2s after the first pending change, even if more changes arrive.
    func schedulePush() {
        // Coalesce into one pending push. Continuous timer updates must not postpone it forever.
        guard canSynchronize, store.hasOnboarded, pushTask == nil else { return }
        let generation = sessionGeneration
        let taskID = UUID()
        pushTaskID = taskID
        pushTask = _Concurrency.Task { [weak self] in
            try? await _Concurrency.Task.sleep(nanoseconds: 2_000_000_000)
            // An old cancelled task can resume after a replacement was installed.
            // Only the owner may release this slot, including on stale exits.
            guard let self, self.pushTaskID == taskID else { return }
            self.pushTask = nil
            self.pushTaskID = nil
            guard !_Concurrency.Task.isCancelled, self.isCurrent(generation) else { return }
            await self.pushDirty()
        }
    }

    private func cancelScheduledPush() {
        pushTaskID = nil
        pushTask?.cancel()
        pushTask = nil
    }

    func pushDirty() async {
        guard canSynchronize else { return }
        let generation = sessionGeneration
        await waitForCompletion()
        guard isCurrent(generation), store.hasPendingSync else { return }
        inFlight = true
        defer { finishSync() }
        status = .syncing
        guard await ensureSession() else { return }
        guard isCurrent(generation) else { return }

        let dirty = store.dirty
        let deleted = store.deleted
        let sendSettings = store.settingsDirty
        let sendFocus = store.activeFocusDirty
        let sendTools = store.aiToolsDirty
        let checkpoint = store.syncCheckpoint()
        let request = buildRequest(dirty: dirty, deleted: deleted, settings: sendSettings,
                                   activeFocus: sendFocus, aiTools: sendTools)
        do {
            let bootstrap = try await client.send(Endpoint.sync(request), as: Bootstrap.self)
            guard isCurrent(generation) else { return }
            store.acknowledge(checkpoint, settings: sendSettings, activeFocus: sendFocus, aiTools: sendTools)
            apply(bootstrap)
            try await refreshPlansBeforeCompletingSync()
            guard isCurrent(generation) else { return }
            status = .idle
            if store.hasPendingSync { schedulePush() }
        } catch {
            if isCurrent(generation) { fail(error) }
        }
    }

    /// Push if anything is pending, otherwise pull.
    func syncOnForeground() async {
        guard canSynchronize, store.hasOnboarded else { return }
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
        client.bindUser(u?.id)
        user = u
        store.loadPreferences(userID: u?.id)
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
