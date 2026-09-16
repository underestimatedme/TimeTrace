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
