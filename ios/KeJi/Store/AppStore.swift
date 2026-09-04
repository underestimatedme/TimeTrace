import Foundation
import Observation

/// Port of design/src/store/useStore.ts (zustand) as an observable, main-actor store.
/// Local state is the single source of truth; every mutation marks touched entities dirty
/// so `SyncEngine` can push them (spec §2).
@Observable @MainActor
final class AppStore {
    static let aiSteps = ["读取项目结构", "分析数据模型", "生成代码", "运行测试", "修复错误", "优化输出", "写入文件"]

    var projects: [Project] = []
    var goals: [Goal] = []
    var tasks: [TaskItem] = []
    var timeSessions: [TimeSession] = []
    var aiExecutions: [AIExecution] = []
    /// Daily stats shipped with the sample data; empty when the user starts from scratch.
    var sampleDailyStats: [DailyStats] = []
    var experiments: [EfficiencyExperiment] = []
    var settings: UserSettings = .defaults()
    var aiTools: [AIToolConnection] = AIToolConnection.defaults
    var activeFocus: ActiveFocus?
    var hasOnboarded = false
    var useSampleData = false

    /// Advances once per second via `tick()`; views read it to re-render live durations.
    var now = Date()

    // MARK: Sync bookkeeping
    private(set) var dirty: [SyncEntity: Set<String>] = [:]
    private(set) var deleted: [SyncEntity: Set<String>] = [:]
    private(set) var settingsDirty = false
    private(set) var activeFocusDirty = false
    private(set) var aiToolsDirty = false

    /// Called after every state mutation (persistence hook).
    @ObservationIgnored var onChange: (() -> Void)?
    /// Called whenever something becomes dirty (sync hook).
    @ObservationIgnored var onDirty: (() -> Void)?

    init() {}

    // MARK: - Derived

    /// Prototype takes dailyStats from mock data; otherwise compute the last 7 days on the fly.
    var dailyStats: [DailyStats] {
        if useSampleData && !sampleDailyStats.isEmpty { return sampleDailyStats }
        return Stats.dailyStats(sessions: timeSessions, tasks: tasks, days: 7, now: now)
    }

    var hasPendingSync: Bool {
        dirty.values.contains { !$0.isEmpty } || deleted.values.contains { !$0.isEmpty }
            || settingsDirty || activeFocusDirty || aiToolsDirty
    }

    func project(_ id: String) -> Project? { projects.first { $0.id == id } }
    func goal(_ id: String) -> Goal? { goals.first { $0.id == id } }
    func task(_ id: String) -> TaskItem? { tasks.first { $0.id == id } }

    func runningHumanTask() -> TaskItem? {
        guard let focus = activeFocus else { return nil }
        return task(focus.taskId)
    }

    func runningAITasks() -> [TaskItem] { tasks.filter { $0.status == .aiRunning } }
    func waitingHumanTasks() -> [TaskItem] { tasks.filter { $0.status == .waitingHuman } }

    func focusElapsedSeconds(at date: Date? = nil) -> Int {
        guard let focus = activeFocus else { return 0 }
        return secondsSince(focus.startedAt, at: date ?? now) + focus.accumulatedSeconds
    }

    // MARK: - Helpers

    static func generateId() -> String {
        UUID().uuidString.replacingOccurrences(of: "-", with: "").lowercased()
    }

    func secondsSince(_ date: Date, at reference: Date? = nil) -> Int {
        max(0, Int((reference ?? Date()).timeIntervalSince(date)))
    }

    func timeLabel(_ date: Date) -> String { Format.time(date) }

    func markDirty(_ entity: SyncEntity, _ id: String) {
        dirty[entity, default: []].insert(id)
        deleted[entity]?.remove(id)
        onDirty?()
    }

    func markDeleted(_ entity: SyncEntity, _ id: String) {
        dirty[entity]?.remove(id)
        deleted[entity, default: []].insert(id)
        onDirty?()
    }

    func markSettingsDirty() { settingsDirty = true; onDirty?() }
    func markActiveFocusDirty() { activeFocusDirty = true; onDirty?() }
    func markAIToolsDirty() { aiToolsDirty = true; onDirty?() }

    /// Finish a mutation: notify persistence.
    func commit() { onChange?() }

    // MARK: - Onboarding / reset (useStore.ts)

    func completeOnboarding(useSample: Bool) {
        hasOnboarded = true
        replaceAll(with: useSample ? SampleData.createSampleData() : SampleData.createEmptyData(), useSample: useSample)
        commit()
    }

    func resetToSample() {
        hasOnboarded = true
        replaceAll(with: SampleData.createSampleData(), useSample: true)
        commit()
    }

    /// Fresh users have no projects; TaskCreate needs one to attach tasks to.
    @discardableResult
    func ensureDefaultProject() -> Project {
        if let first = projects.first { return first }
        let at = Date()
        let project = Project(id: AppStore.generateId(), name: "我的任务", description: "默认项目", icon: "📌",
                              color: "#d4845a", status: .active, createdAt: at, updatedAt: at)
        projects.append(project)
        markDirty(.projects, project.id)
        commit()
        return project
    }

    func clearAll() {
        replaceAll(with: SampleData.createEmptyData(), useSample: false)
        hasOnboarded = false
        commit()
    }

