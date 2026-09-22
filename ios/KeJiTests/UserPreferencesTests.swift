import XCTest
@testable import KeJi

final class UserPreferencesTests: XCTestCase {
    func testFeedbackRefusesSensitiveProseAndUsesServerByteLimit() {
        for text in ["Authorization: Bearer secret", "token=secret", "contact me@example.com", "API_KEY=secret", "HOME=/Users/private", "PATH=/private/bin", #"{"HOME":"/Users/private"}"#, "environment_snapshot: {}", String(repeating: "中", count: 1400)] {
            XCTAssertFalse(FeedbackDraft.new(text: text).isValid, "unsafe or oversized feedback must stay local")
        }
    }

    @MainActor func testClearingAccountResetsPreferences() {
        let store = AppStore()
        store.updatePreferences { $0.reduceMotion = true }
        store.clearAll()
        XCTAssertEqual(store.preferences, .defaults)
    }

    func testPreferencesAccountIsolationAndLegacyUnownedDataNotImported() throws {
        let suite = "f11.preferences." + UUID().uuidString
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        var changed = UserPreferences.defaults
        changed.reduceMotion = true
        defaults.set(try JSONCoding.encoder.encode(changed), forKey: "keji.preferences.v1")
        let storage = PreferencesStore(defaults: defaults)
        XCTAssertEqual(storage.load(userID: "alice"), .defaults)
        storage.save(changed, userID: "alice")
        XCTAssertEqual(storage.load(userID: "bob"), .defaults)
        XCTAssertEqual(storage.load(userID: nil), .defaults)
        XCTAssertEqual(PreferencesStore(defaults: defaults).load(userID: "alice"), changed)
    }
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
    /// 三方合并：只把本机改过的字段套到服务端最新版上，另一台设备改的字段不被冲掉。
    func testThreeWayMergeKeepsBothDevicesChanges() {
        let base = UserPreferences.defaults
        var local = base; local.themeMode = .dark                  // 本机改了主题
        var remote = base; remote.reduceMotion = true              // 另一台设备改了减少动效
        let merged = PreferencesMerge.threeWay(base: base, local: local, remote: remote)
        XCTAssertEqual(merged.themeMode, .dark, "本机的改动保留")
        XCTAssertTrue(merged.reduceMotion, "另一台设备的改动也保留，不被静默覆盖")
    }

    /// 同一个字段两边都改了：以本机用户这次的操作为准（那是他刚刚明确做的选择）。
    func testThreeWayMergePrefersLocalOnTheSameField() {
        let base = UserPreferences.defaults
        var local = base; local.accent = .violet
        var remote = base; remote.accent = .blue; remote.themeMode = .system
        let merged = PreferencesMerge.threeWay(base: base, local: local, remote: remote)
        XCTAssertEqual(merged.accent, .violet)
        XCTAssertEqual(merged.themeMode, .system)
    }

    /// 服务端还没有记录时返回 revision 0 和空对象 {}，应解成默认偏好。
    func testRemotePreferencesDecodesEmptyServerRecord() throws {
        let json = #"{"revision":0,"data":{},"updated_at":"0001-01-01T00:00:00Z"}"#
        let remote = try JSONCoding.decoder.decode(RemotePreferences.self, from: Data(json.utf8))
        XCTAssertEqual(remote.revision, 0)
        XCTAssertEqual(remote.data, UserPreferences.defaults)
    }

    func testPutPreferencesMatchesValleyContract() throws {
        var prefs = UserPreferences.defaults; prefs.themeMode = .dark
        let endpoint = Endpoint.putPreferences(expectedRevision: 3, prefs: prefs)
        XCTAssertEqual(endpoint.path, "/preferences")
        XCTAssertEqual(endpoint.method, .put)
        XCTAssertEqual(Endpoint.getPreferences.path, "/preferences")
        let body = try JSONSerialization.jsonObject(with: JSONCoding.encoder.encode(
            PutPreferencesBody(expectedRevision: 3, data: prefs))) as? [String: Any]
        XCTAssertEqual(body?["expected_revision"] as? Int, 3)
        XCTAssertEqual((body?["data"] as? [String: Any])?["theme_mode"] as? String, "dark")
    }
    /// 本机没改过：服务端有新版本就采用，没有就不动。
    func testSyncAdoptsNewerRemoteWhenNothingChangedLocally() {
        let state = PreferencesSyncState(revision: 2, base: .defaults)
        var remoteData = UserPreferences.defaults; remoteData.themeMode = .dark
        XCTAssertEqual(PreferencesSync.plan(local: .defaults, state: state,
                                            remote: RemotePreferences(revision: 3, data: remoteData)),
                       .adopt(remoteData, revision: 3))
        XCTAssertEqual(PreferencesSync.plan(local: .defaults, state: state,
                                            remote: RemotePreferences(revision: 2, data: .defaults)),
                       .none)
    }

    /// 本机改过：合并到服务端最新版上再推，用服务端当前 revision 做乐观锁。
    func testSyncPushesMergedChangesAgainstTheLatestRevision() {
        let state = PreferencesSyncState(revision: 2, base: .defaults)
        var local = UserPreferences.defaults; local.accent = .violet
        var remoteData = UserPreferences.defaults; remoteData.reduceMotion = true
        guard case let .push(merged, expected) = PreferencesSync.plan(
            local: local, state: state, remote: RemotePreferences(revision: 5, data: remoteData)) else {
            return XCTFail("本机有改动时应当推送")
        }
        XCTAssertEqual(expected, 5)
        XCTAssertEqual(merged.accent, .violet)
        XCTAssertTrue(merged.reduceMotion)
    }

    /// 第一次同步：服务端还没记录（revision 0、空对象），本机改过就以 0 为预期版本推上去。
    func testFirstSyncPushesAgainstRevisionZero() {
        var local = UserPreferences.defaults; local.themeMode = .system
        XCTAssertEqual(PreferencesSync.plan(local: local, state: PreferencesSyncState(),
                                            remote: RemotePreferences(revision: 0, data: .defaults)),
                       .push(local, expectedRevision: 0))
    }
}
