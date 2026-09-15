import XCTest

/// I2 offline workspace flow: projects → keji → quota → plan.03, where dispatch
/// is gated until its dependencies (plan.01, plan.02) are accepted.
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

    func testDispatchGatedByAcceptedDependencies() {
        // Drill down to plan.03.
        tap("project.keji")
        tap("task.quota")
        tap("plan.03")

        let dispatch = app.buttons["plan.dispatch"].firstMatch
        XCTAssertTrue(dispatch.waitForExistence(timeout: 5))
        XCTAssertFalse(dispatch.isEnabled, "dispatch must be disabled while dependencies are unaccepted")

        // Accept both dependencies.
        for dep in ["plan.01", "plan.02"] {
            tap("subpage.back")            // back to task.quota
            tap(dep)
            tap("plan.accept")
        }

        // Return to plan.03; dispatch is now enabled.
        tap("subpage.back")
        tap("plan.03")
        let dispatch2 = app.buttons["plan.dispatch"].firstMatch
        XCTAssertTrue(dispatch2.waitForExistence(timeout: 5))
        XCTAssertTrue(dispatch2.isEnabled, "dispatch must enable once dependencies are accepted")
    }
}
