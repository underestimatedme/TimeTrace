import Foundation

/// Port of design/src/lib/stats.ts. `date` filters are `yyyy-MM-dd` day keys (local calendar).
enum Stats {
    static let humanTypes: [TimeSessionType] = [.humanFocus, .humanReview]
    static let aiTypes: [TimeSessionType] = [.aiActive]
    static let waitingTypes: [TimeSessionType] = [.waitingHuman, .waitingAI, .waitingExternal]

    static func matches(_ session: TimeSession, day: String?) -> Bool {
        guard let day else { return true }
        return Format.dayKey(session.startedAt) == day
    }

    static func sumSessionSeconds(_ sessions: [TimeSession], types: [TimeSessionType], day: String? = nil) -> Int {
        sessions.reduce(0) { sum, s in
            guard types.contains(s.type), matches(s, day: day) else { return sum }
            return sum + s.durationSeconds
        }
    }

    static func humanSeconds(_ sessions: [TimeSession], day: String? = nil) -> Int {
        sumSessionSeconds(sessions, types: humanTypes, day: day)
    }

    static func aiActiveSeconds(_ sessions: [TimeSession], day: String? = nil) -> Int {
        sumSessionSeconds(sessions, types: aiTypes, day: day)
    }

    static func waitingSeconds(_ sessions: [TimeSession], day: String? = nil) -> Int {
        sumSessionSeconds(sessions, types: waitingTypes, day: day)
    }

    struct WaitingByType { var human: Int; var ai: Int; var external: Int }

    static func waitingByType(_ sessions: [TimeSession], day: String? = nil) -> WaitingByType {
        WaitingByType(human: sumSessionSeconds(sessions, types: [.waitingHuman], day: day),
                      ai: sumSessionSeconds(sessions, types: [.waitingAI], day: day),
                      external: sumSessionSeconds(sessions, types: [.waitingExternal], day: day))
    }

    static func timeLeverage(humanSeconds: Int, aiSeconds: Int) -> Double {
        if humanSeconds == 0 { return aiSeconds > 0 ? .infinity : 0 }
        return Double(aiSeconds) / Double(humanSeconds)
    }

    static func planAccuracy(plannedMinutes: Int, actualMinutes: Int) -> Double {
        if plannedMinutes == 0 { return 1 }
        let deviation = abs(Double(actualMinutes - plannedMinutes)) / Double(plannedMinutes)
        return max(0, 1 - deviation)
    }

    /// Merges focus sessions >= 25 min separated by <= 5 min; counts merged blocks >= 25 min.
    static func deepWorkSeconds(_ sessions: [TimeSession], day: String? = nil) -> Int {
        let focus = sessions
            .filter { $0.type == .humanFocus && matches($0, day: day) && $0.durationSeconds >= 25 * 60 }
            .sorted { $0.startedAt < $1.startedAt }

        var total: TimeInterval = 0
        var currentStart: Date?
        var currentEnd: Date?

        for session in focus {
            let start = session.startedAt
            let end = session.endedAt ?? session.startedAt
            if let cs = currentStart, let ce = currentEnd {
                if start.timeIntervalSince(ce) <= 5 * 60 {
                    currentEnd = end
                } else {
                    let duration = ce.timeIntervalSince(cs)
                    if duration >= 25 * 60 { total += duration }
                    currentStart = start
                    currentEnd = end
                }
            } else {
                currentStart = start
                currentEnd = end
            }
        }
        if let cs = currentStart, let ce = currentEnd {
            let duration = ce.timeIntervalSince(cs)
            if duration >= 25 * 60 { total += duration }
        }
        return Int(total)
    }

    static func interruptionCount(_ sessions: [TimeSession], day: String? = nil) -> Int {
        sessions.filter { $0.type == .interruption && matches($0, day: day) }.count
    }

    static func reworkSeconds(_ sessions: [TimeSession], day: String? = nil) -> Int {
        sumSessionSeconds(sessions, types: [.rework], day: day)
    }

    struct ParallelStats: Equatable {
        var wallClockSeconds: Int
        var humanWorkloadSeconds: Int
        var aiWorkloadSeconds: Int
        var concurrencyPeak: Int
        static let empty = ParallelStats(wallClockSeconds: 0, humanWorkloadSeconds: 0, aiWorkloadSeconds: 0, concurrencyPeak: 0)
    }

