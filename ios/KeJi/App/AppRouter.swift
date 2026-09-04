import Foundation
import Observation

enum AppTab: String, CaseIterable, Hashable {
    case today, tasks, timeline, insights, profile

    var label: String {
        switch self {
        case .today: return "今日"
        case .tasks: return "任务"
        case .timeline: return "时间流"
        case .insights: return "洞察"
        case .profile: return "我的"
        }
    }

    var symbol: String {
        switch self {
        case .today: return "calendar"
        case .tasks: return "checklist"
        case .timeline: return "arrow.triangle.branch"
        case .insights: return "chart.bar"
        case .profile: return "person"
        }
    }
}

enum Route: Hashable {
    case taskCreate
    case taskDetail(String)
    case focus(String)
    case ai(String)
    case projects
    case project(String)
    case goal(String)
    case aiTools
    case appearance
    case account
}

enum RootPhase { case splash, onboarding, main }

/// Navigation state: root phase, selected tab and the pushed sub-page path.
@Observable @MainActor
final class AppRouter {
    var phase: RootPhase = .splash
    var tab: AppTab = .today
    var path: [Route] = []

    func push(_ route: Route) { path.append(route) }
    func pop() { if !path.isEmpty { path.removeLast() } }
    func popToRoot() { path.removeAll() }

    /// `navigate('/today')` etc.: back to a tab root.
    func go(_ tab: AppTab) {
        path.removeAll()
        self.tab = tab
    }

    /// Parses a `--screen <route>` value.
    func apply(screen: String) {
        let parts = screen.split(separator: "/").map(String.init)
        guard let head = parts.first else { return }
        let arg = parts.count > 1 ? parts[1] : nil
        phase = .main
        switch (head, arg) {
        case ("splash", _): phase = .splash
        case ("onboarding", _): phase = .onboarding
        case ("today", _): go(.today)
        case ("tasks", nil): go(.tasks)
        case ("tasks", "new"): go(.tasks); push(.taskCreate)
        case ("tasks", let id?): go(.tasks); push(.taskDetail(id))
        case ("timeline", _): go(.timeline)
        case ("insights", _): go(.insights)
        case ("profile", _): go(.profile)
        case ("focus", let id?): go(.today); push(.focus(id))
        case ("ai", let id?): go(.today); push(.ai(id))
        case ("projects", nil): go(.profile); push(.projects)
        case ("projects", let id?): go(.profile); push(.projects); push(.project(id))
        case ("goals", let id?): go(.profile); push(.projects); push(.goal(id))
        case ("ai-tools", _): go(.profile); push(.aiTools)
        case ("appearance", _): go(.profile); push(.appearance)
        case ("account", _): go(.profile); push(.account)
        default: go(.today)
        }
    }
}
