import XCTest
@testable import KeJi

@MainActor
final class StoreReducerTests: XCTestCase {
    private func makeStore() -> AppStore {
        let store = AppStore()
        store.completeOnboarding(useSample: true)
        store.clearDirty(store.dirty, deleted: store.deleted, settings: true, activeFocus: true, aiTools: true)
        return store
    }

    func testStartAndPauseFocusWithReason() {
        let store = makeStore()
        store.completeFocus() // clear the sample's running focus on t2
        store.startFocus("t7")
        XCTAssertEqual(store.task("t7")?.status, .humanRunning)
        XCTAssertEqual(store.activeFocus?.taskId, "t7")
        let open = store.timeSessions.filter { $0.taskId == "t7" && $0.type == .humanFocus && $0.endedAt == nil }
        XCTAssertEqual(open.count, 1)

        store.pauseFocus(reason: "开会")
        XCTAssertNil(store.activeFocus)
        XCTAssertEqual(store.task("t7")?.status, .paused)
        let closed = store.timeSessions.filter { $0.taskId == "t7" && $0.type == .humanFocus && $0.id != "ts24" }
        XCTAssertEqual(closed.count, 1)
        XCTAssertNotNil(closed.first?.endedAt)
        let interruption = store.timeSessions.filter { $0.taskId == "t7" && $0.type == .interruption }
        XCTAssertEqual(interruption.count, 1)
        XCTAssertEqual(interruption.first?.note, "开会")
        XCTAssertEqual(interruption.first?.durationSeconds, 0)
        XCTAssertTrue(store.dirty[.tasks]?.contains("t7") ?? false)
        XCTAssertTrue(store.activeFocusDirty)
    }

    func testCompleteAIReviewCreatesReviewSession() {
        let store = makeStore()
        store.completeAIReview("t4")
        XCTAssertEqual(store.task("t4")?.status, .completed)
        XCTAssertNotNil(store.task("t4")?.completedAt)
        let review = store.timeSessions.filter { $0.taskId == "t4" && $0.type == .humanReview }
        XCTAssertEqual(review.count, 1)
        XCTAssertEqual(review.first?.durationSeconds, 480)
        XCTAssertEqual(review.first?.confidence, .estimated)
        XCTAssertEqual(review.first?.source, .manual)
        // waiting_human session ts8 is closed
        XCTAssertNotNil(store.timeSessions.first { $0.id == "ts8" }?.endedAt)
    }

    func testTickFinishesAIExecutionAtRightSecond() {
        let store = makeStore()
        store.completeFocus()
        store.startAIExecution("t7")
        guard let execId = store.aiExecutions.first(where: { $0.taskId == "t7" })?.id else { return XCTFail("no execution") }
        XCTAssertEqual(store.task("t7")?.status, .aiRunning)

        for _ in 0..<179 { store.tickAIExecutions() }
        XCTAssertEqual(store.aiExecutions.first { $0.id == execId }?.status, .running)
        XCTAssertEqual(store.aiExecutions.first { $0.id == execId }?.activeSeconds, 179)
        XCTAssertEqual(store.aiExecutions.first { $0.id == execId }?.currentStep, AppStore.aiSteps[5])

        store.tickAIExecutions() // 180 > 120 and % 60 == 0
        let exec = store.aiExecutions.first { $0.id == execId }
        XCTAssertEqual(exec?.status, .completed)
        XCTAssertEqual(exec?.activeSeconds, 180)
        XCTAssertEqual(exec?.resultSummary, "执行完成，等待审核")
        XCTAssertEqual(store.task("t7")?.status, .waitingHuman)
        XCTAssertEqual(store.timeSessions.filter { $0.taskId == "t7" && $0.type == .waitingHuman && $0.endedAt == nil }.count, 1)
        // the ai_active session accrued one second per tick
        XCTAssertEqual(store.timeSessions.first { $0.taskId == "t7" && $0.type == .aiActive }?.durationSeconds, 180)
    }

    func testTickIsNoopWhenNothingRuns() {
        let store = AppStore()
        store.completeOnboarding(useSample: false)
        let before = store.snapshot
        store.tickAIExecutions()
        XCTAssertEqual(store.snapshot, before)
    }

    func testDeleteTaskCascadesAndTombstones() {
        let store = makeStore()
        let sessions = store.timeSessions.filter { $0.taskId == "t3" }.map(\.id)
        let execs = store.aiExecutions.filter { $0.taskId == "t3" }.map(\.id)
        XCTAssertFalse(sessions.isEmpty)
        XCTAssertFalse(execs.isEmpty)

        store.deleteTask("t3")
        XCTAssertNil(store.task("t3"))
        XCTAssertTrue(store.timeSessions.allSatisfy { $0.taskId != "t3" })
        XCTAssertTrue(store.aiExecutions.allSatisfy { $0.taskId != "t3" })
        XCTAssertTrue(store.deleted[.tasks]?.contains("t3") ?? false)
        for id in sessions { XCTAssertTrue(store.deleted[.timeSessions]?.contains(id) ?? false) }
        for id in execs { XCTAssertTrue(store.deleted[.aiExecutions]?.contains(id) ?? false) }
    }

