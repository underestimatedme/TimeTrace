import XCTest
@testable import KeJi

/// 上架前置条件：隐私清单必须随 App 打包，并如实申报。
final class ReleaseReadinessTests: XCTestCase {
    private func privacyManifest() throws -> [String: Any] {
        let url = try XCTUnwrap(Bundle.main.url(forResource: "PrivacyInfo", withExtension: "xcprivacy"),
                                "PrivacyInfo.xcprivacy 没有打进 App 包，审核会被打回")
        let data = try Data(contentsOf: url)
        return try XCTUnwrap(PropertyListSerialization.propertyList(from: data, format: nil) as? [String: Any])
    }

    /// 刻迹不做跨 App 追踪，也不接任何追踪域名。
    func testPrivacyManifestDeclaresNoTracking() throws {
        let manifest = try privacyManifest()
        XCTAssertEqual(manifest["NSPrivacyTracking"] as? Bool, false)
        XCTAssertEqual((manifest["NSPrivacyTrackingDomains"] as? [String])?.isEmpty, true)
    }

    /// 偏好存在 UserDefaults 里，这是需要申报原因的 API（CA92.1：仅本 App 读写）。
    func testPrivacyManifestDeclaresUserDefaultsReason() throws {
        let manifest = try privacyManifest()
        let apis = try XCTUnwrap(manifest["NSPrivacyAccessedAPITypes"] as? [[String: Any]])
        let defaults = apis.first { $0["NSPrivacyAccessedAPIType"] as? String == "NSPrivacyAccessedAPICategoryUserDefaults" }
        XCTAssertEqual(defaults?["NSPrivacyAccessedAPITypeReasons"] as? [String], ["CA92.1"])
    }

    /// 如实申报：登录用的邮箱/手机号、用户写的任务内容；都不用于追踪。
    func testPrivacyManifestDeclaresCollectedDataWithoutTracking() throws {
        let manifest = try privacyManifest()
        let collected = try XCTUnwrap(manifest["NSPrivacyCollectedDataTypes"] as? [[String: Any]])
        let types = Set(collected.compactMap { $0["NSPrivacyCollectedDataType"] as? String })
        XCTAssertTrue(types.isSuperset(of: ["NSPrivacyCollectedDataTypeEmailAddress",
                                            "NSPrivacyCollectedDataTypePhoneNumber",
                                            "NSPrivacyCollectedDataTypeOtherUserContent"]))
        for entry in collected {
            XCTAssertEqual(entry["NSPrivacyCollectedDataTypeTracking"] as? Bool, false,
                           "\(entry["NSPrivacyCollectedDataType"] ?? "?") 不应标为追踪")
        }
    }

    /// 「帮助改进刻迹」的匿名使用统计：产品交互数据，关联到账号（按用户去重算漏斗），
    /// 不用于追踪，用途是分析与改进功能。
    func testPrivacyManifestDeclaresProductInteractionForAnalytics() throws {
        let manifest = try privacyManifest()
        let collected = try XCTUnwrap(manifest["NSPrivacyCollectedDataTypes"] as? [[String: Any]])
        let interaction = try XCTUnwrap(collected.first {
            $0["NSPrivacyCollectedDataType"] as? String == "NSPrivacyCollectedDataTypeProductInteraction"
        }, "使用统计会上传页面浏览与操作结果，必须申报产品交互")
        XCTAssertEqual(interaction["NSPrivacyCollectedDataTypeLinked"] as? Bool, true)
        XCTAssertEqual(interaction["NSPrivacyCollectedDataTypeTracking"] as? Bool, false)
        XCTAssertEqual(Set(interaction["NSPrivacyCollectedDataTypePurposes"] as? [String] ?? []),
                       ["NSPrivacyCollectedDataTypePurposeAnalytics", "NSPrivacyCollectedDataTypePurposeAppFunctionality"])
    }

    private func localizedInfoPlist(_ localization: String) throws -> [String: Any] {
        let url = try XCTUnwrap(Bundle.main.url(forResource: "InfoPlist", withExtension: "strings",
                                                subdirectory: nil, localization: localization),
                                "\(localization).lproj/InfoPlist.strings 没有打进 App 包")
        let data = try Data(contentsOf: url)
        return try XCTUnwrap(PropertyListSerialization.propertyList(from: data, format: nil) as? [String: Any])
    }

    /// 主屏幕名称随系统语言：英文环境叫 TimeTrace，简体中文环境叫刻迹。
    func testDisplayNameIsLocalizedPerSystemLanguage() throws {
        let english = try localizedInfoPlist("en")
        XCTAssertEqual(english["CFBundleDisplayName"] as? String, "TimeTrace")
        XCTAssertEqual(english["CFBundleName"] as? String, "TimeTrace")

        let simplifiedChinese = try localizedInfoPlist("zh-Hans")
        XCTAssertEqual(simplifiedChinese["CFBundleDisplayName"] as? String, "刻迹")
        XCTAssertEqual(simplifiedChinese["CFBundleName"] as? String, "刻迹")
    }

    /// 没有匹配语言时回落到英文名，而不是回落到中文。
    func testUnlocalizedDisplayNameFallsBackToEnglish() throws {
        let info = try XCTUnwrap(Bundle.main.infoDictionary)
        XCTAssertEqual(info["CFBundleDisplayName"] as? String, "TimeTrace")
        XCTAssertEqual(info["CFBundleName"] as? String, "TimeTrace")
        XCTAssertEqual(info["CFBundleDevelopmentRegion"] as? String, "en")
    }

    /// 关于页显示的版本号来自包信息，不写死。
    func testAboutVersionTextComesFromBundleInfo() {
        XCTAssertEqual(AppVersion.text(info: ["CFBundleShortVersionString": "0.1.0", "CFBundleVersion": "2026091201"]),
                       "版本 0.1.0（2026091201）")
        XCTAssertEqual(AppVersion.text(info: [:]), "版本未知", "缺信息时不编造版本号")
    }
}
