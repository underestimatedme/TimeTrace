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
                .environment(environment)
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
    let stateStore: StateStore

    @ObservationIgnored private var saveTask: _Concurrency.Task<Void, Never>?

    init(options: LaunchOptions) {
        self.options = options
        let store = AppStore()
        let router = AppRouter()
        let stateStore = StateStore()
        self.store = store
        self.router = router
        self.stateStore = stateStore

        if options.sampleData {
            store.resetToSample()
        } else if let persisted = stateStore.load() {
            store.load(persisted)
        }
        if let theme = options.theme {
            store.updateSettings { $0.theme = theme }
        }

        let client = APIClient(baseURL: options.apiBaseURL)
        sync = SyncEngine(store: store, client: client, enabled: !options.offline)
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