    static func parallelStats(_ sessions: [TimeSession], day: String? = nil) -> ParallelStats {
        let filtered = sessions.filter {
            matches($0, day: day) && ($0.type == .humanFocus || $0.type == .humanReview || $0.type == .aiActive)
        }
        guard !filtered.isEmpty else { return .empty }

        struct Block { let start: TimeInterval; let end: TimeInterval; let human: Bool }
        let blocks = filtered.map {
            Block(start: $0.startedAt.timeIntervalSince1970,
                  end: ($0.endedAt ?? $0.startedAt).timeIntervalSince1970,
                  human: $0.type.rawValue.hasPrefix("human"))
        }
        let human = blocks.filter(\.human).reduce(0.0) { $0 + ($1.end - $1.start) }
        let ai = blocks.filter { !$0.human }.reduce(0.0) { $0 + ($1.end - $1.start) }
        let minStart = blocks.map(\.start).min() ?? 0
        let maxEnd = blocks.map(\.end).max() ?? 0

        var events: [(time: TimeInterval, delta: Int)] = []
        for b in blocks {
            events.append((b.start, 1))
            events.append((b.end, -1))
        }
        events.sort { a, b in a.time == b.time ? a.delta < b.delta : a.time < b.time }
        var current = 0, peak = 0
        for e in events {
            current += e.delta
            peak = max(peak, current)
        }
        return ParallelStats(wallClockSeconds: Int(maxEnd - minStart), humanWorkloadSeconds: Int(human),
                             aiWorkloadSeconds: Int(ai), concurrencyPeak: peak)
    }

    static func taskWallClockSeconds(_ sessions: [TimeSession], taskId: String) -> Int {
        let taskSessions = sessions.filter { $0.taskId == taskId && $0.endedAt != nil }
        guard !taskSessions.isEmpty else { return 0 }
        let starts = taskSessions.map { $0.startedAt.timeIntervalSince1970 }
        let ends = taskSessions.compactMap { $0.endedAt?.timeIntervalSince1970 }
        return Int((ends.max() ?? 0) - (starts.min() ?? 0))
    }

    struct TaskBreakdown {
        var human: Int, ai: Int, waitingHuman: Int, waitingAI: Int, waitingExternal: Int
        var interruption: Int, rework: Int, total: Int
    }

    static func taskTimeBreakdown(_ sessions: [TimeSession], taskId: String) -> TaskBreakdown {
        let ts = sessions.filter { $0.taskId == taskId }
        return TaskBreakdown(
            human: sumSessionSeconds(ts, types: humanTypes),
            ai: sumSessionSeconds(ts, types: aiTypes),
            waitingHuman: sumSessionSeconds(ts, types: [.waitingHuman]),
            waitingAI: sumSessionSeconds(ts, types: [.waitingAI]),
            waitingExternal: sumSessionSeconds(ts, types: [.waitingExternal]),
            interruption: sumSessionSeconds(ts, types: [.interruption]),
            rework: sumSessionSeconds(ts, types: [.rework]),
            total: taskWallClockSeconds(ts, taskId: taskId))
    }

    static func completedTasksCount(_ tasks: [TaskItem], day: String? = nil) -> Int {
        tasks.filter { t in
            guard t.status == .completed, let done = t.completedAt else { return false }
            guard let day else { return true }
            return Format.dayKey(done) == day
        }.count
    }

    struct TodayStats { var human: Int; var ai: Int; var waiting: Int; var completed: Int; var leverage: Double }

    static func todayStats(_ sessions: [TimeSession], tasks: [TaskItem], day: String) -> TodayStats {
        let human = humanSeconds(sessions, day: day)
        let ai = aiActiveSeconds(sessions, day: day)
        return TodayStats(human: human, ai: ai, waiting: waitingSeconds(sessions, day: day),
                          completed: completedTasksCount(tasks, day: day),
                          leverage: timeLeverage(humanSeconds: human, aiSeconds: ai))
    }

    static func aggregateDailyStats(_ stats: [DailyStats], days: Int) -> DailyStats {
        let recent = Array(stats.suffix(days))
        return recent.reduce(DailyStats.zero) { acc, d in
            DailyStats(date: "aggregate",
                       humanSeconds: acc.humanSeconds + d.humanSeconds,
                       aiActiveSeconds: acc.aiActiveSeconds + d.aiActiveSeconds,
                       waitingSeconds: acc.waitingSeconds + d.waitingSeconds,
                       deepWorkSeconds: acc.deepWorkSeconds + d.deepWorkSeconds,
                       interruptionCount: acc.interruptionCount + d.interruptionCount,
                       reworkSeconds: acc.reworkSeconds + d.reworkSeconds,
                       completedTasks: acc.completedTasks + d.completedTasks,
                       plannedMinutes: acc.plannedMinutes + d.plannedMinutes,
                       actualHumanMinutes: acc.actualHumanMinutes + d.actualHumanMinutes)
        }
    }
}
