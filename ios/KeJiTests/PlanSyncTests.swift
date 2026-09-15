import XCTest
@testable import KeJi

final class PlanSyncTests: XCTestCase {
    @MainActor
    func testNewTaskImmediatelyHasOnlyAnUnacceptedDraftPlan() {
        let store = AppStore()
        let task = SampleData.createWorkspaceFixture().state.tasks[0]
        let id = store.addTask(task)
        XCTAssertEqual(store.plans(forTask: id).count, 1)
        XCTAssertEqual(store.plans(forTask: id).first?.status, .draft)
    }

    @MainActor
    func testRunningAndCancelledPlansCannotBeLocallyAccepted() async {
        for status in [PlanState.running, .cancelled] {
            let store = AppStore()
            var plan = SampleData.createWorkspaceFixture().state.plans[0]
            plan.status = status
            store.plans = [plan]
            let accepted = await store.acceptPlan(plan.id, expectedRevision: plan.revision, evidenceIDs: [], criteria: [])
            XCTAssertFalse(accepted)
            XCTAssertEqual(store.plan(plan.id)?.status, status)
        }
    }
    private let legacyJSON = Data(#"""
    {"projects":[{"id":"p1","name":"P","description":"","icon":"x","color":"#fff","status":"active","created_at":"2026-09-14T10:00:00Z","updated_at":"2026-09-14T10:00:00Z"}],
     "tasks":[{"id":"t1","project_id":"p1","goal_id":null,"title":"T","description":"","executor_type":"ai","ai_provider":null,"collaboration_mode":null,"status":"planned","priority":"high","estimated_minutes":30,"due_date":null,"scheduled_start":null,"scheduled_end":null,"created_at":"2026-09-14T10:00:00Z","completed_at":null,"result_summary":null,"updated_at":"2026-09-14T10:00:00Z"}]}
    """#.utf8)

    func testOldSnapshotDecodesWithoutPlans() throws {
        let snap = try JSONCoding.decoder.decode(StateSnapshot.self, from: legacyJSON)
        XCTAssertEqual(snap.schemaVersion, 1)   // absent -> v1
        XCTAssertTrue(snap.plans.isEmpty)
        XCTAssertEqual(snap.tasks.count, 1)
    }

    func testMigrationIsIdempotentAndDeterministic() throws {
        let snap = try JSONCoding.decoder.decode(StateSnapshot.self, from: legacyJSON)
        let once = migrateDefaultPlans(snap)
        XCTAssertEqual(once.schemaVersion, 2)
        XCTAssertEqual(once.plans.count, 1)
        XCTAssertEqual(once.plans[0].id, defaultPlanID(taskID: "t1"))
        XCTAssertEqual(once.plans[0].priority, 1)                 // "high" -> 1
        XCTAssertEqual(once.plans[0].estimatedHumanMinutes, 30)   // inherited from task

        // Running again creates no duplicate; two loads yield the same result.
        let twice = migrateDefaultPlans(once)
        XCTAssertEqual(twice.plans.count, 1)
        XCTAssertEqual(twice.plans, once.plans)
    }

    func testRoundTripEncodeDecodePreservesPlans() throws {
        var snap = try JSONCoding.decoder.decode(StateSnapshot.self, from: legacyJSON)
        // Whole-second timestamp so ISO8601 (millisecond) round-trips exactly.
        snap = migrateDefaultPlans(snap, now: Date(timeIntervalSince1970: 1_789_462_800))
        let data = try JSONCoding.encoder.encode(snap)
        let back = try JSONCoding.decoder.decode(StateSnapshot.self, from: data)
        XCTAssertEqual(back.schemaVersion, 2)
        XCTAssertEqual(back.plans, snap.plans)
    }
}
