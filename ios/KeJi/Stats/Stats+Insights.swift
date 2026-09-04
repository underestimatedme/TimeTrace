import Foundation

extension Stats {
    /// Port of `generateInsights` (copy verbatim).
    static func generateInsights(sessions: [TimeSession], tasks: [TaskItem], dailyStats: [DailyStats],
                                 executions: [AIExecution]) -> [String] {
        var insights: [String] = []
        let week = aggregateDailyStats(dailyStats, days: 7)

        let morning = sessions.filter { s in
            let hour = Format.calendar.component(.hour, from: s.startedAt)
            return hour >= 9 && hour < 11 && s.type == .humanFocus
        }
        if morning.count > 3 {
            insights.append("你在上午 9:00 至 11:00 的任务完成速度最高，建议将复杂开发任务安排在这个时段。")
        }

        let waiting = tasks.filter { $0.status == .waitingHuman }
        if waiting.count >= 3 {
            insights.append("本周有 \(waiting.count) 个 AI 任务完成后等待审核超过 30 分钟，建议设置每天两次集中审核时段。")
        }

        let dev = tasks.filter { $0.estimatedMinutes > 0 && $0.status == .completed }
        if !dev.isEmpty {
            insights.append("你通常低估开发任务时间 42%，以后建议将开发类任务的预计时长乘以 1.4。")
        }

        if week.interruptionCount > 5 {
            var pct = 31
            if week.completedTasks > 0 {
                let r = Int((Double(week.interruptionCount) / Double(week.completedTasks) * 100).rounded())
                if r != 0 { pct = r }
            }
            insights.append("本周 \(pct)% 的工作时间消耗在任务切换上，连续工作超过 45 分钟的任务完成率明显更高。")
        }

        let claude = executions.filter { $0.provider == .claude && $0.status == .completed }
        let codex = executions.filter { $0.provider == .codex && $0.status == .completed }
        if !claude.isEmpty && !codex.isEmpty {
            insights.append("Claude 任务的一次通过率为 72%，Codex 为 84%，但 Codex 平均成本更高。")
        }
        return insights
    }

    /// Computes DailyStats for the last `days` days (oldest first) from real sessions/tasks.
    /// Used when sample data is not loaded (the prototype takes dailyStats from mock data).
    static func dailyStats(sessions: [TimeSession], tasks: [TaskItem], days: Int = 7, now: Date = Date()) -> [DailyStats] {
        let cal = Format.calendar
        return (0..<days).reversed().map { offset in
            let dayDate = cal.date(byAdding: .day, value: -offset, to: cal.startOfDay(for: now)) ?? now
            let key = Format.dayKey(dayDate)
            let human = humanSeconds(sessions, day: key)
            let planned = tasks.filter { t in
                if let s = t.scheduledStart, Format.dayKey(s) == key { return true }
                if t.dueDate == key { return true }
                return false
            }.reduce(0) { $0 + $1.estimatedMinutes }
            return DailyStats(date: key,
                              humanSeconds: human,
                              aiActiveSeconds: aiActiveSeconds(sessions, day: key),
                              waitingSeconds: waitingSeconds(sessions, day: key),
                              deepWorkSeconds: deepWorkSeconds(sessions, day: key),
                              interruptionCount: interruptionCount(sessions, day: key),
                              reworkSeconds: reworkSeconds(sessions, day: key),
                              completedTasks: completedTasksCount(tasks, day: key),
                              plannedMinutes: planned,
                              actualHumanMinutes: human / 60)
        }
    }
}
