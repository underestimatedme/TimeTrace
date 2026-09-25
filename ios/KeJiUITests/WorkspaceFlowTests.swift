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

    /// 报告只回答三件事：AI 今天干了什么、额度值不值、明天交给 AI 什么；不再有任何评分。
    func testReportsOpenFromTodayShowsDailyBrief() {
        app.terminate()
        app.launchArguments = ["--ui-testing", "--offline", "--sample-data", "--screen", "today"]
        app.launch()
        tap("reports.open")
        XCTAssertTrue(app.staticTexts["报告"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["AI 今天替你干了什么"].waitForExistence(timeout: 3))
        // 示例数据里 Codex 已跑完单元测试、等我确认：它必须以「去验收」突出显示。
        let review = app.buttons["reports.work.review.t4"].firstMatch
        XCTAssertTrue(review.waitForExistence(timeout: 3))
        XCTAssertTrue(review.label.contains("去验收"))
        for gone in ["生产力", "时间杠杆", "效率指数", "评分"] {
            XCTAssertFalse(app.staticTexts.matching(NSPredicate(format: "label CONTAINS %@", gone)).firstMatch.exists,
                           "报告里不应再出现「\(gone)」")
        }
        let quota = app.staticTexts["额度用得值不值"]
        for _ in 0..<6 where !quota.isHittable { app.swipeUp() }
        XCTAssertTrue(quota.exists)
        let unknown = app.descendants(matching: .any)["reports.quota.hint.pool-claude"].firstMatch
        for _ in 0..<4 where !unknown.exists { app.swipeUp() }
        XCTAssertTrue(unknown.waitForExistence(timeout: 3))
        XCTAssertTrue(unknown.label.contains("额度未知（电脑离线或未上报）"))
        // 离线没有在线电脑：「安排在重置后执行」必须禁用并说明原因。
        let schedule = app.buttons["reports.schedule.t6"].firstMatch
        for _ in 0..<6 where !schedule.isHittable { app.swipeUp() }
        XCTAssertTrue(schedule.waitForExistence(timeout: 3))
        XCTAssertFalse(schedule.isEnabled)
        XCTAssertTrue(schedule.label.contains("没有在线电脑"), schedule.label)
        capture("report-daily-brief")
        // 去验收直达对应的 Plan。
        for _ in 0..<8 where !review.isHittable { app.swipeDown() }
        review.tap()
        XCTAssertTrue(app.staticTexts["Plan 详情"].waitForExistence(timeout: 5))
    }

    /// 联网：额度与电脑来自服务端；有额度快重置而剩余很多时给出提示，
    /// 一键把任务安排到重置后 2 分钟执行，派发请求带上 not_before。
    func testReportSchedulesTaskAfterQuotaReset() {
        createTask()
        tap("workspace.tab.today")
        tap("reports.open")
        let hint = app.descendants(matching: .any)["reports.quota.hint.pool-codex"].firstMatch
        for _ in 0..<6 where !hint.exists { app.swipeUp() }
        XCTAssertTrue(hint.waitForExistence(timeout: 20), "额度应当来自服务端")
        XCTAssertTrue(hint.label.contains("还剩 62%") && hint.label.contains("现在派一批任务更划算"), hint.label)
        let schedule = app.buttons.matching(NSPredicate(format: "label CONTAINS %@", "F08 报告任务")).firstMatch
        for _ in 0..<6 where !(schedule.exists && schedule.isHittable) { app.swipeUp() }
        XCTAssertTrue(schedule.waitForExistence(timeout: 10))
        let enabled = NSPredicate(format: "enabled == true")
        expectation(for: enabled, evaluatedWith: schedule)
        waitForExpectations(timeout: 10)   // runners arrive from GET /runners
        XCTAssertTrue(schedule.label.contains("安排在重置后执行"), schedule.label)
        schedule.tap()
        let planned = app.staticTexts.matching(NSPredicate(format: "label BEGINSWITH %@", "已安排 · ")).firstMatch
        XCTAssertTrue(planned.waitForExistence(timeout: 10), app.debugDescription)
        capture("report-scheduled")
    }

    /// 项目报告只看这个项目：示例数据的「工作」项目没有 AI 任务，所以显示空状态，
    /// 也不会串进另一个项目里等待验收的 Codex 任务。
    func testProjectReportStaysWithinProject() {
        app.terminate()
        app.launchArguments = ["--ui-testing", "--offline", "--sample-data", "--screen", "reports/p2"]
        app.launch()
        XCTAssertTrue(app.staticTexts["项目报告"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["今天还没有派给 AI 的任务"].waitForExistence(timeout: 3))
        XCTAssertFalse(app.buttons["reports.work.review.t4"].exists, "other project's work must be excluded")
        XCTAssertFalse(app.buttons["reports.schedule.t6"].exists)
    }

    /// 今天还没派过 AI 任务：空状态直接给出新建任务的入口。
    func testEmptyReportOffersTaskCreation() {
        app.terminate()
        app.launchArguments = ["--workspace-fixture", "--screen", "reports"]
        app.launch()
        XCTAssertTrue(app.staticTexts["今天还没有派给 AI 的任务"].waitForExistence(timeout: 5))
        tap("reports.work.create")
        XCTAssertTrue(app.textFields["输入任务名称"].waitForExistence(timeout: 5))
    }

    /// 匿名使用统计真的发到服务端：打开报告后切到后台触发上报，fixture 只收白名单事件。
    func testUsageEventsReachServerOnBackground() throws {
        let base = "http://127.0.0.1:18768/events-\(UUID().uuidString)"
        app.terminate()
        app.launchArguments = ["--workspace-fixture", "--online-ui-testing", "--api-base-url", base, "--screen", "today"]
        app.launchEnvironment["KEJI_OFFLINE"] = "0"
        app.launch()
        tap("reports.open", timeout: 10)
        XCTAssertTrue(app.staticTexts["AI 今天替你干了什么"].waitForExistence(timeout: 5))
        sleep(3)   // 等游客会话建立
        XCUIDevice.shared.press(.home)
        var names: [String] = []
        var invalid = -1
        for _ in 0..<20 {
            sleep(1)
            let data = try Data(contentsOf: URL(string: base + "/events")!)
            let object = try JSONSerialization.jsonObject(with: data) as? [String: Any]
            let payload = object?["data"] as? [String: Any]
            names = (payload?["events"] as? [[String: Any]])?.compactMap { $0["name"] as? String } ?? []
            invalid = payload?["invalid"] as? Int ?? -1
            if names.contains("report_opened") { break }
        }
        XCTAssertTrue(names.contains("report_opened"), "received: \(names)")
        XCTAssertTrue(names.contains("app_open"), "received: \(names)")
        XCTAssertEqual(invalid, 0, "the app sent an event the server contract rejects")
        app.activate()
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

    /// 定时派发：面板里打开「指定时间执行」，派发后执行记录先显示「已安排 · 时刻」，
    /// fixture 到点后推进到待确认，并带上电脑回传的输出尾巴。
    func testScheduledDispatchShowsPlannedTimeAndCompletedJobShowsOutput() {
        createAndDispatch(scenario: "schedule", schedule: true)
        let planned = app.staticTexts.matching(NSPredicate(format: "label BEGINSWITH %@", "执行记录：已安排 · ")).firstMatch
        XCTAssertTrue(planned.waitForExistence(timeout: 10), app.debugDescription)
        capture("plan-scheduled")
        XCTAssertTrue(app.staticTexts["执行记录：结果待确认"].waitForExistence(timeout: 20))
        let disclosure = app.descendants(matching: .any).matching(NSPredicate(format: "label == %@", "查看输出（最后 8 KB）")).firstMatch
        XCTAssertTrue(disclosure.waitForExistence(timeout: 5))
        disclosure.tap()
        let output = app.staticTexts.matching(NSPredicate(format: "label CONTAINS %@", "3 passed")).firstMatch
        XCTAssertTrue(output.waitForExistence(timeout: 5))
        capture("plan-output-tail")
    }

    /// 联网建一个 Codex 任务（服务端随即建好它的 Plan），供报告页安排。
    private func createTask() {
        app.terminate()
        app.launchArguments = ["--workspace-fixture", "--online-ui-testing", "--api-base-url",
                               "http://127.0.0.1:18768/report-schedule-\(UUID().uuidString)",
                               "--screen", "tasks/new"]
        app.launchEnvironment["KEJI_OFFLINE"] = "0"
        app.launch()
        let title = app.textFields["输入任务名称"]
        XCTAssertTrue(title.waitForExistence(timeout: 5))
        title.tap()
        title.typeText("F08 报告任务\n")
        tap("AI 来做")
        tap("Codex")
        for _ in 0..<5 where !app.buttons["保存任务"].isHittable { app.swipeUp() }
        tap("保存任务")
        tap("project.keji")
        let task = app.buttons.matching(NSPredicate(format: "label CONTAINS %@", "F08 报告任务")).firstMatch
        XCTAssertTrue(task.waitForExistence(timeout: 10))
        task.tap()
        let plan = app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH %@", "plan.")).firstMatch
        XCTAssertTrue(plan.waitForExistence(timeout: 10), "created task must expose its server Plan")
        tap("subpage.back")   // task → project
        tap("subpage.back")   // project → projects tab
    }

    private func createAndDispatch(scenario: String, humanOnly: Bool = false, saveAndStart: Bool = false, schedule: Bool = false) {
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
        if schedule {
            let toggle = app.switches["plan.dispatch.schedule"].firstMatch
            XCTAssertTrue(toggle.waitForExistence(timeout: 5))
            // A Form row's centre is the label; the control sits at the trailing edge,
            // and where exactly differs per simulator, so walk inwards until the value flips.
            func isOn() -> Bool { (toggle.value as? String) == "1" }
            if let knob = toggle.switches.allElementsBoundByIndex.first, knob.exists { knob.tap() }
            for dx in [0.95, 0.9, 0.85, 0.8] where !isOn() {
                toggle.coordinate(withNormalizedOffset: CGVector(dx: dx, dy: 0.5)).tap()
                _ = app.datePickers["plan.dispatch.runAt"].firstMatch.waitForExistence(timeout: 1)
            }
            XCTAssertTrue(isOn(), "schedule toggle did not switch on: \(toggle.value ?? "nil")")
            tap("plan.dispatch.confirm")
            return
        }
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
        // CI simulators are slower and smaller: allow the guest session + quota fetch more
        // time, and scroll until each element is in the accessibility tree.
        XCTAssertTrue(app.staticTexts["62%"].waitForExistence(timeout: 20), "额度应当来自服务端，而不是示例数据")
        let source = app.descendants(matching: .any)["reset.source.BetterOPC"].firstMatch
        for _ in 0..<8 where !source.exists { app.swipeUp() }
        XCTAssertTrue(source.waitForExistence(timeout: 5), "应当显示 Valley 返回的信号来源")
        let note = app.staticTexts["reset.note"].firstMatch
        for _ in 0..<4 where !note.exists { app.swipeUp() }
        XCTAssertTrue(note.waitForExistence(timeout: 5), "应当显示公共信号说明")
        XCTAssertTrue(note.label.contains("不替代个人额度核验"), "必须写明公共信号不代表个人额度")
        capture("ai-reset-signals")
    }
    /// 公共重置日历：当月 10 日 Codex 与 Claude 都有已确认重置（fixture 按请求的月份造事件），
    /// 点开这一天列出两条事件，写明「已重置」、原文和来源。
    func testResetCalendarListsEventsOfTappedDay() {
        app.terminate()
        app.launchArguments = ["--workspace-fixture", "--online-ui-testing", "--api-base-url",
                               "http://127.0.0.1:18768/calendar-\(UUID().uuidString)", "--screen", "ai-tools"]
        app.launchEnvironment["KEJI_OFFLINE"] = "0"
        app.launch()
        let monthFormatter = DateFormatter()
        monthFormatter.calendar = Calendar(identifier: .gregorian)
        monthFormatter.dateFormat = "yyyy-MM"
        let dayKey = monthFormatter.string(from: Date()) + "-10"
        let calendar = app.descendants(matching: .any)["reset.calendar"].firstMatch
        XCTAssertTrue(app.staticTexts["62%"].waitForExistence(timeout: 20))
        let day = app.buttons["reset.day.\(dayKey)"].firstMatch
        for _ in 0..<8 where !(day.exists && day.isHittable) { app.swipeUp() }
        XCTAssertTrue(calendar.waitForExistence(timeout: 5), "AI 页应显示公共重置日历")
        XCTAssertTrue(day.waitForExistence(timeout: 10), "当月 10 日应当有重置标记")
        XCTAssertTrue(day.label.contains("Codex") && day.label.contains("Claude"), day.label)
        let summary = app.staticTexts["reset.summary"].firstMatch
        for _ in 0..<3 where !summary.isHittable { app.swipeUp() }
        XCTAssertTrue(summary.exists && summary.label.hasPrefix("最近一次重置："), summary.label)
        capture("reset-calendar")
        day.tap()
        let codex = app.descendants(matching: .any)["reset.event.rse_fixture_codex"].firstMatch
        XCTAssertTrue(codex.waitForExistence(timeout: 5), "点开日期应列出当天事件")
        XCTAssertTrue(app.descendants(matching: .any)["reset.event.rse_fixture_claude"].firstMatch.exists)
        XCTAssertTrue(app.staticTexts["Codex 用量已重置"].firstMatch.exists)
        XCTAssertTrue(app.staticTexts.matching(NSPredicate(format: "label == %@", "已重置")).count >= 2)
        XCTAssertTrue(app.buttons["查看来源"].firstMatch.exists || app.links["查看来源"].firstMatch.exists)
        capture("reset-calendar-day")
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
