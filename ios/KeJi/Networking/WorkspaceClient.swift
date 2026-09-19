import Foundation

/// Reads Plans, account quota, and daily reports from Valley. All values match
/// the workspace API contract; acceptance and dispatch are server-confirmed —
/// the UI never treats a local optimistic state as accepted delivery.
final class WorkspaceClient {
    private let client: APIClient

    init(client: APIClient) { self.client = client }

    func accountQuota() async throws -> AccountQuota {
        try await client.send(.accountQuota, as: AccountQuota.self)
    }

    func submitFeedback(_ draft: FeedbackDraft) async throws -> FeedbackTicket {
        try await client.send(.createFeedback(draft), as: FeedbackTicket.self)
    }

    func resetSignals() async throws -> ResetSignalsResponse {
        try await client.send(.resetSignals, as: ResetSignalsResponse.self)
    }

    func plans(taskID: String) async throws -> [PlanItem] {
        try await client.send(.taskPlans(taskID: taskID), as: [PlanItem].self)
    }

    func createPlan(taskID: String, draft: PlanItem) async throws -> PlanItem {
        try await client.send(.createPlan(taskID: taskID, draft: draft), as: PlanItem.self)
    }

    func runners() async throws -> [RunnerInventory] { try await client.send(.runners, as: [RunnerInventory].self) }

    func dispatch(_ request: RemoteJobRequest) async throws -> RemoteJob {
        try await client.send(.createRemoteJob(request), as: RemoteJob.self)
    }

    func job(id: String) async throws -> RemoteJob {
        try await client.send(.remoteJob(id: id), as: RemoteJob.self)
    }

    func retryPlan(id: String, expectedRevision: Int) async throws -> PlanItem {
        try await client.send(.retryPlan(id: id, expectedRevision: expectedRevision), as: PlanItem.self)
    }

    func acceptPlan(id: String, expectedRevision: Int, evidenceIDs: [String] = [],
                    criteria: [CriterionResultBody] = []) async throws -> PlanItem {
        try await client.send(.acceptPlan(id: id, expectedRevision: expectedRevision,
                                          evidenceIDs: evidenceIDs, criteria: criteria), as: PlanItem.self)
    }

    func updatePlanPolicy(id: String, expectedRevision: Int, policy: PlanExecutionPolicy) async throws -> PlanItem {
        try await client.send(.updatePlanPolicy(id: id, expectedRevision: expectedRevision, policy: policy), as: PlanItem.self)
    }

    func cancelPlan(id: String, expectedRevision: Int) async throws -> PlanItem {
        try await client.send(.cancelPlan(id: id, expectedRevision: expectedRevision), as: PlanItem.self)
    }

    func report(date: String) async throws -> DailyReport {
        try await client.send(.report(date: date), as: DailyReport.self)
    }

    func generateReport(date: String, zone: String) async throws -> DailyReport {
        try await client.send(.generateReport(date: date, zone: zone), as: DailyReport.self)
    }
}