    func testAddTaskAssignsIdAndMarksDirty() {
        let store = makeStore()
        let draft = TaskItem(id: "", projectId: "p1", goalId: nil, title: "新任务", description: "", executorType: .human,
                             aiProvider: nil, collaborationMode: nil, status: .inbox, priority: .medium, estimatedMinutes: 30,
                             dueDate: "2026-09-04", scheduledStart: nil, scheduledEnd: nil, createdAt: .distantPast,
                             completedAt: nil, resultSummary: nil, updatedAt: .distantPast)
        let id = store.addTask(draft)
        XCTAssertEqual(id.count, 32)
        XCTAssertEqual(store.task(id)?.dueDate, "2026-09-04")
        XCTAssertTrue(store.dirty[.tasks]?.contains(id) ?? false)
        store.setTaskStatus(id, .completed)
        XCTAssertNotNil(store.task(id)?.completedAt)
    }

    func testSwitchingFocusClosesPreviousSessionAndRepeatedStartIsIdempotent() {
        let store = makeStore()
        store.startFocus("t7")
        XCTAssertEqual(store.task("t2")?.status, .paused)
        XCTAssertTrue(store.timeSessions.filter { $0.taskId == "t2" && $0.type == .humanFocus }.allSatisfy { $0.endedAt != nil })
        store.startFocus("t7")
        XCTAssertEqual(store.timeSessions.filter { $0.taskId == "t7" && $0.type == .humanFocus && $0.endedAt == nil }.count, 1)
    }

    func testMissingTaskCannotStartFocus() {
        let store = makeStore()
        let before = store.snapshot
        store.startFocus("missing")
        XCTAssertEqual(store.snapshot, before)
    }

    func testPausedAIDoesNotAccrueTimeAndCanResumeSameExecution() throws {
        let store = makeStore()
        store.startAIExecution("t7")
        let id = try XCTUnwrap(store.aiExecutions.last { $0.taskId == "t7" }?.id)
        store.tick()
        store.pauseAIExecution("t7")
        let before = Stats.taskTimeBreakdown(store.timeSessions, taskId: "t7").ai
        store.tick()
        XCTAssertEqual(Stats.taskTimeBreakdown(store.timeSessions, taskId: "t7").ai, before)
        XCTAssertTrue(store.timeSessions.filter { $0.taskId == "t7" && $0.type == .aiActive }.allSatisfy { $0.endedAt != nil })
        store.authorizeAI("t7")
        store.authorizeAI("t7")
        XCTAssertEqual(store.aiExecutions.filter { $0.taskId == "t7" }.count, 1)
        XCTAssertEqual(store.aiExecutions.first { $0.id == id }?.status, .running)
        XCTAssertEqual(store.timeSessions.filter { $0.taskId == "t7" && $0.type == .aiActive && $0.endedAt == nil }.count, 1)
    }

    func testAICompletionClosesActiveTimeAndWaitingContinuesWithoutOtherWork() {
        let store = makeStore()
        store.completeFocus()
        store.cancelAIExecution("t3")
        store.startAIExecution("t7")
        for _ in 0..<180 { store.tick() }
        XCTAssertTrue(store.timeSessions.filter { $0.taskId == "t7" && $0.type == .aiActive }.allSatisfy { $0.endedAt != nil })
        let before = store.timeSessions.first { $0.taskId == "t7" && $0.type == .waitingHuman }!.durationSeconds
        store.tick()
        XCTAssertEqual(store.timeSessions.first { $0.taskId == "t7" && $0.type == .waitingHuman }?.durationSeconds, before + 1)
        XCTAssertEqual(Stats.taskTimeBreakdown(store.timeSessions, taskId: "t7").ai, 180)
    }

    func testReviewIsIdempotentAndCompletedExecutionCannotBeResumed() {
        let store = makeStore()
        store.completeAIReview("t4")
        store.completeAIReview("t4")
        XCTAssertEqual(store.timeSessions.filter { $0.taskId == "t4" && $0.type == .humanReview }.count, 1)
        store.authorizeAI("t4")
        XCTAssertEqual(store.task("t4")?.status, .completed)
    }

    func testCompletingFromTaskMenuStopsAllTiming() {
        let store = makeStore()
        store.setTaskStatus("t2", .completed)
        XCTAssertNil(store.activeFocus)
        XCTAssertTrue(store.timeSessions.filter { $0.taskId == "t2" }.allSatisfy { $0.endedAt != nil })
        store.setTaskStatus("t3", .completed)
        XCTAssertTrue(store.aiExecutions.filter { $0.taskId == "t3" }.allSatisfy { $0.status != .running })
        XCTAssertTrue(store.timeSessions.filter { $0.taskId == "t3" }.allSatisfy { $0.endedAt != nil })
    }
}
