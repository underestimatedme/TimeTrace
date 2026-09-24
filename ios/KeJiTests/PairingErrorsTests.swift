import XCTest
@testable import KeJi

/// 配对失败要说人话：每个稳定错误码一句能照着做的提示，其余保留服务端消息。
final class PairingErrorsTests: XCTestCase {
    func testKnownCodesBecomeActionableChinese() {
        XCTAssertEqual(pairingErrorText(APIError(code: 40400, message: "resource not found")), "没有这个授权码，请核对电脑上显示的 8 位码。")
        XCTAssertEqual(pairingErrorText(APIError(code: 41000, message: "resource expired")), "授权码已过期，请在电脑上重新运行 keji cloud login。")
        XCTAssertEqual(pairingErrorText(APIError(code: 40900, message: "resource state conflict")), "这个授权码已经用过了，请在电脑上重新生成。")
        XCTAssertEqual(pairingErrorText(APIError(code: 40300, message: "operation not allowed")), "游客账号不能绑定电脑，请先登录。")
        XCTAssertEqual(pairingErrorText(APIError(code: 40100, message: "authentication required")), "登录已失效，请重新登录后再试。")
    }

    func testUnknownErrorsKeepTheirMessage() {
        XCTAssertEqual(pairingErrorText(APIError(code: 50000, message: "request failed")), "绑定失败：request failed")
        XCTAssertEqual(pairingErrorText(APIError.offline), "绑定失败：离线模式")
    }
}
