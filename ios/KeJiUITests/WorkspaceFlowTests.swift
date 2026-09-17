import XCTest

/// Run TestSupport/workspace_server.py on the host before the HTTP scenarios.
/// Offline fixtures never unlock dependencies; HTTP scenarios use the real client.
final class WorkspaceFlowTests: XCTestCase {
    private var app: XCUIApplication!

    override func setUpWithError() throws {
        continueAfterFailure = false
        app = XCUIApplication()
        app.launchArguments = ["--workspace-fixture", "--screen", "projects"]
        app.launch()
    }

    private func tap(_ id: String, timeout: TimeInterval = 5, file: StaticString = #filePath, line: UInt = #line) {
        let el = app.buttons[id].firstMatch
        XCTAssertTrue(el.waitForExistence(timeout: timeout), "missing \(id)", file: file, line: line)
        el.tap()
    }

    func testReportsOpenFromTodayShowsSeparatedTimes() {
        app.terminate()
        app.launchArguments = ["--ui-testing", "--offline", "--sample-data", "--screen", "today"]
        app.launch()
        tap("reports.open")
        XCTAssertTrue(app.staticTexts["报告"].waitForExistence(timeout: 5))
        // The report leads with delivery (accepted Plans), then the time breakdown below the ChangeLog.
        XCTAssertTrue(app.staticTexts["个 Plan 已验收"].waitForExistence(timeout: 3))
        // Human and AI time are shown as separate sections (never summed).
        let human = app.staticTexts["人工投入"]
        for _ in 0..<8 where !human.isHittable { app.swipeUp() }
        XCTAssertTrue(human.waitForExistence(timeout: 3))
        XCTAssertTrue(app.staticTexts["AI 活跃（累计）"].exists)
    }

    func testReportsUseServerFactsRevisionAndCoverageGate() {
        app.terminate()
        app.launchArguments = ["--workspace-fixture", "--online-ui-testing", "--api-base-url",
                               "http://127.0.0.1:18768/reports-\(UUID().uuidString)", "--screen", "today"]
        app.launchEnvironment["KEJI_OFFLINE"] = "0"
        app.launch()
        tap("reports.open")
        XCTAssertTrue(app.staticTexts["时区 Asia/Dubai · 修订 7 · 私有草稿"].waitForExistence(timeout: 8))
        XCTAssertTrue(app.staticTexts["10 分钟"].exists)
        XCTAssertTrue(app.staticTexts["20 分钟"].exists)
        XCTAssertTrue(app.staticTexts["无记录"].exists)
        XCTAssertFalse(app.staticTexts["95"].exists)
        tap("reports.generate")
        XCTAssertTrue(app.staticTexts["时区 Asia/Dubai · 修订 8 · 私有草稿"].waitForExistence(timeout: 5))
        capture("report-server-facts")
    }

    func testOfflineCannotAcceptDependenciesOrUnlockDispatch() {
        // Drill down to plan.03.
        tap("project.keji")
        tap("task.quota")
        tap("plan.03")

        let dispatch = app.buttons["plan.dispatch"].firstMatch
        XCTAssertTrue(dispatch.waitForExistence(timeout: 5))
        XCTAssertFalse(dispatch.isEnabled, "dispatch must be disabled while dependencies are unaccepted")

        // Offline fixtures must never turn a local tap into accepted delivery.
        for dep in ["plan.01", "plan.02"] {
            tap("subpage.back")            // back to task.quota
            tap(dep)
            XCTAssertFalse(app.buttons["plan.accept"].exists)
        }

        // Return to plan.03; dispatch is now enabled.
        tap("subpage.back")
        tap("plan.03")
        let dispatch2 = app.buttons["plan.dispatch"].firstMatch
        XCTAssertTrue(dispatch2.waitForExistence(timeout: 5))
        XCTAssertFalse(dispatch2.isEnabled, "offline work must not unlock dependencies")
    }

