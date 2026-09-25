import XCTest
@testable import KeJi

/// 「我的」页只显示真实数据：名字来自账号，头像是名字首字，连续天数从时间记录算。
final class ProfileIdentityTests: XCTestCase {
    func testDisplayNamePrefersACustomNameThenTheAccount() {
        let user = UserInfo(id: "u", isGuest: false, accountLabel: "138****5678")
        XCTAssertEqual(ProfileIdentity.displayName(settingsName: "刻迹用户", user: user), "138****5678")
        XCTAssertEqual(ProfileIdentity.displayName(settingsName: "Joey", user: user), "Joey")
        XCTAssertEqual(ProfileIdentity.displayName(settingsName: "刻迹用户", user: UserInfo(id: "g", isGuest: true)), "游客")
        XCTAssertEqual(ProfileIdentity.displayName(settingsName: "", user: nil), "游客")
    }

    func testInitialIsTheFirstMeaningfulCharacter() {
        XCTAssertEqual(ProfileIdentity.initial(of: "Joey"), "J")
        XCTAssertEqual(ProfileIdentity.initial(of: "138****5678"), "1")
        XCTAssertEqual(ProfileIdentity.initial(of: "王小明"), "王")
        XCTAssertEqual(ProfileIdentity.initial(of: ""), "刻")
    }

    func testStreakCountsConsecutiveDaysWithRecordedTime() {
        let cal = Calendar.current
        let today = cal.date(from: DateComponents(year: 2026, month: 9, day: 25, hour: 20))!
        func session(daysAgo: Int) -> TimeSession {
            let start = cal.date(byAdding: .day, value: -daysAgo, to: today)!
            return TimeSession(id: UUID().uuidString, taskId: "t", type: .aiActive, executor: "codex", startedAt: start,
                               endedAt: start.addingTimeInterval(600), durationSeconds: 600, source: .integration, confidence: .exact,
                               note: nil, updatedAt: start)
        }
        XCTAssertEqual(Stats.streakDays([], asOf: today), 0)
        XCTAssertEqual(Stats.streakDays([session(daysAgo: 0), session(daysAgo: 1), session(daysAgo: 2)], asOf: today), 3)
        XCTAssertEqual(Stats.streakDays([session(daysAgo: 1), session(daysAgo: 2)], asOf: today), 2, "today not yet recorded keeps yesterday's streak")
        XCTAssertEqual(Stats.streakDays([session(daysAgo: 0), session(daysAgo: 2)], asOf: today), 1)
    }
}
