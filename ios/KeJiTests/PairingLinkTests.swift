import XCTest
@testable import KeJi

/// `keji cloud login` 打印的二维码与 Valley 的 verification_uri 都是 keji://pair 链接；
/// 手机只从里面取 8 位授权码（和可选的电脑名），其余一律不认。
final class PairingLinkTests: XCTestCase {
    private func parse(_ string: String) -> PairingLink? {
        URL(string: string).flatMap(PairingLink.parse)
    }

    func testValidLinkYieldsCodeAndName() {
        let link = parse("keji://pair?code=ABCD1234&name=Joey%20%E7%9A%84%20Mac&platform=darwin&v=1")
        XCTAssertEqual(link, PairingLink(code: "ABCD1234", name: "Joey 的 Mac"))
    }

    func testCodeIsTrimmedAndUppercased() {
        XCTAssertEqual(parse("keji://pair?code=%20a1b2c3d4%20")?.code, "A1B2C3D4")
        XCTAssertEqual(parse("KEJI://PAIR?code=abcd1234")?.code, "ABCD1234")
    }

    func testNameIsOptional() {
        XCTAssertEqual(parse("keji://pair?code=ABCD1234"), PairingLink(code: "ABCD1234", name: nil))
        XCTAssertNil(parse("keji://pair?code=ABCD1234&name=%20")?.name)
    }

    func testRejectsOtherSchemesAndHosts() {
        XCTAssertNil(parse("https://pair?code=ABCD1234"))
        XCTAssertNil(parse("https://apis.atlaspaces.com/pair?code=ABCD1234"))
        XCTAssertNil(parse("keji://other?code=ABCD1234"))
        XCTAssertNil(parse("keji:pair?code=ABCD1234"))
    }

    func testRejectsMissingOrMalformedCode() {
        XCTAssertNil(parse("keji://pair"))
        XCTAssertNil(parse("keji://pair?name=Mac"))
        XCTAssertNil(parse("keji://pair?code=ABC123"))
        XCTAssertNil(parse("keji://pair?code=ABCD12345"))
        XCTAssertNil(parse("keji://pair?code=ABCD-123"))
    }

    /// 新 CLI 在链接里带 exp（unix 秒）；旧 CLI 不带就永不按本地时间判过期，交给服务端。
    func testParsesOptionalExpiry() {
        let link = parse("keji://pair?code=ABCD1234&name=Mac&exp=1790000000&platform=darwin&v=1")
        XCTAssertEqual(link?.exp, 1790000000)
        XCTAssertEqual(link?.isExpired(now: Date(timeIntervalSince1970: 1789999999)), false)
        XCTAssertEqual(link?.isExpired(now: Date(timeIntervalSince1970: 1790000000)), true)
        XCTAssertEqual(link?.isExpired(now: Date(timeIntervalSince1970: 1790000100)), true)
        let old = parse("keji://pair?code=ABCD1234")
        XCTAssertNil(old?.exp)
        XCTAssertEqual(old?.isExpired(now: .distantFuture), false)
        // exp 写坏了不影响授权码本身：当作没有 exp。
        XCTAssertNil(parse("keji://pair?code=ABCD1234&exp=soon")?.exp)
        XCTAssertEqual(parse("keji://pair?code=ABCD1234&exp=soon")?.code, "ABCD1234")
        XCTAssertEqual(PairingLink.expiredMessage, "二维码已过期，请看电脑上刷新出的新二维码")
    }

    /// 二维码上的电脑名与服务端记录不一致时要提醒（忽略首尾空白与大小写）。
    func testNameMismatchWarning() {
        XCTAssertNil(pairingNameMismatchWarning(linkName: nil, serverName: "Fixture Mac"))
        XCTAssertNil(pairingNameMismatchWarning(linkName: "  fixture MAC ", serverName: "Fixture Mac"))
        XCTAssertNil(pairingNameMismatchWarning(linkName: "  ", serverName: "Fixture Mac"))
        XCTAssertEqual(pairingNameMismatchWarning(linkName: "Joey 的 Mac", serverName: "Fixture Mac"),
                       "⚠️ 二维码上的电脑名（Joey 的 Mac）与服务器记录（Fixture Mac）不一致，确认是你自己的电脑再绑定")
    }