    func testCreateDispatchWaitAndAcceptThroughHTTP() {
        createAndDispatch(scenario: "happy")
        XCTAssertTrue(app.staticTexts["待验收"].waitForExistence(timeout: 15))
        tap("plan.accept")
        tap("plan.evidence.job-ui")
        tap("plan.accept.confirm")
        XCTAssertTrue(app.staticTexts["已验收"].waitForExistence(timeout: 10))
        capture("plan-accepted")
    }

    func testConflictRequiresFreshReviewInsteadOfAutomaticRetry() {
        createAndDispatch(scenario: "conflict")
        XCTAssertTrue(app.staticTexts["待验收"].waitForExistence(timeout: 15))
        tap("plan.accept")
        tap("plan.evidence.job-ui")
        tap("plan.accept.confirm")
        XCTAssertTrue(app.staticTexts["plan.review.stale"].waitForExistence(timeout: 10))
        XCTAssertFalse(app.buttons["plan.accept.confirm"].isEnabled)
        XCTAssertFalse(app.staticTexts["已验收"].exists)
        capture("plan-conflict-review")
        tap("关闭")
        XCTAssertTrue(app.staticTexts["plan.error"].waitForExistence(timeout: 5))
        tap("plan.accept")
        XCTAssertTrue(app.buttons["plan.criterion.0"].waitForExistence(timeout: 5))
        XCTAssertFalse(app.buttons["plan.accept.confirm"].isEnabled)
    }

    func testCancelledPlanCannotBeAccepted() {
        createAndDispatch(scenario: "cancel")
        tap("plan.cancel")
        XCTAssertTrue(app.staticTexts["已取消"].waitForExistence(timeout: 10))
        XCTAssertFalse(app.buttons["plan.accept"].exists)
        XCTAssertFalse(app.buttons["plan.dispatch"].isEnabled)
        capture("plan-cancelled")
    }

    func testHumanPlanExplainsUnsupportedWorkflowWithoutOfferingAIRunner() {
        createAndDispatch(scenario: "human", humanOnly: true)
        XCTAssertFalse(app.buttons["plan.dispatch"].isEnabled)
        XCTAssertTrue(app.staticTexts["plan.executor.unavailable"].exists)
        XCTAssertFalse(app.buttons["plan.accept"].exists)
        capture("human-plan-blocked")
    }

    func testSaveAndStartAIExecutesAfterTaskSync() {
        createAndDispatch(scenario: "save-start", saveAndStart: true)
        XCTAssertTrue(app.staticTexts["执行中"].waitForExistence(timeout: 10))
    }

    private func createAndDispatch(scenario: String, humanOnly: Bool = false, saveAndStart: Bool = false) {
        app.terminate()
        app.launchArguments = ["--workspace-fixture", "--online-ui-testing", "--api-base-url",
                               "http://127.0.0.1:18768/\(scenario)-\(UUID().uuidString)", "--screen", "tasks/new"]
        app.launchEnvironment["KEJI_OFFLINE"] = "0"
        app.launch()
        let title = app.textFields["输入任务名称"]
        XCTAssertTrue(title.waitForExistence(timeout: 5))
        title.tap()
        title.typeText("F08 网络任务\n")
        if !humanOnly {
            tap("AI 来做")
            tap("Codex")
        }
        let saveTitle = saveAndStart ? "保存并开始" : "保存任务"
        for _ in 0..<5 where !app.buttons[saveTitle].isHittable { app.swipeUp() }
        tap(saveTitle)
        if saveAndStart { return }
        tap("project.keji")
        let task = app.buttons.matching(NSPredicate(format: "label CONTAINS %@", "F08 网络任务")).firstMatch
        XCTAssertTrue(task.waitForExistence(timeout: 10))
        task.tap()
        let plan = app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH %@", "plan.")).firstMatch
        XCTAssertTrue(plan.waitForExistence(timeout: 10), "created task must immediately expose its Plan")
        plan.tap()
        if humanOnly { return }
        tap("plan.dispatch", timeout: 10)
        tap("plan.dispatch.confirm")
        XCTAssertTrue(app.staticTexts["执行中"].waitForExistence(timeout: 10))
    }

    private func capture(_ name: String) {
        let attachment = XCTAttachment(screenshot: app.screenshot())
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }
}
