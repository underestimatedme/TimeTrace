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
}
