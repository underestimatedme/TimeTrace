import XCTest
@testable import KeJi

final class TimelineProjectionTests: XCTestCase {
    func testHumanAndAIStaySeparate() {
        let start = Date(timeIntervalSince1970: 0)
        let records = [TrackInterval(start: start, end: start.addingTimeInterval(600), track: .human),
                       TrackInterval(start: start, end: start.addingTimeInterval(900), track: .ai)]
        XCTAssertEqual(activeSeconds(records, track: .human), 600)
        XCTAssertEqual(activeSeconds(records, track: .ai), 900)
    }

    func testAIActivityAccumulatesAcrossMachines() {
        let start = Date(timeIntervalSince1970: 0)
        // Two machines active over the same wall-clock window: AI active time
        // accumulates (shown as 累计活跃), it is not a union.
        let records = [TrackInterval(start: start, end: start.addingTimeInterval(300), track: .ai),
                       TrackInterval(start: start, end: start.addingTimeInterval(300), track: .ai)]
        XCTAssertEqual(activeSeconds(records, track: .ai), 600)
    }

    func testHumanOverlapIsUnionNotDoubleCounted() {
        let start = Date(timeIntervalSince1970: 0)
        // Overlapping human records (a data anomaly) must not double count.
        let records = [TrackInterval(start: start, end: start.addingTimeInterval(600), track: .human),
                       TrackInterval(start: start.addingTimeInterval(300), end: start.addingTimeInterval(900), track: .human)]
        XCTAssertEqual(unionSeconds(records, track: .human), 900)
        XCTAssertTrue(hasOverlap(records, track: .human))
    }

    func testNegativeAndDedup() {
        let start = Date(timeIntervalSince1970: 0)
        let records = [
            TrackInterval(id: "e1", start: start.addingTimeInterval(100), end: start, track: .ai), // negative -> 0
            TrackInterval(id: "e2", start: start, end: start.addingTimeInterval(120), track: .ai),
            TrackInterval(id: "e2", start: start, end: start.addingTimeInterval(120), track: .ai), // duplicate id
        ]
        XCTAssertEqual(dedupedByID(records).count, 2)
        XCTAssertEqual(activeSeconds(dedupedByID(records), track: .ai), 120)
    }
    private func sess(_ id: String, task: String, _ type: TimeSessionType, minutesAgo: Int) -> TimeSession {
        let start = Date().addingTimeInterval(TimeInterval(-60 * minutesAgo))
        return TimeSession(id: id, taskId: task, type: type, executor: "x", startedAt: start,
                           endedAt: start.addingTimeInterval(600), durationSeconds: 600,
                           source: .timer, confidence: .exact, note: nil, updatedAt: start)
    }

    private func tsk(_ id: String, project: String) -> TaskItem {
        TaskItem(id: id, projectId: project, goalId: nil, title: id, description: "", executorType: .ai,
                 aiProvider: nil, collaborationMode: nil, status: .planned, priority: .medium,
                 estimatedMinutes: 0, dueDate: nil, scheduledStart: nil, scheduledEnd: nil,
                 createdAt: Date(), completedAt: nil, resultSummary: nil, updatedAt: Date())
    }

    /// 时间线按「我 / AI / 等待」分轨：等待是第三类，不算进任何一方的工作时间。
    func testLanesSplitTracksAndKeepWaitingSeparate() {
        let tasks = [tsk("t1", project: "A"), tsk("t2", project: "B")]
        let sessions = [sess("h", task: "t1", .humanFocus, minutesAgo: 50),
                        sess("r", task: "t1", .humanReview, minutesAgo: 40),
                        sess("a", task: "t1", .aiActive, minutesAgo: 30),
                        sess("w", task: "t1", .waitingHuman, minutesAgo: 20),
                        sess("other", task: "t2", .aiActive, minutesAgo: 10)]

        let all = TimelineLanes(sessions: sessions, tasks: tasks, scope: .all)
        XCTAssertEqual(all.human.map(\.id), ["h", "r"])
        XCTAssertEqual(all.ai.map(\.id), ["a", "other"])
        XCTAssertEqual(all.waiting.map(\.id), ["w"])
        XCTAssertFalse(all.isEmpty)

        let projectA = TimelineLanes(sessions: sessions, tasks: tasks, scope: .project("A"))
        XCTAssertEqual(projectA.ai.map(\.id), ["a"], "project filter must drop project B")
        XCTAssertEqual(projectA.humanSeconds, 1200)
        XCTAssertEqual(projectA.aiSeconds, 600)
        XCTAssertEqual(projectA.waitingSeconds, 600)
        XCTAssertEqual(projectA.summaryText, "人工投入 20 分钟 · AI 活跃 10 分钟 · 等待 10 分钟（三者不相加）")

        XCTAssertTrue(TimelineLanes(sessions: [], tasks: tasks, scope: .all).isEmpty)
    }
}
