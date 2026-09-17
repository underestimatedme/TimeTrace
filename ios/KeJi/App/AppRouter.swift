import Foundation
import Observation

/// Confirmed bottom navigation: 今日 · 项目 · 时间线 · AI · 我的. Reports are not
/// a tab — they are reached from Today's top-right (all projects) and from a
/// project's detail (that project's scope).
enum AppTab: String, CaseIterable, Hashable {
    case today, projects, timeline, ai, mine

    var label: String {
        switch self {
        case .today: return "今日"
        case .projects: return "项目"
        case .timeline: return "时间线"
        case .ai: return "AI"
        case .mine: return "我的"
        }
    }

    var symbol: String {
        switch self {
        case .today: return "calendar"
        case .projects: return "folder"
        case .timeline: return "arrow.triangle.branch"
        case .ai: return "sparkles"
        case .mine: return "person"
        }
    }
}

/// Reports keep their scope: from Today's top-right they cover all projects; from
/// a project's detail they stay within that project.
enum ReportScope: Hashable {
    case all
    case project(String)
}

enum Route: Hashable {
    case taskCreate
    case taskDetail(String)
    case plan(String)
    case reports(ReportScope)
    case focus(String)
    case ai(String)
    case projects
    case project(String)
    case goal(String)
    case aiTools
    case appearance
    case account
    case privacy
    case homeCustomization
    case notifications
    case feedback
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
        // Legacy `tasks` deep links map to the project scope's "all tasks".
        case ("tasks", nil): go(.projects)
        case ("tasks", "new"): go(.projects); push(.taskCreate)
        case ("tasks", let id?): go(.projects); push(.taskDetail(id))
        case ("timeline", _): go(.timeline)
        case ("insights", _): go(.today)
        case ("profile", _): go(.mine)
        case ("focus", let id?): go(.today); push(.focus(id))
        case ("ai", nil): go(.ai)
        case ("ai", let id?): go(.today); push(.ai(id))
        case ("projects", nil): go(.projects)
        case ("projects", let id?): go(.projects); push(.project(id))
        case ("goals", let id?): go(.projects); push(.goal(id))
        case ("ai-tools", _): go(.ai)
        // 报告从今日页右上角进入；项目报告限定当前项目，返回时回到项目详情。
        case ("reports", nil): go(.today); push(.reports(.all))
        case ("reports", let id?): go(.projects); push(.project(id)); push(.reports(.project(id)))
        case ("appearance", _): go(.mine); push(.appearance)
        case ("account", _): go(.mine); push(.account)
        default: go(.today)
        }
    }
}
