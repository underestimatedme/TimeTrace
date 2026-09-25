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
