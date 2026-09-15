import XCTest
@testable import KeJi

final class ReportsScopeTests: XCTestCase {
    private func task(_ id: String, project: String) -> TaskItem {
        TaskItem(id: id, projectId: project, goalId: nil, title: id, description: "", executorType: .ai,
                 aiProvider: nil, collaborationMode: nil, status: .planned, priority: .medium,
                 estimatedMinutes: 0, dueDate: nil, scheduledStart: nil, scheduledEnd: nil,
                 createdAt: Date(), completedAt: nil, resultSummary: nil, updatedAt: Date())
    }
    private func session(_ id: String, task: String) -> TimeSession {
        TimeSession(id: id, taskId: task, type: .humanFocus, executor: "human", startedAt: Date(),
                    endedAt: nil, durationSeconds: 60, source: .timer, confidence: .exact, note: nil, updatedAt: Date())
    }

    func testProjectScopeStaysWithinProject() {
        let tasks = [task("t1", project: "A"), task("t2", project: "B")]
        let sessions = [session("s1", task: "t1"), session("s2", task: "t2"), session("s3", task: "t1")]

        let all = sessionsInScope(.all, tasks: tasks, sessions: sessions)
        XCTAssertEqual(all.count, 3)

        let projectA = sessionsInScope(.project("A"), tasks: tasks, sessions: sessions)
        XCTAssertEqual(Set(projectA.map { $0.id }), ["s1", "s3"])   // no s2 (project B)
    }
}
