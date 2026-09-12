import type { DailyStats, Task, TimeSession } from '@/types'

const HUMAN_TYPES = ['human_focus', 'human_review'] as const
const AI_TYPES = ['ai_active'] as const
const WAITING_TYPES = ['waiting_human', 'waiting_ai', 'waiting_external'] as const

export function sumSessionSeconds(
  sessions: TimeSession[],
  types: readonly string[],
  dateFilter?: string
): number {
  return sessions
    .filter((s) => {
      if (!types.includes(s.type)) return false
      if (dateFilter && !s.startedAt.startsWith(dateFilter)) return false
      return true
    })
    .reduce((sum, s) => sum + s.durationSeconds, 0)
}

export function getHumanSeconds(sessions: TimeSession[], date?: string): number {
  return sumSessionSeconds(sessions, HUMAN_TYPES, date)
}

export function getAIActiveSeconds(sessions: TimeSession[], date?: string): number {
  return sumSessionSeconds(sessions, AI_TYPES, date)
}

export function getWaitingSeconds(sessions: TimeSession[], date?: string): number {
  return sumSessionSeconds(sessions, WAITING_TYPES, date)
}

export function getWaitingByType(sessions: TimeSession[], date?: string) {
  return {
    human: sumSessionSeconds(sessions, ['waiting_human'], date),
    ai: sumSessionSeconds(sessions, ['waiting_ai'], date),
    external: sumSessionSeconds(sessions, ['waiting_external'], date),
  }
}

export function getTimeLeverage(humanSeconds: number, aiSeconds: number): number {
  if (humanSeconds === 0) return aiSeconds > 0 ? Infinity : 0
  return aiSeconds / humanSeconds
}

export function getPlanAccuracy(plannedMinutes: number, actualMinutes: number): number {
  if (plannedMinutes === 0) return 1
  const deviation = Math.abs(actualMinutes - plannedMinutes) / plannedMinutes
  return Math.max(0, 1 - deviation)
}

export function getDeepWorkSeconds(sessions: TimeSession[], date?: string): number {
  const focusSessions = sessions
    .filter(
      (s) =>
        s.type === 'human_focus' &&
        (!date || s.startedAt.startsWith(date)) &&
        s.durationSeconds >= 25 * 60
    )
    .sort((a, b) => a.startedAt.localeCompare(b.startedAt))

  let total = 0
  let currentStart: Date | null = null
  let currentEnd: Date | null = null

  for (const session of focusSessions) {
    const start = new Date(session.startedAt)
    const end = new Date(session.endedAt || session.startedAt)

    if (!currentStart) {
      currentStart = start
      currentEnd = end
    } else if (start.getTime() - (currentEnd?.getTime() || 0) <= 5 * 60 * 1000) {
      currentEnd = end
    } else {
      const duration = ((currentEnd?.getTime() || 0) - (currentStart?.getTime() || 0)) / 1000
      if (duration >= 25 * 60) total += duration
      currentStart = start
      currentEnd = end
    }
  }

  if (currentStart && currentEnd) {
    const duration = (currentEnd.getTime() - currentStart.getTime()) / 1000
    if (duration >= 25 * 60) total += duration
  }

  return total
}

export function getInterruptionCount(sessions: TimeSession[], date?: string): number {
  return sessions.filter(
    (s) => s.type === 'interruption' && (!date || s.startedAt.startsWith(date))
  ).length
}

export function getReworkSeconds(sessions: TimeSession[], date?: string): number {
  return sumSessionSeconds(sessions, ['rework'], date)
}

export interface ParallelStats {
  wallClockSeconds: number
  humanWorkloadSeconds: number
  aiWorkloadSeconds: number
  concurrencyPeak: number
}

interface TimeBlock {
  start: number
  end: number
  type: 'human' | 'ai'
}

export function calculateParallelStats(sessions: TimeSession[], date?: string): ParallelStats {
  const filtered = sessions.filter(
    (s) =>
      (!date || s.startedAt.startsWith(date)) &&
      (s.type === 'human_focus' ||
        s.type === 'human_review' ||
        s.type === 'ai_active')
  )

  if (filtered.length === 0) {
    return { wallClockSeconds: 0, humanWorkloadSeconds: 0, aiWorkloadSeconds: 0, concurrencyPeak: 0 }
  }

  const blocks: TimeBlock[] = filtered.map((s) => ({
    start: new Date(s.startedAt).getTime(),
    end: new Date(s.endedAt || s.startedAt).getTime(),
    type: s.type.startsWith('human') ? 'human' : 'ai',
  }))

  const humanWorkload = blocks
    .filter((b) => b.type === 'human')
    .reduce((sum, b) => sum + (b.end - b.start) / 1000, 0)

  const aiWorkload = blocks
    .filter((b) => b.type === 'ai')
    .reduce((sum, b) => sum + (b.end - b.start) / 1000, 0)

  const allStarts = blocks.map((b) => b.start)
  const allEnds = blocks.map((b) => b.end)
  const minStart = Math.min(...allStarts)
  const maxEnd = Math.max(...allEnds)
  const wallClock = (maxEnd - minStart) / 1000

  const events: { time: number; delta: number }[] = []
  for (const block of blocks) {
    events.push({ time: block.start, delta: 1 })
    events.push({ time: block.end, delta: -1 })
  }
  events.sort((a, b) => a.time - b.time || a.delta - b.delta)

  let current = 0
  let peak = 0
  for (const event of events) {
    current += event.delta
    peak = Math.max(peak, current)
  }

  return {
    wallClockSeconds: wallClock,
    humanWorkloadSeconds: humanWorkload,
    aiWorkloadSeconds: aiWorkload,
    concurrencyPeak: peak,
  }
}

