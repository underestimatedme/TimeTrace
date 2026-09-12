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

    func dispatch(task: TaskItem, runner: RunnerInventory, workspace: RunnerWorkspace,
                  tool: RunnerTool) async throws -> RemoteJob {
        let request = RemoteJobRequest(
            taskId: task.id, runnerId: runner.runner.id, workspaceId: workspace.id,
            toolProfileId: tool.id, prompt: task.description.isEmpty ? task.title : task.description,
            idempotencyKey: "ios-\(task.id)-\(runner.runner.id)-\(workspace.id)-\(tool.id)")
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
}
