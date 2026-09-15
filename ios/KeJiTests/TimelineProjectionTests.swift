import XCTest
@testable import KeJi

final class TimelineProjectionTests: XCTestCase {
    func testHumanAndAIStaySeparate() {
        let start = Date(timeIntervalSince1970: 0)
        let records = [TrackInterval(start: start, end: start.addingTimeInterval(600), track: .human),
                       TrackInterval(start: start, end: start.addingTimeInterval(900), track: .ai)]
        XCTAssertEqual(activeSeconds(records, track: .human), 600)
        XCTAssertEqual(activeSeconds(records, track: .ai), 900)
    }

    func testAIActivityAccumulatesAcrossMachines() {
        let start = Date(timeIntervalSince1970: 0)
        // Two machines active over the same wall-clock window: AI active time
        // accumulates (shown as 累计活跃), it is not a union.
        let records = [TrackInterval(start: start, end: start.addingTimeInterval(300), track: .ai),
                       TrackInterval(start: start, end: start.addingTimeInterval(300), track: .ai)]
        XCTAssertEqual(activeSeconds(records, track: .ai), 600)
    }

    func testHumanOverlapIsUnionNotDoubleCounted() {
        let start = Date(timeIntervalSince1970: 0)
        // Overlapping human records (a data anomaly) must not double count.
        let records = [TrackInterval(start: start, end: start.addingTimeInterval(600), track: .human),
                       TrackInterval(start: start.addingTimeInterval(300), end: start.addingTimeInterval(900), track: .human)]
        XCTAssertEqual(unionSeconds(records, track: .human), 900)
        XCTAssertTrue(hasOverlap(records, track: .human))
    }

    func testNegativeAndDedup() {
        let start = Date(timeIntervalSince1970: 0)
        let records = [
            TrackInterval(id: "e1", start: start.addingTimeInterval(100), end: start, track: .ai), // negative -> 0
            TrackInterval(id: "e2", start: start, end: start.addingTimeInterval(120), track: .ai),
            TrackInterval(id: "e2", start: start, end: start.addingTimeInterval(120), track: .ai), // duplicate id
        ]
        XCTAssertEqual(dedupedByID(records).count, 2)
        XCTAssertEqual(activeSeconds(dedupedByID(records), track: .ai), 120)
    }
}