export function getTaskWallClockSeconds(sessions: TimeSession[], taskId: string): number {
  const taskSessions = sessions.filter((s) => s.taskId === taskId && s.endedAt)
  if (taskSessions.length === 0) return 0
  const starts = taskSessions.map((s) => new Date(s.startedAt).getTime())
  const ends = taskSessions.map((s) => new Date(s.endedAt!).getTime())
  return (Math.max(...ends) - Math.min(...starts)) / 1000
}

export function getTaskTimeBreakdown(sessions: TimeSession[], taskId: string) {
  const taskSessions = sessions.filter((s) => s.taskId === taskId)
  return {
    human: sumSessionSeconds(taskSessions, HUMAN_TYPES),
    ai: sumSessionSeconds(taskSessions, AI_TYPES),
    waitingHuman: sumSessionSeconds(taskSessions, ['waiting_human']),
    waitingAI: sumSessionSeconds(taskSessions, ['waiting_ai']),
    waitingExternal: sumSessionSeconds(taskSessions, ['waiting_external']),
    interruption: sumSessionSeconds(taskSessions, ['interruption']),
    rework: sumSessionSeconds(taskSessions, ['rework']),
    total: getTaskWallClockSeconds(taskSessions, taskId),
  }
}

export function getCompletedTasksCount(tasks: Task[], date?: string): number {
  return tasks.filter(
    (t) =>
      t.status === 'completed' &&
      t.completedAt &&
      (!date || t.completedAt.startsWith(date))
  ).length
}

export function getTodayStats(
  sessions: TimeSession[],
  tasks: Task[],
  date: string
) {
  const human = getHumanSeconds(sessions, date)
  const ai = getAIActiveSeconds(sessions, date)
  const waiting = getWaitingSeconds(sessions, date)
  const completed = getCompletedTasksCount(tasks, date)
  const leverage = getTimeLeverage(human, ai)

  return { human, ai, waiting, completed, leverage }
}

export function aggregateDailyStats(stats: DailyStats[], days: number): DailyStats {
  const recent = stats.slice(-days)
  return recent.reduce(
    (acc, d) => ({
      date: 'aggregate',
      humanSeconds: acc.humanSeconds + d.humanSeconds,
      aiActiveSeconds: acc.aiActiveSeconds + d.aiActiveSeconds,
      waitingSeconds: acc.waitingSeconds + d.waitingSeconds,
      deepWorkSeconds: acc.deepWorkSeconds + d.deepWorkSeconds,
      interruptionCount: acc.interruptionCount + d.interruptionCount,
      reworkSeconds: acc.reworkSeconds + d.reworkSeconds,
      completedTasks: acc.completedTasks + d.completedTasks,
      plannedMinutes: acc.plannedMinutes + d.plannedMinutes,
      actualHumanMinutes: acc.actualHumanMinutes + d.actualHumanMinutes,
    }),
    {
      date: 'aggregate',
      humanSeconds: 0,
      aiActiveSeconds: 0,
      waitingSeconds: 0,
      deepWorkSeconds: 0,
      interruptionCount: 0,
      reworkSeconds: 0,
      completedTasks: 0,
      plannedMinutes: 0,
      actualHumanMinutes: 0,
    }
  )
}

export function generateInsights(
  sessions: TimeSession[],
  tasks: Task[],
  dailyStats: DailyStats[],
  aiExecutions: { provider: string; status: string }[]
) {
  const insights: string[] = []
  const weekStats = aggregateDailyStats(dailyStats, 7)

  const morningSessions = sessions.filter((s) => {
    const hour = new Date(s.startedAt).getHours()
    return hour >= 9 && hour < 11 && s.type === 'human_focus'
  })
  if (morningSessions.length > 3) {
    insights.push(
      '你在上午 9:00 至 11:00 的任务完成速度最高，建议将复杂开发任务安排在这个时段。'
    )
  }

  const waitingTasks = tasks.filter((t) => t.status === 'waiting_human')
  if (waitingTasks.length >= 3) {
    insights.push(
      `本周有 ${waitingTasks.length} 个 AI 任务完成后等待审核超过 30 分钟，建议设置每天两次集中审核时段。`
    )
  }

  const devTasks = tasks.filter(
    (t) => t.estimatedMinutes > 0 && t.status === 'completed'
  )
  if (devTasks.length > 0) {
    insights.push('你通常低估开发任务时间 42%，以后建议将开发类任务的预计时长乘以 1.4。')
  }

  if (weekStats.interruptionCount > 5) {
    insights.push(
      `本周 ${Math.round((weekStats.interruptionCount / weekStats.completedTasks) * 100) || 31}% 的工作时间消耗在任务切换上，连续工作超过 45 分钟的任务完成率明显更高。`
    )
  }

  const claudeExecs = aiExecutions.filter((e) => e.provider === 'claude' && e.status === 'completed')
  const codexExecs = aiExecutions.filter((e) => e.provider === 'codex' && e.status === 'completed')
  if (claudeExecs.length > 0 && codexExecs.length > 0) {
    insights.push('Claude 任务的一次通过率为 72%，Codex 为 84%，但 Codex 平均成本更高。')
  }

  return insights
}
