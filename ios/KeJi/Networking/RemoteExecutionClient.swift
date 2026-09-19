import Foundation
import Observation

@Observable @MainActor
final class RemoteExecutionClient {
    private(set) var runners: [RunnerInventory] = []
    private(set) var jobsByTask: [String: RemoteJob] = [:]
    private(set) var isLoading = false
    private(set) var errorMessage: String?
    let client: APIClient

    init(client: APIClient) { self.client = client }

    func loadRunners() async {
        isLoading = true
        defer { isLoading = false }
        do {
            runners = try await client.send(Endpoint.runners, as: [RunnerInventory].self)
            errorMessage = nil
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func approve(code: String) async throws {
        _ = try await client.send(Endpoint.approveRunner(code: code.uppercased()), as: DeviceApprovalResponse.self)
        await loadRunners()
    }

    func inspect(code: String) async throws -> DeviceAuthorizationInspection {
        try await client.send(Endpoint.inspectRunner(code: code.uppercased()), as: DeviceAuthorizationInspection.self)
    }

    func dispatch(task: TaskItem, runner: RunnerInventory, workspace: RunnerWorkspace,
                  tool: RunnerTool) async throws -> RemoteJob {
        let request = RemoteJobRequest(
            taskId: task.id, runnerId: runner.runner.id, workspaceId: workspace.id,
            toolProfileId: tool.id, prompt: task.description.isEmpty ? task.title : task.description,
            idempotencyKey: "ios-\(task.id)-\(runner.runner.id)-\(workspace.id)-\(tool.id)",
            expectedTaskRevision: Int64(task.updatedAt.timeIntervalSince1970 * 1000))
        let job = try await client.send(Endpoint.createRemoteJob(request), as: RemoteJob.self)
        jobsByTask[task.id] = job
        return job
    }

    @discardableResult
    func refresh(taskId: String) async throws -> RemoteJob? {
        guard let existing = jobsByTask[taskId] else { return nil }
        let job = try await client.send(Endpoint.remoteJob(id: existing.id), as: RemoteJob.self)
        jobsByTask[taskId] = job
        return job
    }

    func refresh(jobID: String) async throws -> RemoteJob {
        let job = try await client.send(Endpoint.remoteJob(id: jobID), as: RemoteJob.self)
        jobsByTask[job.taskId] = job
        return job
    }

    func cancel(jobID: String) async throws {
        guard let job = jobsByTask.values.first(where: { $0.id == jobID }) else { throw APIError.decoding(NSError(domain: "RemoteJob", code: 1)) }
        _ = try await client.send(Endpoint.remoteJobCommand(id: jobID, action: "cancel", expectedRevision: job.revision,
                                                             idempotencyKey: "cancel-\(job.id)-\(job.revision)"), as: RemoteCommandResponse.self)
    }

}
