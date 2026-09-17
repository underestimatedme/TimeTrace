import Foundation

/// The three timeline tracks. Human and AI time are shown and summed
/// independently — never added together into a single number.
enum TimelineTrack: String, Codable { case human, ai, waiting }

/// Calendar day boundaries, including the 23/25-hour IANA DST days.
func reportDayInterval(_ day: String, timeZone: TimeZone) -> DateInterval? {
    let formatter = DateFormatter()
    formatter.locale = Locale(identifier: "en_US_POSIX")
    formatter.calendar = Calendar(identifier: .gregorian)
    formatter.timeZone = timeZone
    formatter.dateFormat = "yyyy-MM-dd"
    formatter.isLenient = false
    guard let date = formatter.date(from: day), formatter.string(from: date) == day else { return nil }
    var calendar = Calendar(identifier: .gregorian)
    calendar.timeZone = timeZone
    return calendar.dateInterval(of: .day, for: date)
}

struct TrackInterval: Equatable, Identifiable {
    let id: String
    let start: Date
    let end: Date
    let track: TimelineTrack

    init(id: String = UUID().uuidString, start: Date, end: Date, track: TimelineTrack) {
        self.id = id; self.start = start; self.end = end; self.track = track
    }
}

/// Active seconds on one track = sum of positive interval durations. Used for AI
/// activity, which can accumulate across machines (shown as "累计活跃"). Human and
/// AI are computed separately, so parallel AI time never inflates human time.
func activeSeconds(_ intervals: [TrackInterval], track: TimelineTrack) -> TimeInterval {
    intervals.filter { $0.track == track }.reduce(0) { $0 + max(0, $1.end.timeIntervalSince($1.start)) }
}

/// Union seconds on one track = merged, non-overlapping duration. Used for human
/// time (a person cannot be in two places at once, so overlaps are not
/// double-counted) and for a project's elapsed span.
func unionSeconds(_ intervals: [TrackInterval], track: TimelineTrack) -> TimeInterval {
    let sorted = intervals.filter { $0.track == track && $0.end > $0.start }
        .sorted { $0.start < $1.start }
    var total: TimeInterval = 0
    var cursor: Date?
    var end: Date?
    for interval in sorted {
        if let e = end, interval.start <= e {
            if interval.end > e { end = interval.end }
        } else {
            if let s = cursor, let e = end { total += e.timeIntervalSince(s) }
            cursor = interval.start
            end = interval.end
        }
    }
    if let s = cursor, let e = end { total += e.timeIntervalSince(s) }
    return total
}

/// True when two same-track intervals overlap — a human track with overlaps is
/// flagged anomalous rather than silently double-counted.
func hasOverlap(_ intervals: [TrackInterval], track: TimelineTrack) -> Bool {
    let sorted = intervals.filter { $0.track == track }.sorted { $0.start < $1.start }
    for i in 1..<max(sorted.count, 1) where i < sorted.count {
        if sorted[i].start < sorted[i - 1].end { return true }
    }
    return false
}

/// Deduplicates intervals by id (network retries can deliver the same event
/// twice) before any accumulation.
func dedupedByID(_ intervals: [TrackInterval]) -> [TrackInterval] {
    var seen = Set<String>()
    var result: [TrackInterval] = []
    for interval in intervals where seen.insert(interval.id).inserted {
        result.append(interval)
    }
    return result
}

/// 时间线的三条轨：我 / AI / 等待。等待是独立的第三类，不属于任何一方的工作时间。
/// 项目筛选复用报告的范围规则，项目视图不会串进别的项目。
struct TimelineLanes: Equatable {
    var human: [TimeSession]
    var ai: [TimeSession]
    var waiting: [TimeSession]

    var isEmpty: Bool { human.isEmpty && ai.isEmpty && waiting.isEmpty }

    /// 人工重叠取并集，AI 并行累计 —— 和报告口径一致。
    var humanSeconds: Int { Int(unionSeconds(intervals(human, track: .human), track: .human)) }
    var aiSeconds: Int { Int(activeSeconds(intervals(ai, track: .ai), track: .ai)) }
    var waitingSeconds: Int { Int(activeSeconds(intervals(waiting, track: .waiting), track: .waiting)) }

    var summaryText: String {
        "人工投入 \(Format.duration(humanSeconds)) · AI 活跃 \(Format.duration(aiSeconds))"
            + " · 等待 \(Format.duration(waitingSeconds))（三者不相加）"
    }

    init(sessions: [TimeSession], tasks: [TaskItem], scope: ReportScope) {
        let scoped = sessionsInScope(scope, tasks: tasks, sessions: sessions).sorted { $0.startedAt < $1.startedAt }
        human = scoped.filter { Stats.humanTypes.contains($0.type) }
        ai = scoped.filter { Stats.aiTypes.contains($0.type) }
        waiting = scoped.filter { Stats.waitingTypes.contains($0.type) }
    }

    private func intervals(_ sessions: [TimeSession], track: TimelineTrack) -> [TrackInterval] {
        dedupedByID(sessions.map {
            TrackInterval(id: $0.id, start: $0.startedAt,
                          end: $0.endedAt ?? $0.startedAt.addingTimeInterval(TimeInterval($0.durationSeconds)),
                          track: track)
        })
    }
}
