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
                    if let link = PairingLink.parse(url) {
                        UsageEvents.shared.record(.pairingStep, ["step": .string("link"), "result": .string("received")])
                        environment.router.openPairing(link)
                    }
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
        UsageEvents.shared.configure(
            fileURL: UsageEvents.defaultFileURL(uiTesting: options.uiTesting),
            // 设备级开关，与账号无关；UI 测试用独立的 defaults，不碰真实设置。
            defaults: (options.uiTesting ? UserDefaults(suiteName: "keji-ui-testing") : nil) ?? .standard,
            offline: options.offline,
            appVersion: AppEnvironment.appVersion
        ) { [client] body in
            _ = try await client.send(.usageEvents(body), as: UsageEventsReceipt.self)
        }
        UsageEvents.shared.record(.appOpen)
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

    /// 「0.2.0 (2026092601)」；只用于统计按版本拆分，不含设备或账号信息。
    static var appVersion: String {
        let info = Bundle.main.infoDictionary
        let version = info?["CFBundleShortVersionString"] as? String ?? "?"
        let build = info?["CFBundleVersion"] as? String ?? "?"
        return String("\(version) (\(build))".prefix(32))
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
