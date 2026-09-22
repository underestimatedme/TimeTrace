import XCTest

/// Run TestSupport/workspace_server.py on the host before the HTTP scenarios.
/// Offline fixtures never unlock dependencies; HTTP scenarios use the real client.
final class WorkspaceFlowTests: XCTestCase {
    func testFeedbackDraftSurvivesLeavingPage() {
        app.terminate()
        app.launchArguments = ["--ui-testing", "--offline", "--sample-data", "--screen", "profile"]
        app.launch()
        app.swipeUp()
        app.buttons["反馈"].firstMatch.tap()
        let editor = app.textViews["feedback.text"]
        XCTAssertTrue(editor.waitForExistence(timeout: 5))
        editor.tap()
        editor.typeText("Feedback draft persists")
        let expected = editor.value as? String
        XCTAssertTrue(expected?.contains("Feedback draft persists") == true)
        tap("subpage.back")
        app.swipeUp()
        app.buttons["反馈"].firstMatch.tap()
        XCTAssertEqual(app.textViews["feedback.text"].value as? String, expected)
        XCTAssertTrue(app.staticTexts["feedback.status"].label.contains("仅本机草稿"))
    }

    func testFeedbackHTTPFailureRestartRetryAndConfirmedCleanup() {
        app.terminate()
        app.launchArguments = ["--workspace-fixture", "--online-ui-testing", "--api-base-url",
                               "http://127.0.0.1:18768/feedback-\(UUID().uuidString)", "--screen", "profile"]
        app.launchEnvironment["KEJI_OFFLINE"] = "0"
        app.launch()
        app.swipeUp()
        app.buttons["反馈"].firstMatch.tap()
        let editor = app.textViews["feedback.text"]
        XCTAssertTrue(editor.waitForExistence(timeout: 8))
        editor.tap()
        editor.typeText("My feedback after restart")
        tap("feedback.submit")
        let status = app.staticTexts["feedback.status"]
        let failed = NSPredicate(format: "label CONTAINS %@", "提交未确认")
        expectation(for: failed, evaluatedWith: status)
        waitForExpectations(timeout: 8)
        app.terminate()
        app.launch()
        app.swipeUp()
        app.buttons["反馈"].firstMatch.tap()
        XCTAssertTrue(editor.waitForExistence(timeout: 8))
        XCTAssertEqual(editor.value as? String, "My feedback after restart")
        tap("feedback.submit")
        expectation(for: NSPredicate(format: "label CONTAINS %@", "已提交 · 工单 ticket-f11"), evaluatedWith: status)
        waitForExpectations(timeout: 8)
        tap("subpage.back")
        app.swipeUp()
        app.buttons["反馈"].firstMatch.tap()
        XCTAssertTrue(editor.waitForExistence(timeout: 5))
        XCTAssertEqual(editor.value as? String, "")
        XCTAssertFalse(app.buttons["feedback.submit"].isEnabled)
    }
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
        XCTAssertTrue(app.staticTexts["时区 \(TimeZone.current.identifier) · 修订 7 · 私有草稿"].waitForExistence(timeout: 8))
        XCTAssertTrue(app.staticTexts["10 分钟"].exists)
        XCTAssertTrue(app.staticTexts["20 分钟"].exists)
        XCTAssertTrue(app.staticTexts["无记录"].exists)
        XCTAssertFalse(app.staticTexts["95"].exists)
        tap("reports.generate")
        XCTAssertTrue(app.staticTexts["时区 \(TimeZone.current.identifier) · 修订 8 · 私有草稿"].waitForExistence(timeout: 5))
        capture("report-server-facts")
    }

    func testProjectReportUsesOnlyItsServerFacts() {
        app.terminate()
        app.launchArguments = ["--workspace-fixture", "--online-ui-testing", "--api-base-url",
                               "http://127.0.0.1:18768/reports-project-\(UUID().uuidString)", "--screen", "projects"]
        app.launchEnvironment["KEJI_OFFLINE"] = "0"
        app.launch()
        tap("project.keji")
        tap("reports.open.project")
        XCTAssertTrue(app.staticTexts["时区 \(TimeZone.current.identifier) · 修订 7 · 私有草稿"].waitForExistence(timeout: 8))
        XCTAssertTrue(app.staticTexts["10 分钟"].exists)
        XCTAssertTrue(app.staticTexts["20 分钟"].exists)
        XCTAssertFalse(app.staticTexts["30 分钟"].exists, "other project's AI must be excluded")
        XCTAssertFalse(app.staticTexts["生产力总分 95"].exists)
        capture("report-project-server-facts")
    }

    func testReportRejectsSnapshotFromAnotherTimeZone() {
        app.terminate()
        app.launchArguments = ["--workspace-fixture", "--online-ui-testing", "--api-base-url",
                               "http://127.0.0.1:18768/reports-zone-mismatch-\(UUID().uuidString)", "--screen", "today"]
        app.launchEnvironment["KEJI_OFFLINE"] = "0"
        app.launch()
        tap("reports.open")
        let mismatch = app.staticTexts.matching(NSPredicate(format: "label CONTAINS %@", "报告日期或时区不匹配")).firstMatch
        XCTAssertTrue(mismatch.waitForExistence(timeout: 8))
        XCTAssertFalse(app.staticTexts["20 分钟"].exists)
        XCTAssertFalse(app.staticTexts["时区 America/New_York · 修订 7 · 私有草稿"].exists)
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
        XCTAssertFalse(app.buttons["plan.accept.confirm"].isEnabled)
        tap("plan.evidence.job-ui")
        XCTAssertFalse(app.buttons["plan.accept.confirm"].isEnabled, "evidence alone cannot satisfy criteria")
        tap("plan.criterion.0")
        XCTAssertFalse(app.buttons["plan.accept.confirm"].isEnabled, "each criterion requires explicit selection")
        tap("plan.criterion.1")
        XCTAssertTrue(app.buttons["plan.accept.confirm"].isEnabled)
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
    /// AI 页联网时从 Valley 拉取个人额度与公共重置信号。
    /// fixture 返回 62%，示例数据是 80%：看到 62% 才说明请求真的发了出去。
    func testAIPageLoadsQuotaAndResetSignalsFromServer() {
        app.terminate()
        app.launchArguments = ["--workspace-fixture", "--online-ui-testing", "--api-base-url",
                               "http://127.0.0.1:18768/signals-\(UUID().uuidString)", "--screen", "ai-tools"]
        app.launchEnvironment["KEJI_OFFLINE"] = "0"
        app.launch()
        XCTAssertTrue(app.staticTexts["62%"].waitForExistence(timeout: 8), "额度应当来自服务端，而不是示例数据")
        let source = app.descendants(matching: .any)["reset.source.BetterOPC"].firstMatch
        for _ in 0..<6 where !source.exists { app.swipeUp() }
        XCTAssertTrue(source.waitForExistence(timeout: 5), "应当显示 Valley 返回的信号来源")
        let note = app.staticTexts["reset.note"].firstMatch
        XCTAssertTrue(note.exists)
        XCTAssertTrue(note.label.contains("不替代个人额度核验"), "必须写明公共信号不代表个人额度")
        capture("ai-reset-signals")
    }
    /// 反馈真的发到服务端，并显示服务端返回的工单号（之前联网时只显示「已保存草稿」，其实什么都没发）。
    func testFeedbackIsSubmittedToServerAndShowsTicket() {
        app.terminate()
        app.launchArguments = ["--workspace-fixture", "--online-ui-testing", "--api-base-url",
                               "http://127.0.0.1:18768/feedback-ok-\(UUID().uuidString)", "--screen", "profile"]
        app.launchEnvironment["KEJI_OFFLINE"] = "0"
        app.launch()
        let entry = app.buttons["反馈"].firstMatch
        for _ in 0..<6 where !entry.isHittable { app.swipeUp() }
        entry.tap()
        let field = app.textViews["feedback.text"].firstMatch
        XCTAssertTrue(field.waitForExistence(timeout: 5))
        field.tap()
        field.typeText("额度页看不到周窗口")
        tap("feedback.submit")
        let status = app.staticTexts["feedback.status"].firstMatch
        XCTAssertTrue(status.waitForExistence(timeout: 8))
        XCTAssertTrue(status.label.contains("工单 fb-ui-1"), "应显示服务端工单号，实际：\(status.label)")
        capture("feedback-submitted")
    }
    /// 偏好经 Valley 跨设备同步：改成深海蓝后，用 --sample-data 重启（会清掉本机偏好与同步状态），
    /// 深海蓝仍被选中，就只可能是从服务端拉回来的。
    func testPreferencesRoundTripThroughServer() {
        let base = "http://127.0.0.1:18768/prefs-\(UUID().uuidString)"
        func launchAppearance() {
            app.terminate()
            app.launchArguments = ["--workspace-fixture", "--online-ui-testing", "--api-base-url", base,
                                   "--screen", "appearance"]
            app.launchEnvironment["KEJI_OFFLINE"] = "0"
            app.launch()
        }
        launchAppearance()
        let dark = app.buttons["theme.dark"].firstMatch
        XCTAssertTrue(dark.waitForExistence(timeout: 8))
        XCTAssertEqual(app.buttons["theme.light"].value as? String, "已选择", "新会话默认冰晶白")
        dark.tap()
        XCTAssertEqual(dark.value as? String, "已选择")
        sleep(2)   // 等 PUT /preferences 发出
        launchAppearance()   // --workspace-fixture 带 --sample-data：本机偏好与同步基准都被清空
        let darkAgain = app.buttons["theme.dark"].firstMatch
        XCTAssertTrue(darkAgain.waitForExistence(timeout: 8))
        let adopted = NSPredicate(format: "value == %@", "已选择")
        expectation(for: adopted, evaluatedWith: darkAgain)
        waitForExpectations(timeout: 8)
        capture("preferences-round-trip")
    }
}
