import Foundation

extension AppStore {
    func plan(_ id: String) -> PlanItem? { plans.first { $0.id == id } }

    /// Plans for a task, ordered by priority then creation (deterministic).
    func plans(forTask taskId: String) -> [PlanItem] {
        plans.filter { $0.taskId == taskId }.sorted { ($0.priority, $0.createdAt) < ($1.priority, $1.createdAt) }
    }

    /// Optimistic local accept, used for offline drafts and UI fixtures. In
    /// production, acceptance is confirmed by the server via PlanClient (I3);
    /// only a server-returned `accepted` advances delivery goals.
    func markPlanAccepted(_ id: String) {
        guard let idx = plans.firstIndex(where: { $0.id == id }) else { return }
        plans[idx].status = .accepted
        plans[idx].revision += 1
        onChange?()
    }
}
