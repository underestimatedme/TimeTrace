import SwiftUI

@main
struct KeJiApp: App {
    @State private var environment = AppEnvironment(options: .current)

    var body: some Scene {
        WindowGroup {
            RootView()
                .environment(environment.store)
                .environment(environment.router)
                .environment(environment.sync)
                .environment(environment.remote)
                .environment(environment)
                // keji://pair?code=… ——电脑上 `keji cloud login` 打印的二维码用系统相机扫到后会走这里。
                .onOpenURL { url in
                    if let link = PairingLink.parse(url) { environment.router.openPairing(link) }
                }
        }
    }
}

/// Wires store ↔ persistence ↔ sync ↔ router according to launch options.
@Observable @MainActor
final class AppEnvironment {
    let options: LaunchOptions
    let store: AppStore
    let router: AppRouter
    let sync: SyncEngine
    let remote: RemoteExecutionClient
    let stateStore: StateStore
    let feedbackDraftStore: FeedbackDraftStore

    @ObservationIgnored private var saveTask: _Concurrency.Task<Void, Never>?

    init(options: LaunchOptions) {
        self.options = options
        feedbackDraftStore = options.uiTesting
            ? FeedbackDraftStore(directory: FileManager.default.temporaryDirectory.appendingPathComponent("feedback-ui-tests"))
            : FeedbackDraftStore()
        let store = AppStore()
        let router = AppRouter()
        let stateStore = StateStore(fileName: options.uiTesting ? "keji-ui-testing-state.json" : StateStore.fileName)
        self.store = store
        self.router = router
        self.stateStore = stateStore

        if options.resetState { stateStore.clear() }
        if options.workspaceFixture {
            store.resetToWorkspaceFixture()
        } else if options.sampleData {
            store.resetToSample()
        } else if let persisted = stateStore.load() {
            store.load(persisted)
        }
        store.loadPreferences()
        if let theme = options.theme {
            store.updateSettings { $0.theme = theme }
        }

        let client = APIClient(baseURL: options.apiBaseURL,
                               keychain: options.uiTesting ? KeychainStore(account: "ui-test-session") : KeychainStore())
        sync = SyncEngine(store: store, client: client, enabled: !options.offline)
        remote = RemoteExecutionClient(client: client)
        if !options.offline {
            store.workspaceClient = WorkspaceClient(client: client)
            let sync = self.sync
            store.preparePlanDispatch = { [weak sync] in
                guard let sync else { throw APIError.noSession }
                try await sync.prepareForPlanDispatch()
            }
            store.refreshPlanProjection = { [weak sync] in await sync?.pull() }
        }
        store.onChange = { [weak self] in self?.scheduleSave() }
        if options.sampleData { scheduleSave() }

        if let screen = options.screen {
            router.apply(screen: screen)
        } else if options.sampleData {
            router.phase = .main
        } else {
            router.phase = .splash
        }
    }

    private func scheduleSave() {
        saveTask?.cancel()
        saveTask = _Concurrency.Task { [weak self] in
            try? await _Concurrency.Task.sleep(nanoseconds: 500_000_000)
            guard !_Concurrency.Task.isCancelled else { return }
            self?.saveNow()
        }
    }

    func saveNow() {
        stateStore.save(store.persisted)
    }
}
