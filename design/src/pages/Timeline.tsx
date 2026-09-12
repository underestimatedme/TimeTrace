import { useState } from 'react'
import { AppLayout, PageLayout } from '@/components/layout/Layout'
import { Card } from '@/components/ui/Card'
import { SectionTitle, MetricCard } from '@/components/ui/Common'
import { useStore } from '@/store/useStore'
import { formatTime, formatDuration } from '@/lib/format'
import { calculateParallelStats } from '@/lib/stats'
import { format, subDays } from 'date-fns'
import { cn } from '@/lib/utils'
import type { TimeSessionType } from '@/types'
import { sessionEndMillis, useNow } from '@/lib/time'

type ViewRange = 'today' | 'week'

const typeColors: Record<TimeSessionType, string> = {
  human_focus: 'bg-accent/60',
  human_review: 'bg-accent/40',
  ai_active: 'bg-ai/60',
  ai_idle: 'bg-ai/30',
  waiting_human: 'bg-warning/50',
  waiting_ai: 'bg-warning/30',
  waiting_external: 'bg-warning/20',
  interruption: 'bg-danger/40',
  rework: 'bg-danger/30',
}

const typeLabels: Record<TimeSessionType, string> = {
  human_focus: '我',
  human_review: '我·审核',
  ai_active: 'AI',
  ai_idle: 'AI·空闲',
  waiting_human: '等待我',
  waiting_ai: '等待 AI',
  waiting_external: '等待外部',
  interruption: '中断',
  rework: '返工',
}

export function TimelinePage() {
  const { timeSessions, tasks } = useStore()
  const [range, setRange] = useState<ViewRange>('today')
  const nowMillis = useNow()

  const today = format(new Date(), 'yyyy-MM-dd')
  const weekStart = format(subDays(new Date(), 6), 'yyyy-MM-dd')

  const filtered = timeSessions
    .filter((s) => {
      if (range === 'today') return s.startedAt.startsWith(today)
      return s.startedAt >= weekStart
    })
    .sort((a, b) => a.startedAt.localeCompare(b.startedAt))

  const parallel = calculateParallelStats(
    timeSessions,
    range === 'today' ? today : undefined
  )

  const getTaskTitle = (taskId: string) => tasks.find((t) => t.id === taskId)?.title || '未知任务'

  const dayStart = filtered.length > 0
    ? new Date(filtered[0].startedAt).setHours(0, 0, 0, 0)
    : new Date().setHours(0, 0, 0, 0)
  const dayEnd = dayStart + 24 * 60 * 60 * 1000

  const getPosition = (start: string, end?: string) => {
    const s = new Date(start).getTime()
    const e = sessionEndMillis(end, nowMillis)
    const left = ((s - dayStart) / (dayEnd - dayStart)) * 100
    const width = Math.max(((e - s) / (dayEnd - dayStart)) * 100, 0.5)
    return { left: `${left}%`, width: `${width}%` }
  }

  return (
    <AppLayout>
      <PageLayout>
        <h1 className="text-xl font-medium text-text mb-4">时间流</h1>

        <div className="flex gap-2 mb-4">
          {(['today', 'week'] as ViewRange[]).map((r) => (
            <button
              key={r}
              onClick={() => setRange(r)}
              className={cn(
                'px-4 py-1.5 rounded-full text-xs transition-colors',
                range === r ? 'bg-accent/20 text-accent' : 'bg-bg-card text-text-secondary'
              )}
            >
              {r === 'today' ? '今天' : '本周'}
            </button>
          ))}
        </div>

        <div className="grid grid-cols-2 gap-2 mb-6">
          <MetricCard label="实际经过" value={formatDuration(parallel.wallClockSeconds)} />
          <MetricCard label="并发峰值" value={`${parallel.concurrencyPeak}`} />
          <MetricCard label="人工工作量" value={formatDuration(parallel.humanWorkloadSeconds)} />
          <MetricCard label="AI 工作量" value={formatDuration(parallel.aiWorkloadSeconds)} />
        </div>

        <SectionTitle>时间线</SectionTitle>
        {filtered.length === 0 ? (
          <Card>
            <p className="text-sm text-text-muted text-center py-8">暂无时间记录</p>
          </Card>
        ) : (
          <div className="space-y-1">
            {filtered.map((session) => {
              const pos = getPosition(session.startedAt, session.endedAt)
              return (
                <div key={session.id} className="relative">
                  <div className="flex items-center gap-3 py-2">
                    <span className="text-xs font-mono text-text-muted w-24 shrink-0">
                      {formatTime(session.startedAt)}
                      {session.endedAt && `–${formatTime(session.endedAt)}`}
                    </span>
                    <div className="flex-1 relative h-8 bg-bg-elevated rounded-lg overflow-hidden">
                      <div
                        className={cn('absolute top-1 bottom-1 rounded-md', typeColors[session.type])}
                        style={pos}
                      />
                    </div>
                  </div>
                  <div className="flex items-center gap-2 pl-28 -mt-1 mb-2">
                    <span className={cn('text-xs px-1.5 py-0.5 rounded', typeColors[session.type], 'text-bg')}>
                      {typeLabels[session.type]}
                    </span>
                    <span className="text-xs text-text-secondary truncate">
                      {getTaskTitle(session.taskId)}
                    </span>
                    <span className="text-xs text-text-muted ml-auto">
                      {formatDuration(session.durationSeconds)}
                    </span>
                  </div>
                </div>
              )
            })}
          </div>
        )}

        <SectionTitle className="mt-6">图例</SectionTitle>
        <div className="flex flex-wrap gap-2">
          {Object.entries(typeLabels).map(([type, label]) => (
            <div key={type} className="flex items-center gap-1.5">
              <div className={cn('w-3 h-3 rounded', typeColors[type as TimeSessionType])} />
              <span className="text-xs text-text-muted">{label}</span>
            </div>
          ))}
        </div>
      </PageLayout>
    </AppLayout>
  )
}
