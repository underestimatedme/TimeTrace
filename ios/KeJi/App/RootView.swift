import SwiftUI

/// Splash → Onboarding → Tabs; applies the theme environment and drives the 1s tick.
struct RootView: View {
    @Environment(AppStore.self) private var store
    @Environment(AppRouter.self) private var router
    @Environment(SyncEngine.self) private var sync
    @Environment(AppEnvironment.self) private var appEnv
    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.colorScheme) private var systemColorScheme
    /// 订阅动态字体：系统字号变化时整棵树重新求值，Typo 才会拿到新的缩放值。
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    var body: some View {
        // `--theme` 调试开关优先；否则按「主题与动效」里的模式 + 强调色解析。
        let theme = LaunchOptions.current.theme.map(Theme.named)
            ?? resolveTheme(mode: store.preferences.themeMode,
                            systemIsDark: systemColorScheme == .dark,
                            accent: store.preferences.accent)
        Group {
            switch router.phase {
            case .splash: SplashView()
            case .onboarding: OnboardingView()
            case .main: MainShellView()
            }
        }
        .environment(\.theme, theme)
        .id(dynamicTypeSize)
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
        case .devices: DevicesView()
        case .account: AccountView()
        case .privacy: PrivacyView()
        case .homeCustomization: HomeCustomizationView()
        case .notifications: NotificationPreferencesView()
        case .feedback: FeedbackView()
        }
    }
}