    /// Replaces local state; old entities are tombstoned and new ones marked dirty so the
    /// server converges to the same picture.
    private func replaceAll(with data: SampleData.Bundle, useSample: Bool) {
        for p in projects { markDeleted(.projects, p.id) }
        for g in goals { markDeleted(.goals, g.id) }
        for t in tasks { markDeleted(.tasks, t.id) }
        for s in timeSessions { markDeleted(.timeSessions, s.id) }
        for e in aiExecutions { markDeleted(.aiExecutions, e.id) }
        for e in experiments { markDeleted(.experiments, e.id) }

        projects = data.state.projects
        goals = data.state.goals
        tasks = data.state.tasks
        timeSessions = data.state.timeSessions
        aiExecutions = data.state.aiExecutions
        experiments = data.state.experiments
        settings = data.state.settings
        aiTools = data.state.aiTools
        activeFocus = data.state.activeFocus
        sampleDailyStats = data.dailyStats
        useSampleData = useSample

        for p in projects { markDirty(.projects, p.id) }
        for g in goals { markDirty(.goals, g.id) }
        for t in tasks { markDirty(.tasks, t.id) }
        for s in timeSessions { markDirty(.timeSessions, s.id) }
        for e in aiExecutions { markDirty(.aiExecutions, e.id) }
        for e in experiments { markDirty(.experiments, e.id) }
        markSettingsDirty()
        markActiveFocusDirty()
        markAIToolsDirty()
    }

    // MARK: - Snapshot in/out (sync + persistence)

    var snapshot: StateSnapshot {
        StateSnapshot(projects: projects, goals: goals, tasks: tasks, timeSessions: timeSessions,
                      aiExecutions: aiExecutions, experiments: experiments, settings: settings,
                      aiTools: aiTools, activeFocus: activeFocus)
    }

    /// Replace local state with a server snapshot, keeping entities that are still dirty or
    /// deleted locally (they are in flight and will win on the next push).
    func applySnapshot(_ snapshot: StateSnapshot) {
        projects = merge(local: projects, remote: snapshot.projects, entity: .projects)
        goals = merge(local: goals, remote: snapshot.goals, entity: .goals)
        tasks = merge(local: tasks, remote: snapshot.tasks, entity: .tasks)
        timeSessions = merge(local: timeSessions, remote: snapshot.timeSessions, entity: .timeSessions)
        aiExecutions = merge(local: aiExecutions, remote: snapshot.aiExecutions, entity: .aiExecutions)
        experiments = merge(local: experiments, remote: snapshot.experiments, entity: .experiments)
        if !settingsDirty { settings = snapshot.settings }
        if !aiToolsDirty { aiTools = snapshot.aiTools }
        if !activeFocusDirty { activeFocus = snapshot.activeFocus }
        commit()
    }

    private func merge<T: Identifiable>(local: [T], remote: [T], entity: SyncEntity) -> [T] where T.ID == String {
        let dirtyIds = dirty[entity] ?? []
        let deletedIds = deleted[entity] ?? []
        var result = remote.filter { !dirtyIds.contains($0.id) && !deletedIds.contains($0.id) }
        result.append(contentsOf: local.filter { dirtyIds.contains($0.id) })
        return result
    }

    /// Clears the given ids after a successful push (only those that were actually sent).
    func clearDirty(_ pushed: [SyncEntity: Set<String>], deleted pushedDeleted: [SyncEntity: Set<String>],
                    settings: Bool, activeFocus: Bool, aiTools: Bool) {
        for (entity, ids) in pushed { dirty[entity]?.subtract(ids) }
        for (entity, ids) in pushedDeleted { deleted[entity]?.subtract(ids) }
        if settings { settingsDirty = false }
        if activeFocus { activeFocusDirty = false }
        if aiTools { aiToolsDirty = false }
        commit()
    }

    // MARK: - Persistence bridge

    func load(_ persisted: PersistedState) {
        projects = persisted.state.projects
        goals = persisted.state.goals
        tasks = persisted.state.tasks
        timeSessions = persisted.state.timeSessions
        aiExecutions = persisted.state.aiExecutions
        experiments = persisted.state.experiments
        settings = persisted.state.settings
        aiTools = persisted.state.aiTools
        activeFocus = persisted.state.activeFocus
        sampleDailyStats = persisted.sampleDailyStats
        hasOnboarded = persisted.hasOnboarded
        useSampleData = persisted.useSampleData
        dirty = persisted.dirty
        deleted = persisted.deleted
        settingsDirty = persisted.settingsDirty
        activeFocusDirty = persisted.activeFocusDirty
        aiToolsDirty = persisted.aiToolsDirty
    }

    var persisted: PersistedState {
        PersistedState(state: snapshot, sampleDailyStats: sampleDailyStats, hasOnboarded: hasOnboarded,
                       useSampleData: useSampleData, dirty: dirty, deleted: deleted, settingsDirty: settingsDirty,
                       activeFocusDirty: activeFocusDirty, aiToolsDirty: aiToolsDirty)
    }
}

/// What `StateStore` writes to disk.
struct PersistedState: Codable {
    var state: StateSnapshot
    var sampleDailyStats: [DailyStats] = []
    var hasOnboarded = false
    var useSampleData = false
    var dirty: [SyncEntity: Set<String>] = [:]
    var deleted: [SyncEntity: Set<String>] = [:]
    var settingsDirty = false
    var activeFocusDirty = false
    var aiToolsDirty = false
}
