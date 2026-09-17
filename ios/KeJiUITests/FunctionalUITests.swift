import XCTest

/// Deterministic, offline UI regression suite. Uses a separate persistence file.
final class FunctionalUITests: XCTestCase {
    private var app: XCUIApplication!

    override func setUpWithError() throws {
        continueAfterFailure = false
        app = XCUIApplication()
    }

    private func launch(_ route: String, sample: Bool = true) {
        app.terminate()
        app.launchArguments = ["--ui-testing", "--offline", "--screen", route]
        if sample { app.launchArguments.append("--sample-data") }
        app.launch()
    }

    private func reveal(_ element: XCUIElement, file: StaticString = #filePath, line: UInt = #line) {
        for _ in 0..<10 {
            if element.exists && element.isHittable { return }
            app.swipeUp()
        }
        capture("unreachable-element")
        let hierarchy = XCTAttachment(string: app.debugDescription)
        hierarchy.lifetime = .keepAlways
        add(hierarchy)
        XCTAssertTrue(element.exists && element.isHittable, "Element not reachable: \(element)", file: file, line: line)
    }

    private func tap(_ title: String, file: StaticString = #filePath, line: UInt = #line) {
        let button = app.buttons[title].firstMatch
        reveal(button, file: file, line: line)
        button.tap()
    }

    private func capture(_ name: String) {
        let attachment = XCTAttachment(screenshot: app.screenshot())
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }

    /// Tasks are reached the way a user reaches them: projects tab → project → task.
    /// The bottom tabs are 今日 · 项目 · 时间线 · AI · 我的; there is no tasks tab.
    private func openTask(_ title: String, file: StaticString = #filePath, line: UInt = #line) {
        tap("workspace.tab.projects", file: file, line: line)
        // Onboarding auto-creates a single project; sample data leads with 刻迹 App.
        let project = app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH %@", "project.")).firstMatch
        reveal(project, file: file, line: line)
        project.tap()
        let row = app.buttons.matching(NSPredicate(format: "label CONTAINS %@", title)).firstMatch
        reveal(row, file: file, line: line)
        row.tap()
    }

    func testOnboardingCreatePauseResumeCompleteAndPersist() {
        launch("onboarding")
        tap("继续")
        tap("继续")
        tap("开始使用")
        tap("workspace.tab.projects")
        if !app.buttons["task.create"].waitForExistence(timeout: 2) {
            tap("workspace.tab.projects") // onboarding transition can briefly swallow the first tab tap
        }
        tap("task.create")
        let title = app.textFields["输入任务名称"]
        XCTAssertTrue(title.waitForExistence(timeout: 5))
        title.tap()
        title.typeText("QA Focus Lifecycle\n")
        tap("保存并开始")
        XCTAssertTrue(app.staticTexts["专注计时"].waitForExistence(timeout: 5))
        capture("focus-running")
        tap("暂停")
        tap("临时休息")
        openTask("QA Focus Lifecycle")
        tap("开始执行")
        XCTAssertTrue(app.staticTexts["专注计时"].waitForExistence(timeout: 5))
        tap("完成")
        openTask("QA Focus Lifecycle")
        XCTAssertTrue(app.staticTexts["已完成"].waitForExistence(timeout: 5))
        capture("focus-completed")
        XCUIDevice.shared.press(.home) // exercise background save before cold launch
        launch("tasks", sample: false)
        openTask("QA Focus Lifecycle")
        XCTAssertTrue(app.staticTexts["已完成"].waitForExistence(timeout: 5))
    }

    func testAITaskDetailStartsAIAndPauseCanResume() {
        launch("tasks/new")
        let title = app.textFields["输入任务名称"]
        XCTAssertTrue(title.waitForExistence(timeout: 5))
        title.tap()
        title.typeText("QA AI Lifecycle\n")
        tap("AI 来做")
        XCTAssertTrue(app.staticTexts["AI 提供商"].waitForExistence(timeout: 5))
        tap("保存任务")
        XCTAssertTrue(app.buttons["workspace.tab.today"].waitForExistence(timeout: 5))
        openTask("QA AI Lifecycle")
        tap("开始执行")
        XCTAssertTrue(app.staticTexts["AI 执行"].waitForExistence(timeout: 5))
        XCTAssertFalse(app.staticTexts["专注计时"].exists)
        tap("暂停")
        XCTAssertTrue(app.buttons["继续执行"].waitForExistence(timeout: 5))
        capture("ai-paused-resumable")
        tap("继续执行")
        XCTAssertTrue(app.buttons["暂停"].waitForExistence(timeout: 5))
        capture("ai-resumed")
        tap("取消")
        openTask("QA AI Lifecycle")
        XCTAssertTrue(app.staticTexts["已取消"].waitForExistence(timeout: 5))
    }

    func testAIReviewCompletesTask() {
        launch("ai/t4")
        tap("审核完成")
        XCUIDevice.shared.press(.home)
        launch("tasks/t4", sample: false)
        XCTAssertTrue(app.staticTexts["已完成"].waitForExistence(timeout: 5))
        XCTAssertFalse(app.buttons["审核完成"].exists)
        capture("ai-review-completed")
    }

    func testAllThemesAndSelectionPersists() {
        launch("appearance")
        for theme in ["claude", "codex", "cursor", "light"] {
            let row = app.buttons["theme-\(theme)"]
            reveal(row)
            row.tap()
            XCTAssertEqual(row.value as? String, "已选中")
            capture("theme-\(theme)")
        }
        XCUIDevice.shared.press(.home)
        launch("appearance", sample: false)
        XCTAssertEqual(app.buttons["theme-light"].value as? String, "已选中")
    }

    func testMainTabsAndSecondaryRoutesRender() {
        launch("today")
        for (tab, label) in [("projects", "项目"), ("timeline", "时间线"),
                             ("ai", "AI"), ("mine", "我的"), ("today", "今日")] {
            tap("workspace.tab.\(tab)")
            let button = app.buttons["workspace.tab.\(tab)"].firstMatch
            XCTAssertTrue(button.label.contains(label), "tab \(tab) is labelled \(button.label)")
            XCTAssertTrue(app.buttons["workspace.tab.today"].exists)
            XCTAssertEqual(app.state, .runningForeground)
            capture("tab-\(tab)")
        }
        for (route, expected) in [
            ("projects", "项目与目标"), ("projects/p1", "刻迹 App"),
            ("goals/g1", "目标详情"), ("ai-tools", "你的 AI"),
            ("account", "账号"), ("tasks/missing", "任务不存在")
        ] {
            launch(route)
            XCTAssertTrue(app.staticTexts[expected].waitForExistence(timeout: 5), "Route \(route)")
            capture("route-\(route.replacingOccurrences(of: "/", with: "-"))")
        }
    }
}
