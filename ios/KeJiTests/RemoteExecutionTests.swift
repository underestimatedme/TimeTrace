import XCTest
@testable import KeJi

final class RemoteExecutionTests: XCTestCase {
    func testRunnerInventoryDecodesSnakeCaseContract() throws {
        let data = Data(#"{"runner":{"id":"r1","name":"Joey Mac","platform":"darwin","client_version":"0.4","status":"online","created_at":"2026-09-12T10:00:00Z","updated_at":"2026-09-12T10:00:00Z"},"workspaces":[{"id":"ws1","name":"TimeTrace","default_branch":"main","enabled":true,"updated_at":"2026-09-12T10:00:00Z"}],"tools":[{"id":"codex-default","provider":"codex","version":"1","status":"available","updated_at":"2026-09-12T10:00:00Z"}]}"#.utf8)
        let inventory = try JSONCoding.decoder.decode(RunnerInventory.self, from: data)
        XCTAssertEqual(inventory.runner.name, "Joey Mac")
        XCTAssertEqual(inventory.workspaces.first?.defaultBranch, "main")
        XCTAssertEqual(inventory.tools.first?.provider, .codex)
    }

    func testRemoteJobDoesNotRequirePromptInUserResponse() throws {
        let data = Data(#"{"id":"j1","task_id":"t1","runner_id":"r1","workspace_id":"ws1","tool_profile_id":"codex-default","status":"awaiting_review","revision":3,"result_summary":"tests passed","created_at":"2026-09-12T10:00:00Z","updated_at":"2026-09-12T10:01:00Z"}"#.utf8)
        let job = try JSONCoding.decoder.decode(RemoteJob.self, from: data)
        XCTAssertEqual(job.status, .awaitingReview)
        XCTAssertEqual(job.resultSummary, "tests passed")
        XCTAssertNil(job.prompt)
    }
}
