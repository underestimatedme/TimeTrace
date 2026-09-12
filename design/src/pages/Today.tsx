import { useNavigate } from 'react-router-dom'
import { Pause, Check, ChevronRight, Clock, Zap } from 'lucide-react'
import { AppLayout, PageLayout } from '@/components/layout/Layout'
import { Card } from '@/components/ui/Card'
import { Button } from '@/components/ui/Button'
import { SectionTitle, ProgressBar, MetricCard } from '@/components/ui/Common'
import { useStore } from '@/store/useStore'
import { formatDuration, formatLeverage, getGreeting, formatTime } from '@/lib/format'
import { getTodayStats } from '@/lib/stats'
import { format as formatDate } from 'date-fns'
import { zhCN } from 'date-fns/locale'
import { elapsedSeconds, useNow } from '@/lib/time'

export function TodayPage() {
  const navigate = useNavigate()
  const {
    tasks,
    projects,
    timeSessions,
    settings,
    activeFocus,
    getRunningHumanTask,
    getRunningAITasks,
    getWaitingHumanTasks,
    completeFocus,
    completeAIReview,
  } = useStore()

  const today = formatDate(new Date(), 'yyyy-MM-dd')
  const todayDisplay = formatDate(new Date(), 'M月d日 EEEE', { locale: zhCN })
  const nowMillis = useNow()
  const stats = getTodayStats(timeSessions, tasks, today)

  const humanTask = getRunningHumanTask()
  const aiTasks = getRunningAITasks()
  const waitingTasks = getWaitingHumanTasks()

  const completedToday = tasks.filter(
    (t) => t.status === 'completed' && t.completedAt?.startsWith(today)
  ).length
  const totalToday = tasks.filter(
    (t) => t.dueDate?.startsWith(today) || t.scheduledStart?.startsWith(today)
  ).length
  const progress = totalToday > 0 ? (completedToday / totalToday) * 100 : 0

  const upcoming = tasks
    .filter(
      (t) =>
        t.scheduledStart?.startsWith(today) &&
        !['completed', 'cancelled', 'failed'].includes(t.status)
    )
    .sort((a, b) => (a.scheduledStart || '').localeCompare(b.scheduledStart || ''))

  const getFocusDuration = () => {
    if (!activeFocus) return 0
    return elapsedSeconds(activeFocus.startedAt, activeFocus.accumulatedSeconds, nowMillis)
  }

  const getAIDuration = (taskId: string) => {
    const session = timeSessions.find(
      (s) => s.taskId === taskId && s.type === 'ai_active' && !s.endedAt
    )
    return session?.durationSeconds || 0
  }

  const getWaitingDuration = (taskId: string) => {
    const session = timeSessions.find(
      (s) => s.taskId === taskId && s.type === 'waiting_human' && !s.endedAt
    )
    if (!session) return 0
    return elapsedSeconds(session.startedAt, 0, nowMillis)
  }

  return (
    <AppLayout>
      <PageLayout>
        <header className="mb-6">
          <p className="text-xs text-text-muted mb-1">{todayDisplay}</p>
          <h1 className="text-2xl font-light text-text">{getGreeting()}，{settings.name}</h1>
          <div className="flex items-center gap-4 mt-3">
            <div className="flex-1">
              <div className="flex justify-between text-xs text-text-secondary mb-1">
                <span>今日进度</span>
                <span>{completedToday}/{totalToday || '—'}</span>
              </div>
              <ProgressBar value={progress} />
            </div>
            <div className="text-right">
              <p className="text-xs text-text-muted">连续专注</p>
              <p className="text-sm font-mono text-accent">{settings.streakDays} 天</p>
            </div>
          </div>
        </header>

        <section className="mb-6">
          <SectionTitle>现在</SectionTitle>
          {humanTask || aiTasks.length > 0 ? (
            <div className="space-y-3">
              {humanTask && (
                <Card className="border-accent/20">
                  <div className="flex items-start justify-between">
                    <div>
                      <p className="text-xs text-accent mb-1">我正在进行</p>
                      <h3 className="text-sm font-medium text-text">{humanTask.title}</h3>
                      <p className="text-xs text-text-muted mt-1 flex items-center gap-1">
                        <Clock size={12} />
                        已专注 {formatDuration(getFocusDuration())}
                      </p>
                    </div>
                  </div>
                  <div className="flex gap-2 mt-3">
                    <Button variant="secondary" size="sm" onClick={() => navigate(`/focus/${humanTask.id}`)}>
                      <Pause size={14} /> 暂停
                    </Button>
                    <Button variant="accent" size="sm" onClick={() => completeFocus()}>
                      <Check size={14} /> 完成
                    </Button>
                    <Button variant="ghost" size="sm" onClick={() => navigate(`/tasks/${humanTask.id}`)}>
                      详情
                    </Button>
                  </div>
                </Card>
              )}
              {aiTasks.map((task) => (
                <Card key={task.id} className="border-ai/20">
                  <div>
                    <p className="text-xs text-ai mb-1">{task.aiProvider} 正在进行</p>
                    <h3 className="text-sm font-medium text-text">{task.title}</h3>
                    <p className="text-xs text-text-muted mt-1 flex items-center gap-1">
                      <Clock size={12} />
                      已运行 {formatDuration(getAIDuration(task.id))}
                    </p>
                  </div>
                  <div className="flex gap-2 mt-3">
                    <Button variant="ghost" size="sm" onClick={() => navigate(`/ai/${task.id}`)}>
                      查看执行
                    </Button>
                  </div>
                </Card>
              ))}
            </div>
          ) : (
            <Card>
              <p className="text-sm text-text-muted text-center py-4">当前没有进行中的任务</p>
            </Card>
          )}
        </section>

        {waitingTasks.length > 0 && (
          <section className="mb-6">
            <SectionTitle>等待你</SectionTitle>
            <div className="space-y-3">
              {waitingTasks.map((task) => (
                <Card key={task.id} className="border-warning/20">
                  <p className="text-xs text-warning mb-1">
                    {task.aiProvider} 已完成，等待审核 {formatDuration(getWaitingDuration(task.id))}
                  </p>
                  <h3 className="text-sm font-medium text-text">{task.title}</h3>
                  <div className="flex gap-2 mt-3">
                    <Button variant="accent" size="sm" onClick={() => navigate(`/tasks/${task.id}`)}>
                      立即审核
                    </Button>
                    <Button variant="secondary" size="sm" onClick={() => completeAIReview(task.id)}>
                      标记完成
                    </Button>
                  </div>
                </Card>
              ))}
            </div>
          </section>
        )}

        <section className="mb-6">
          <SectionTitle>接下来</SectionTitle>
          {upcoming.length > 0 ? (
            <div className="space-y-2">
              {upcoming.slice(0, 5).map((task) => {
                const project = projects.find((p) => p.id === task.projectId)
                const time = task.scheduledStart ? formatTime(task.scheduledStart) : ''
                return (
                  <div
                    key={task.id}
                    onClick={() => navigate(`/tasks/${task.id}`)}
                    className="flex items-center gap-3 py-2.5 px-3 rounded-xl hover:bg-bg-hover cursor-pointer transition-colors"
                  >
                    <span className="text-xs font-mono text-accent w-12">{time}</span>
                    <div className="flex-1 min-w-0">
                      <p className="text-sm text-text truncate">{task.title}</p>
                      {project && <p className="text-xs text-text-muted">{project.name}</p>}
                    </div>
                    <ChevronRight size={16} className="text-text-muted" />
                  </div>
                )
              })}
            </div>
          ) : (
            <Card>
              <p className="text-sm text-text-muted text-center py-4">今天暂无计划任务</p>
            </Card>
          )}
        </section>

        <section className="mb-6">
          <SectionTitle>今日数据摘要</SectionTitle>
          <div className="grid grid-cols-2 gap-2">
            <MetricCard label="人工投入" value={formatDuration(stats.human)} />
            <MetricCard label="AI 活跃" value={formatDuration(stats.ai)} />
            <MetricCard label="等待损耗" value={formatDuration(stats.waiting)} />
            <MetricCard label="完成任务" value={`${stats.completed}`} />
          </div>
          <Card className="mt-2 border-accent/10">
            <div className="flex items-center justify-between">
              <div>
                <p className="text-xs text-text-muted">时间杠杆</p>
                <p className="text-xl font-mono text-accent mt-0.5">{formatLeverage(stats.leverage)}</p>
              </div>
              <Zap size={20} className="text-accent/40" />
            </div>
            <p className="text-xs text-text-muted mt-2">AI 活跃时间 ÷ 人工投入时间</p>
          </Card>
        </section>
      </PageLayout>
    </AppLayout>
  )
}