    /// 确认框正文：不一致时第一行就是警告，其余照旧。
    func testConfirmMessageStartsWithWarningOnMismatch() {
        let now = Date(timeIntervalSince1970: 1_790_000_000)
        let info = DeviceAuthorizationInspection(deviceName: "Fixture Mac", platform: "darwin", clientVersion: "0.4.0",
                                                 requestedAt: now, expiresAt: now.addingTimeInterval(120),
                                                 permissions: ["receive_jobs"])
        let warned = pairingConfirmMessage(info, linkName: "Other Mac", now: now)
        XCTAssertTrue(warned.hasPrefix("⚠️ 二维码上的电脑名（Other Mac）与服务器记录（Fixture Mac）不一致，确认是你自己的电脑再绑定\n"), warned)
        XCTAssertTrue(warned.contains("Fixture Mac · darwin · v0.4.0"))
        let plain = pairingConfirmMessage(info, linkName: "fixture mac", now: now)
        XCTAssertTrue(plain.hasPrefix("Fixture Mac · darwin · v0.4.0\n"), plain)
        XCTAssertTrue(plain.contains("权限：仅接收任务"))
        XCTAssertEqual(pairingConfirmMessage(info, linkName: nil, now: now), plain)
    }

    /// 从二维码读到的是字符串：非 URL、非刻迹的二维码都不能触发绑定。
    func testScannedStringParsing() {
        XCTAssertEqual(PairingLink.parse(scanned: " keji://pair?code=abcd1234 ")?.code, "ABCD1234")
        XCTAssertNil(PairingLink.parse(scanned: "hello world"))
        XCTAssertNil(PairingLink.parse(scanned: "https://example.com"))
    }

    /// 打开链接：切到 AI 页、清掉子页面，把授权码交给 AI 页去核对。
    @MainActor
    func testRouterRoutesPairingLinkToAITab() {
        let router = AppRouter()
        router.phase = .main
        router.go(.mine)
        router.push(.devices)
        router.openPairing(PairingLink(code: "ABCD1234", name: nil))
        XCTAssertEqual(router.tab, .ai)
        XCTAssertTrue(router.path.isEmpty)
        XCTAssertEqual(router.pendingPairing?.code, "ABCD1234")
    }

    func testRenameRunnerEndpointContract() throws {
        let endpoint = Endpoint.renameRunner(id: "r1", name: "书房 iMac")
        XCTAssertEqual(endpoint.path, "/runners/r1")
        XCTAssertEqual(endpoint.method, .patch)
        XCTAssertTrue(endpoint.requiresAuth)
        let body = try XCTUnwrap(endpoint.body)
        let object = try JSONSerialization.jsonObject(with: JSONCoding.encoder.encode(body)) as? [String: Any]
        XCTAssertEqual(object?["name"] as? String, "书房 iMac")
    }
}

/// 扫码绑定需要相机权限说明，打开 keji:// 链接需要注册 URL scheme；缺一个都会在真机上失效。
final class PairingInfoPlistTests: XCTestCase {
    func testCameraUsageDescriptionAndURLSchemeAreDeclared() throws {
        let info = try XCTUnwrap(Bundle.main.infoDictionary)
        XCTAssertEqual(info["NSCameraUsageDescription"] as? String, "扫描电脑上的二维码以绑定这台电脑")
        let types = try XCTUnwrap(info["CFBundleURLTypes"] as? [[String: Any]])
        let schemes = types.flatMap { $0["CFBundleURLSchemes"] as? [String] ?? [] }
        XCTAssertTrue(schemes.contains("keji"), "\(schemes)")
    }
}
