import XCTest
@testable import KeJi

final class PlanModelTests: XCTestCase {
    func testDefaultIDStable() {
        XCTAssertEqual(defaultPlanID(taskID: "t1"), defaultPlanID(taskID: "t1"))
        XCTAssertNotEqual(defaultPlanID(taskID: "t1"), defaultPlanID(taskID: "t2"))
        XCTAssertEqual(defaultPlanID(taskID: "t1").count, 32)
    }

    /// Pins agreement with Valley's Go implementation: this exact id was produced
    /// by the server for task "t1" in the cross-stack live run.
    func testDefaultIDMatchesServer() {
        XCTAssertEqual(defaultPlanID(taskID: "t1"), "0ddd6b563e82a91c9517bcf180806b50")
    }

    func testUnknownPlanStateDecodesToUnknown() throws {
        let json = Data(#"{"id":"p","task_id":"t","status":"time_travel"}"#.utf8)
        let plan = try JSONCoding.decoder.decode(PlanItem.self, from: json)
        XCTAssertEqual(plan.status, .unknown)
        XCTAssertEqual(plan.revision, 1)          // defaulted when absent
        XCTAssertEqual(plan.executionPolicy, .balanced)
    }

    func testKnownPlanStateDecodes() throws {
        let json = Data(#"{"id":"p","task_id":"t","status":"waiting_quota"}"#.utf8)
        let plan = try JSONCoding.decoder.decode(PlanItem.self, from: json)
        XCTAssertEqual(plan.status, .waitingQuota)
    }

    func testCanDispatchGatesOnAcceptedDependencies() {
        func mk(_ id: String, _ status: PlanState, deps: [String] = []) -> PlanItem {
            PlanItem(id: id, taskId: "t", revision: 1, title: id, priority: 2, status: status,
                     criteria: [], dependsOn: deps, estimatedHumanMinutes: 0, estimatedAiMinutes: 0,
                     workWeight: 1, risk: 2, executionPolicy: .balanced, createdAt: Date(), updatedAt: Date())
        }
        let a = mk("a", .ready)
        let b = mk("b", .ready)
        let c = mk("c", .ready, deps: ["a", "b"])
        // Dependencies not yet accepted -> not dispatchable.
        XCTAssertFalse(canDispatchPlan(c, allPlans: [a, b, c]))
        // Both accepted -> dispatchable.
        let a2 = mk("a", .accepted), b2 = mk("b", .accepted)
        XCTAssertTrue(canDispatchPlan(c, allPlans: [a2, b2, c]))
        // One still pending -> not dispatchable.
        XCTAssertFalse(canDispatchPlan(c, allPlans: [a2, b, c]))
        // A plan with no deps is dispatchable from ready, but not once running.
        XCTAssertTrue(canDispatchPlan(a, allPlans: [a]))
        XCTAssertFalse(canDispatchPlan(mk("a", .running), allPlans: []))
    }
}
