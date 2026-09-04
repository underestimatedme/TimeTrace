import XCTest
@testable import KeJi

final class SampleDataTests: XCTestCase {
    func testCounts() {
        let bundle = SampleData.createSampleData()
        XCTAssertEqual(bundle.state.projects.count, 4)
        XCTAssertEqual(bundle.state.goals.count, 5)
        XCTAssertEqual(bundle.state.tasks.count, 20)
        XCTAssertEqual(bundle.state.timeSessions.count, 30)
        XCTAssertEqual(bundle.state.aiExecutions.count, 8)
        XCTAssertEqual(bundle.dailyStats.count, 7)
        XCTAssertEqual(bundle.state.experiments.count, 3)
        XCTAssertEqual(bundle.state.aiTools.count, 4)
        XCTAssertEqual(bundle.state.activeFocus?.taskId, "t2")
        XCTAssertEqual(bundle.state.settings.streakDays, 12)
        XCTAssertEqual(bundle.state.settings.theme, .claude)
    }

    func testRelativeDates() {
        let now = Date()
        let bundle = SampleData.createSampleData(now: now)
        let cal = Calendar.current
        let t1 = bundle.state.tasks[0]
        XCTAssertEqual(t1.dueDate, Format.dayKey(now))
        XCTAssertEqual(cal.component(.hour, from: t1.scheduledStart!), 9)
        XCTAssertTrue(cal.isDate(t1.completedAt!, inSameDayAs: now))
        let focus = bundle.state.activeFocus!
        XCTAssertEqual(now.timeIntervalSince(focus.startedAt), 42 * 60, accuracy: 1)
        XCTAssertEqual(bundle.dailyStats.last?.date, Format.dayKey(now))
        XCTAssertEqual(bundle.dailyStats.first?.date, Format.dayKey(cal.date(byAdding: .day, value: -6, to: now)!))
    }

    func testEmptyData() {
        let bundle = SampleData.createEmptyData()
        XCTAssertTrue(bundle.state.tasks.isEmpty)
        XCTAssertEqual(bundle.state.aiTools.count, 4)
        XCTAssertEqual(bundle.state.settings.streakDays, 0)
        XCTAssertNil(bundle.state.activeFocus)
    }

    func testRoundTripThroughJSON() throws {
        let bundle = SampleData.createSampleData()
        let data = try JSONCoding.encoder.encode(bundle.state)
        let decoded = try JSONCoding.decoder.decode(StateSnapshot.self, from: data)
        XCTAssertEqual(decoded.tasks.count, 20)
        XCTAssertEqual(decoded.tasks.map(\.id), bundle.state.tasks.map(\.id))
        XCTAssertEqual(decoded.timeSessions.map(\.durationSeconds), bundle.state.timeSessions.map(\.durationSeconds))
        XCTAssertEqual(decoded.aiExecutions.map(\.logs.count), bundle.state.aiExecutions.map(\.logs.count))
        // dates survive with millisecond precision
        XCTAssertEqual(decoded.tasks[0].createdAt.timeIntervalSince1970, bundle.state.tasks[0].createdAt.timeIntervalSince1970, accuracy: 0.001)
    }
}
