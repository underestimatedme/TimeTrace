import XCTest
@testable import KeJi

final class UserPreferencesTests: XCTestCase {
    func testCoreModulesCannotBeHidden() {
        var prefs = UserPreferences.defaults
        prefs = prefs.hiding(.goals).hiding(.todos).hiding(.blocked)
        let visible = prefs.resolvedVisibleModules()
        XCTAssertTrue(visible.contains(.goals))
        XCTAssertTrue(visible.contains(.todos))
        XCTAssertTrue(visible.contains(.blocked))
    }

    func testNonCoreModuleHides() {
        let prefs = UserPreferences.defaults.hiding(.insights)
        XCTAssertFalse(prefs.resolvedVisibleModules().contains(.insights))
        // Order stays canonical for the still-visible modules.
        XCTAssertEqual(prefs.resolvedVisibleModules().first, .goals)
        // Re-showing restores it.
        XCTAssertTrue(prefs.showing(.insights).resolvedVisibleModules().contains(.insights))
    }

    func testDefaultsAndDiagnosticsOff() {
        let p = UserPreferences.defaults
        XCTAssertFalse(p.diagnosticsEnabled)   // opt-in only
        XCTAssertFalse(p.reduceMotion)
        XCTAssertEqual(p.resolvedVisibleModules().count, HomeModule.allCases.count)
    }

    func testCodableRoundTripAndForwardCompatibleDecode() throws {
        var p = UserPreferences.defaults
        p = p.hiding(.timeline)
        p.reduceMotion = true
        p.notifications.doNotDisturbStartHour = 22
        let data = try JSONCoding.encoder.encode(p)
        let back = try JSONCoding.decoder.decode(UserPreferences.self, from: data)
        XCTAssertEqual(back, p)
        // A minimal/old blob still decodes to defaults.
        let old = try JSONCoding.decoder.decode(UserPreferences.self, from: Data("{}".utf8))
        XCTAssertEqual(old, UserPreferences.defaults)
    }

    func testFeedbackDraftValidationAndIdempotency() {
        XCTAssertFalse(FeedbackDraft.new(text: "   ").isValid)
        XCTAssertTrue(FeedbackDraft.new(text: "有个问题").isValid)
        XCTAssertFalse(FeedbackDraft.new(text: String(repeating: "x", count: FeedbackDraft.maxLength + 1)).isValid)
        // A retry keeps the same idempotency key (no duplicate ticket).
        var draft = FeedbackDraft.new(text: "问题")
        let key = draft.idempotencyKey
        draft.text = "问题（补充）"
        XCTAssertEqual(draft.idempotencyKey, key)
    }
}
