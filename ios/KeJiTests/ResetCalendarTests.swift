import XCTest
@testable import KeJi

/// 公共重置日历：服务端按 UTC 给事件，手机按用户本地时区分到哪一天。
final class ResetCalendarTests: XCTestCase {
    private func calendar(_ zone: String) -> Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: zone)!
        return calendar
    }

    private func date(_ raw: String) -> Date { ISO8601.date(from: raw)! }

    private func event(_ id: String, provider: String, kind: String = "confirmed_reset", at raw: String,
                       label: String = "") -> ResetEvent {
        ResetEvent(id: id, product: provider == "claude" ? "claude-code" : provider, provider: provider, kind: kind,
                   occurredAt: date(raw), text: "text \(id)", sourceUrl: URL(string: "https://x.com/\(id)"),
                   status: "executed", label: label, confidence: "confirmed")
    }

    private func month(_ raw: String, _ cal: Calendar) -> Date {
        let parts = raw.split(separator: "-").map { Int($0)! }
        return cal.date(from: DateComponents(year: parts[0], month: parts[1], day: 1))!
    }

    // MARK: - Decoding

    /// Valley 现在的形状：integration_status=cached，外加 events 数组。
    func testDecodesValleyCachedShapeWithEvents() throws {
        let json = #"""
        {"integration_status":"cached","sources":[{"name":"BetterOPC","url":"https://betteropc.com"}],"signals":[],"cache_age_seconds":120,"fetched_at":"2026-09-23T00:00:00Z","note":"公共信号不替代个人额度核验。",
         "events":[{"id":"rse_ab12","product":"codex","provider":"codex","kind":"confirmed_reset","occurred_at":"2026-09-22T18:23:37Z","text":"...","source_url":"https://x.com/...","status":"executed","label":"发重置卡","confidence":"confirmed"}]}
        """#
        let response = try JSONCoding.decoder.decode(ResetSignalsResponse.self, from: Data(json.utf8))
        XCTAssertEqual(response.integrationStatus, "cached")
        XCTAssertEqual(response.events.count, 1)
        let event = try XCTUnwrap(response.events.first)
        XCTAssertEqual(event.id, "rse_ab12")
        XCTAssertEqual(event.product, "codex")
        XCTAssertEqual(event.provider, "codex")
        XCTAssertEqual(event.kind, "confirmed_reset")
        XCTAssertTrue(event.isConfirmedReset)
        XCTAssertEqual(event.occurredAt, date("2026-09-22T18:23:37Z"))
        XCTAssertEqual(event.text, "...")
        XCTAssertEqual(event.sourceUrl?.absoluteString, "https://x.com/...")
        XCTAssertEqual(event.status, "executed")
        XCTAssertEqual(event.label, "发重置卡")
        XCTAssertEqual(event.confidence, "confirmed")
        XCTAssertEqual(event.kindLabel, "已重置")
    }

    /// 旧服务端没有 events；未知的 kind/status 也照收，坏掉的单条事件跳过而不是整页失败。
    func testDecodingIsTolerant() throws {
        let old = #"{"integration_status":"link_only","sources":[],"signals":[],"cache_age_seconds":0,"note":""}"#
        XCTAssertEqual(try JSONCoding.decoder.decode(ResetSignalsResponse.self, from: Data(old.utf8)).events, [])

        let json = #"""
        {"integration_status":"cached","sources":[],"signals":[],"cache_age_seconds":0,"note":"",
         "events":[{"id":"rse_1","product":"claude-code","provider":"claude","kind":"rumor","occurred_at":"2026-09-20T01:00:00Z","status":"weird"},
                   {"id":"rse_bad","occurred_at":"not a date"},
                   {"id":"rse_2","product":"codex","provider":"codex","kind":"announcement","occurred_at":"2026-09-21T01:00:00Z","text":"t","source_url":"","status":"","label":"","confidence":"possible"},
                   {"id":"rse_3","product":"codex","provider":"codex","kind":"announcement","occurred_at":"2026-09-21T02:00:00Z","label":"发重置卡"}]}
        """#
        let events = try JSONCoding.decoder.decode(ResetSignalsResponse.self, from: Data(json.utf8)).events
        XCTAssertEqual(events.map(\.id), ["rse_1", "rse_2", "rse_3"])
        XCTAssertFalse(events[0].isConfirmedReset)
        XCTAssertEqual(events[0].kindLabel, "公告")
        XCTAssertEqual(events[0].text, "")
        XCTAssertNil(events[1].sourceUrl)
        XCTAssertEqual(events[2].kindLabel, "发重置卡")
        XCTAssertEqual(events[0].productName, "Claude Code")
        XCTAssertEqual(events[1].productName, "Codex")
    }

    /// 旧调用不带参数；日历按月带 from/to（UTC 天）。
    func testResetSignalsEndpointSupportsRange() {
        XCTAssertEqual(Endpoint.resetSignals.path, "/reset-signals")
        let ranged = Endpoint.resetSignals(from: "2026-08-31", to: "2026-10-01")
        XCTAssertEqual(ranged.path, "/reset-signals?from=2026-08-31&to=2026-10-01")
        XCTAssertEqual(ranged.method, .get)
        XCTAssertTrue(ranged.requiresAuth)
    }

    // MARK: - Bucketing

    /// 上海 = UTC+8：UTC 22 日 18:23 在本地已是 23 日；UTC 22 日 15:59 仍是本地 22 日。
    func testBucketsByLocalDayAcrossUTCMidnight() {
        let cal = calendar("Asia/Shanghai")
        let events = [event("late", provider: "codex", at: "2026-09-22T18:23:37Z"),
                      event("early", provider: "claude", at: "2026-09-22T15:59:00Z")]
        let days = ResetCalendar.days(events: events, month: month("2026-09", cal), calendar: cal)
        XCTAssertEqual(days.count, 30)
        let d22 = days[21], d23 = days[22]
        XCTAssertEqual(d22.key, "2026-09-22")
        XCTAssertEqual(d22.day, 22)
        XCTAssertEqual(d22.events.map(\.id), ["early"])
        XCTAssertEqual(d22.confirmedProviders, [.claude])
        XCTAssertEqual(d23.events.map(\.id), ["late"])
        XCTAssertEqual(d23.confirmedProviders, [.codex])
    }

    /// 本地月初/月末的边界：UTC 8/31 16:00 是上海 9/1，UTC 8/31 15:59 仍是 8/31，不进九月。
    func testMonthEdgesFollowLocalTimeZone() {
        let cal = calendar("Asia/Shanghai")
        let events = [event("in", provider: "codex", at: "2026-08-31T16:00:00Z"),
                      event("out", provider: "codex", at: "2026-08-31T15:59:59Z"),
                      event("octUTCsep", provider: "claude", at: "2026-09-30T15:00:00Z"),
                      event("oct", provider: "claude", at: "2026-09-30T16:00:00Z")]
        let days = ResetCalendar.days(events: events, month: month("2026-09", cal), calendar: cal)
        XCTAssertEqual(days.first?.events.map(\.id), ["in"])
        XCTAssertEqual(days.last?.events.map(\.id), ["octUTCsep"])
        XCTAssertEqual(days.flatMap(\.events).count, 2)
    }

    /// 同一天两个工具都重置：Codex 在前、Claude 在后，各出现一次；公告只点一个淡点。
    func testMultipleProvidersOnOneDay() {
        let cal = calendar("Asia/Dubai")
        let events = [event("c2", provider: "claude", at: "2026-09-10T12:00:00Z"),
                      event("x1", provider: "codex", at: "2026-09-10T09:00:00Z"),
                      event("x2", provider: "codex", at: "2026-09-10T11:00:00Z"),
                      event("a1", provider: "codex", kind: "announcement", at: "2026-09-10T08:00:00Z"),
                      event("a2", provider: "claude", kind: "announcement", at: "2026-09-12T08:00:00Z")]
        let days = ResetCalendar.days(events: events, month: month("2026-09", cal), calendar: cal)
        let d10 = days[9]
        XCTAssertEqual(d10.confirmedProviders, [.codex, .claude])
        XCTAssertTrue(d10.hasAnnouncement)
        XCTAssertEqual(d10.events.map(\.id), ["a1", "x1", "x2", "c2"], "当天事件按时间先后")
        let d12 = days[11]
        XCTAssertEqual(d12.confirmedProviders, [])
        XCTAssertTrue(d12.hasAnnouncement)
        XCTAssertFalse(days[10].hasAnnouncement)
    }

    func testEmptyMonth() {
        let cal = calendar("America/New_York")
        let days = ResetCalendar.days(events: [], month: month("2026-02", cal), calendar: cal)
        XCTAssertEqual(days.count, 28)
        XCTAssertTrue(days.allSatisfy { $0.events.isEmpty && $0.confirmedProviders.isEmpty && !$0.hasAnnouncement })
        XCTAssertEqual(days.map(\.day), Array(1...28))
    }

    /// 周一开头：2026-09-01 是周二 → 前面空 1 格；2026-02-01 是周日 → 空 6 格。与系统 firstWeekday 无关。
    func testLeadingBlanksAreMondayFirst() {
        var cal = calendar("Asia/Shanghai")
        cal.firstWeekday = 1
        XCTAssertEqual(ResetCalendar.leadingBlanks(month: month("2026-09", cal), calendar: cal), 1)
        XCTAssertEqual(ResetCalendar.leadingBlanks(month: month("2026-02", cal), calendar: cal), 6)
        XCTAssertEqual(ResetCalendar.leadingBlanks(month: month("2026-06", cal), calendar: cal), 0)
        XCTAssertEqual(ResetCalendar.weekdaySymbols, ["一", "二", "三", "四", "五", "六", "日"])
    }

    /// 服务端的天是 UTC：请求时前后各多要一天。
    func testFetchRangePadsOneDayEachSide() {
        let cal = calendar("Asia/Shanghai")
        let range = ResetCalendar.fetchRange(month: month("2026-09", cal), calendar: cal)
        XCTAssertEqual(range.from, "2026-08-31")
        XCTAssertEqual(range.to, "2026-10-01")
        let jan = ResetCalendar.fetchRange(month: month("2027-01", cal), calendar: cal)
        XCTAssertEqual(jan.from, "2026-12-31")
        XCTAssertEqual(jan.to, "2027-02-01")
        XCTAssertEqual(ResetCalendar.monthKey(month("2027-01", cal), calendar: cal), "2027-01")
        XCTAssertEqual(ResetCalendar.monthTitle(month("2027-01", cal), calendar: cal), "2027年1月")
    }

    func testMonthStartAndShift() {
        let cal = calendar("Asia/Shanghai")
        let start = ResetCalendar.monthStart(date("2026-09-22T18:23:37Z"), calendar: cal)
        XCTAssertEqual(ResetCalendar.monthKey(start, calendar: cal), "2026-09")
        XCTAssertEqual(ResetCalendar.monthKey(ResetCalendar.shift(start, by: 1, calendar: cal), calendar: cal), "2026-10")
        XCTAssertEqual(ResetCalendar.monthKey(ResetCalendar.shift(start, by: -9, calendar: cal), calendar: cal), "2025-12")
    }

    // MARK: - Summary

    func testLatestResetSummaryPerProvider() {
        let cal = calendar("Asia/Shanghai")
        let events = [event("x-old", provider: "codex", at: "2026-09-01T00:00:00Z"),
                      event("x", provider: "codex", at: "2026-09-22T18:23:37Z"),
                      event("c", provider: "claude", at: "2026-07-16T03:58:00Z"),
                      event("c-ann", provider: "claude", kind: "announcement", at: "2026-09-20T03:58:00Z")]
        XCTAssertEqual(ResetCalendar.latestResetSummary(events: events, calendar: cal),
                       "最近一次重置：Codex 9月23日 02:23 · Claude 7月16日 11:58")
        XCTAssertEqual(ResetCalendar.latestResetSummary(events: [events[2]], calendar: cal),
                       "最近一次重置：Claude 7月16日 11:58")
        XCTAssertEqual(ResetCalendar.latestResetSummary(events: [events[3]], calendar: cal),
                       "最近没有已确认的公共重置")
    }

    func testEventTimeTextIsLocal() {
        let cal = calendar("Asia/Shanghai")
        XCTAssertEqual(ResetCalendar.timeText(date("2026-09-22T18:23:37Z"), calendar: cal), "02:23")
        XCTAssertEqual(ResetCalendar.dayTitle(date("2026-09-22T18:23:37Z"), calendar: cal), "9月23日")
    }
}

private final class ResetHTTPProtocol: URLProtocol {
    static var handler: ((URLRequest) throws -> (Int, Data))!
    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    override func startLoading() {
        do {
            let (status, data) = try Self.handler(request)
            client?.urlProtocol(self, didReceive: HTTPURLResponse(url: request.url!, statusCode: status,
                                httpVersion: nil, headerFields: nil)!, cacheStoragePolicy: .notAllowed)
            client?.urlProtocol(self, didLoad: data)
            client?.urlProtocolDidFinishLoading(self)
        } catch { client?.urlProtocol(self, didFailWithError: error) }
    }
    override func stopLoading() {}
}

/// 日历换月时按月请求，同一个月只拉一次；失败不缓存，下次还能重试。
@MainActor
final class ResetMonthCacheTests: XCTestCase {
    private var api: APIClient!
    private var session: URLSession!
    private var store: AppStore!

    override func setUp() {
        super.setUp()
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [ResetHTTPProtocol.self]
        session = URLSession(configuration: configuration)
        api = APIClient(baseURL: URL(string: "https://reset.invalid/api/v1")!,
                        keychain: KeychainStore(account: "reset-test-" + UUID().uuidString), session: session)
        api.storeTokens(SessionTokens(accessToken: "test", refreshToken: "", expiresIn: 900))
        store = AppStore()
        store.workspaceClient = WorkspaceClient(client: api)
    }

    override func tearDown() {
        api.clearTokens()
        session.invalidateAndCancel()
        ResetHTTPProtocol.handler = nil
        super.tearDown()
    }

    private func body(events: String) -> Data {
        Data(#"{"code":0,"message":"ok","data":{"integration_status":"cached","sources":[{"name":"BetterOPC","url":"https://betteropc.com"}],"signals":[],"cache_age_seconds":0,"note":"n","events":[\#(events)]}}"#.utf8)
    }

    func testLoadsMonthOnceWithPaddedRange() async {
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = TimeZone(identifier: "Asia/Shanghai")!
        let september = cal.date(from: DateComponents(year: 2026, month: 9, day: 1))!
        var queries: [String] = []
        ResetHTTPProtocol.handler = { request in
            queries.append(request.url?.query ?? "")
            return (200, self.body(events: #"{"id":"rse_1","product":"codex","provider":"codex","kind":"confirmed_reset","occurred_at":"2026-09-22T18:23:37Z"}"#))
        }
        await store.loadResetMonth(september, calendar: cal)
        await store.loadResetMonth(september, calendar: cal)
        XCTAssertEqual(queries, ["from=2026-08-31&to=2026-10-01"])
        XCTAssertEqual(store.resetEventMonths["2026-09"]?.map(\.id), ["rse_1"])
        XCTAssertEqual(store.knownResetEvents.map(\.id), ["rse_1"])
        XCTAssertEqual(store.resetSignals?.sources.first?.name, "BetterOPC", "没有整体信号时用这次的来源与说明")
    }

    func testFailureIsNotCached() async {
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = TimeZone(identifier: "UTC")!
        let month = cal.date(from: DateComponents(year: 2026, month: 8, day: 1))!
        var calls = 0
        ResetHTTPProtocol.handler = { _ in
            calls += 1
            return calls == 1 ? (500, Data(#"{"code":50000,"message":"boom","data":null}"#.utf8)) : (200, self.body(events: ""))
        }
        await store.loadResetMonth(month, calendar: cal)
        XCTAssertNil(store.resetEventMonths["2026-08"])
        await store.loadResetMonth(month, calendar: cal)
        XCTAssertEqual(store.resetEventMonths["2026-08"], [])
        XCTAssertEqual(calls, 2)
    }

    /// 摘要用的事件：整体响应与各月缓存合并，按 id 去重。
    func testKnownEventsMergeAndDeduplicate() throws {
        let json = #"{"integration_status":"cached","sources":[],"signals":[],"cache_age_seconds":0,"note":"","events":[{"id":"a","occurred_at":"2026-07-16T03:58:00Z","provider":"claude","kind":"confirmed_reset"},{"id":"b","occurred_at":"2026-09-01T00:00:00Z"}]}"#
        store.resetSignals = try JSONCoding.decoder.decode(ResetSignalsResponse.self, from: Data(json.utf8))
        store.resetEventMonths["2026-09"] = [store.resetSignals!.events[1]]
        XCTAssertEqual(Set(store.knownResetEvents.map(\.id)), ["a", "b"])
        XCTAssertEqual(store.knownResetEvents.count, 2)
    }
}
