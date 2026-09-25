import XCTest

/// 扫码 / keji:// 链接绑定电脑，以及给电脑重命名。
/// Run TestSupport/workspace_server.py on the host first (port 18768).
final class PairingFlowTests: XCTestCase {
    private var app: XCUIApplication!

    override func setUp() {
        continueAfterFailure = false
        app = XCUIApplication()
    }

    private func launchOnline(_ scenario: String, screen: String) {
        app.launchArguments = ["--workspace-fixture", "--online-ui-testing", "--api-base-url",
                               "http://127.0.0.1:18768/\(scenario)-\(UUID().uuidString)", "--screen", screen]
        app.launchEnvironment["KEJI_OFFLINE"] = "0"
        app.launch()
    }

    /// 打开 keji://pair 链接：切到 AI 页、预填授权码并直接弹出确认框，确认后完成绑定。
    func testPairLinkOpensConfirmationAndApproves() {
        launchOnline("pairlink", screen: "today")
        // 登录态可能晚于链接就绪：AI 页会在登录完成后自动核对，不需要等。
        XCTAssertTrue(app.buttons["workspace.tab.ai"].waitForExistence(timeout: 10))
        app.open(URL(string: "keji://pair?code=abcd1234&name=Fixture%20Mac&platform=darwin&v=1")!)
        let confirm = app.buttons["确认绑定"].firstMatch
        XCTAssertTrue(confirm.waitForExistence(timeout: 15), "打开链接应直接弹出确认绑定")
        XCTAssertTrue(app.staticTexts.containing(NSPredicate(format: "label CONTAINS %@", "Fixture Mac")).firstMatch.exists)
        confirm.tap()
        XCTAssertTrue(app.staticTexts["电脑已绑定，可以远程派发任务。"].waitForExistence(timeout: 10))
    }

    /// 过期的二维码（exp 已过）不去服务端核对，直接提示看电脑上的新二维码。
    func testExpiredPairLinkShowsRefreshHint() {
        launchOnline("pairexpired", screen: "today")
        XCTAssertTrue(app.buttons["workspace.tab.ai"].waitForExistence(timeout: 10))
        app.open(URL(string: "keji://pair?code=abcd1234&name=Fixture%20Mac&exp=1000000000&platform=darwin&v=1")!)
        let message = app.staticTexts["二维码已过期，请看电脑上刷新出的新二维码"].firstMatch
        for _ in 0..<6 where !message.exists { app.swipeUp() }
        XCTAssertTrue(message.waitForExistence(timeout: 15), "过期链接应提示刷新")
        XCTAssertFalse(app.buttons["确认绑定"].firstMatch.waitForExistence(timeout: 3), "过期链接不应弹出确认绑定")
    }

    /// 链接上的电脑名与服务端记录不一致：确认框第一行就是警告。
    func testPairLinkNameMismatchWarnsInConfirmation() {
        launchOnline("pairmismatch", screen: "today")
        XCTAssertTrue(app.buttons["workspace.tab.ai"].waitForExistence(timeout: 10))
        let exp = Int(Date().timeIntervalSince1970) + 120
        app.open(URL(string: "keji://pair?code=ABCD1234&name=Other%20Mac&exp=\(exp)&platform=darwin&v=1")!)
        XCTAssertTrue(app.buttons["确认绑定"].firstMatch.waitForExistence(timeout: 15))
        let warning = app.staticTexts.containing(NSPredicate(format: "label BEGINSWITH %@",
            "⚠️ 二维码上的电脑名（Other Mac）与服务器记录（Fixture Mac）不一致")).firstMatch
        XCTAssertTrue(warning.exists, "确认框应以电脑名不一致的警告开头")
    }

    /// 手输授权码仍然能走核对 → 确认，且没有链接时不出现电脑名警告。
    func testTypedCodeStillInspects() {
        launchOnline("pairtyped", screen: "ai-tools")
        let field = app.textFields["runner-pairing-code"].firstMatch
        for _ in 0..<6 where !(field.exists && field.isHittable) { app.swipeUp() }
        XCTAssertTrue(field.waitForExistence(timeout: 15))
        field.tap()
        field.typeText("abcd1234")
        let submit = app.buttons["runner-pairing-submit"].firstMatch
        if !submit.isHittable { app.swipeUp() }
        submit.tap()
        XCTAssertTrue(app.buttons["确认绑定"].firstMatch.waitForExistence(timeout: 15))
        XCTAssertFalse(app.staticTexts.containing(NSPredicate(format: "label CONTAINS %@", "不一致")).firstMatch.exists)
        XCTAssertTrue(app.staticTexts.containing(NSPredicate(format: "label CONTAINS %@", "Fixture Mac")).firstMatch.exists)
    }

    /// 模拟器没有相机：扫码页要说明原因，而不是黑屏。
    func testScannerExplainsWhenNoCamera() {
        launchOnline("scan", screen: "ai-tools")
        let scan = app.buttons["pairing.scan"].firstMatch
        for _ in 0..<6 where !scan.isHittable { app.swipeUp() }
        XCTAssertTrue(scan.waitForExistence(timeout: 15))
        scan.tap()
        let message = app.staticTexts["pairing.scanner.message"].firstMatch
        XCTAssertTrue(message.waitForExistence(timeout: 10))
        XCTAssertTrue(message.label.contains("相机"), message.label)
        app.buttons["pairing.scanner.close"].firstMatch.tap()
        XCTAssertTrue(scan.waitForExistence(timeout: 5))
    }

    /// 设备与授权里给电脑改名：走 PATCH /runners/:id，列表随即显示新名字。
    func testRenameComputerFromDevices() {
        launchOnline("rename", screen: "devices")
        let rename = app.buttons["device.rename.runner-ui"].firstMatch
        XCTAssertTrue(rename.waitForExistence(timeout: 15))
        rename.tap()
        let field = app.alerts.textFields.firstMatch
        XCTAssertTrue(field.waitForExistence(timeout: 5))
        field.tap()
        // 输入框预填了当前名字：先删干净再输入新名字。
        field.typeText(String(repeating: XCUIKeyboardKey.delete.rawValue, count: 20))
        field.typeText("书房 iMac")
        app.alerts.buttons["保存"].tap()
        XCTAssertTrue(app.staticTexts["书房 iMac"].waitForExistence(timeout: 10))
    }
}
