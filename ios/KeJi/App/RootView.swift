import SwiftUI

/// Splash → Onboarding → Tabs; applies the theme environment and drives the 1s tick.
struct RootView: View {
    @Environment(AppStore.self) private var store
    @Environment(AppRouter.self) private var router
    @Environment(SyncEngine.self) private var sync
    @Environment(AppEnvironment.self) private var appEnv
    @Environment(\.scenePhase) private var scenePhase

    var body: some View {
        let theme = Theme.named(store.settings.theme)
        Group {
            switch router.phase {
            case .splash: SplashView()
            case .onboarding: OnboardingView()
            case .main: MainShellView()
            }
        }
        .environment(\.theme, theme)
        .preferredColorScheme(theme.isDark ? .dark : .light)
        .tint(theme.accent)
        .animation(.easeInOut(duration: 0.3), value: router.phase)
        .task {
            await sync.syncOnForeground()
            while !_Concurrency.Task.isCancelled {
                try? await _Concurrency.Task.sleep(nanoseconds: 1_000_000_000)
                store.tick()
            }
        }
        .onChange(of: scenePhase) { _, phase in
            switch phase {
            case .active:
                store.now = Date()
                _Concurrency.Task { await sync.syncOnForeground() }
            case .background, .inactive:
                appEnv.saveNow()
            @unknown default: break
            }
        }
    }
}

extension RootPhase: Equatable {}

/// NavigationStack wrapping the tabs; sub-pages push on top (no tab bar, like the prototype).
struct MainShellView: View {
    @Environment(AppRouter.self) private var router

    var body: some View {
        @Bindable var router = router
        NavigationStack(path: $router.path) {
            MainTabView()
                .toolbar(.hidden, for: .navigationBar)
                .navigationDestination(for: Route.self) { route in
                    destination(route)
                }
        }
    }

    @ViewBuilder
    private func destination(_ route: Route) -> some View {
        switch route {
        case .taskCreate: TaskCreateView()
        case .taskDetail(let id): TaskDetailView(taskId: id)
        case .plan(let id): PlanDetailView(planId: id)
        case .reports(let scope): ReportsView(scope: scope)
        case .focus(let id): FocusView(taskId: id)
        case .ai(let id): AIExecutionView(taskId: id)
        case .projects: ProjectsView()
        case .project(let id): ProjectDetailView(projectId: id)
        case .goal(let id): GoalDetailView(goalId: id)
        case .aiTools: AIToolsView()
        case .appearance: AppearanceView()
        case .account: AccountView()
        }
    }
}
