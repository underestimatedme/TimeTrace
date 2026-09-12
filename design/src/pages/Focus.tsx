import { useState } from 'react'
import { useParams, useNavigate } from 'react-router-dom'
import { Pause, Check, AlertTriangle } from 'lucide-react'
import { SubPageLayout } from '@/components/layout/SubPageLayout'
import { Button } from '@/components/ui/Button'
import { Card } from '@/components/ui/Card'
import { useStore } from '@/store/useStore'
import { formatDuration } from '@/lib/format'
import { getHumanSeconds } from '@/lib/stats'
import { format } from 'date-fns'
import { elapsedSeconds, useNow } from '@/lib/time'

const pauseReasons = ['临时休息', '收到消息', '开会', '等待 AI', '切换任务', '其他']

export function FocusPage() {
  const { id } = useParams<{ id: string }>()
  const navigate = useNavigate()
  const { getTask, getProject, activeFocus, pauseFocus, completeFocus, markInterruption, timeSessions } = useStore()
  const [showPauseMenu, setShowPauseMenu] = useState(false)
  const [note, setNote] = useState('')
  const nowMillis = useNow()

  const task = getTask(id!)
  if (!task) return <SubPageLayout title="专注"><p className="text-center text-text-muted py-12">任务不存在</p></SubPageLayout>

  const project = getProject(task.projectId)
  const today = format(new Date(), 'yyyy-MM-dd')
  const todayTotal = getHumanSeconds(timeSessions, today)

  const elapsed = activeFocus?.taskId === task.id
    ? elapsedSeconds(activeFocus.startedAt, activeFocus.accumulatedSeconds, nowMillis)
    : 0
  const remaining = Math.max(0, task.estimatedMinutes * 60 - elapsed)
  const progress = task.estimatedMinutes > 0 ? (elapsed / (task.estimatedMinutes * 60)) * 100 : 0

  const handlePause = (reason: string) => {
    pauseFocus(reason)
    setShowPauseMenu(false)
    navigate('/today')
  }

  return (
    <SubPageLayout title="专注计时">
      <div className="flex flex-col items-center py-8">
        {project && (
          <p className="text-xs text-text-muted mb-2">{project.icon} {project.name}</p>
        )}
        <h2 className="text-lg font-medium text-text text-center mb-8">{task.title}</h2>

        <div className="relative w-48 h-48 mb-8">
          <svg className="w-full h-full -rotate-90" viewBox="0 0 100 100">
            <circle cx="50" cy="50" r="45" fill="none" stroke="var(--color-border)" strokeWidth="3" />
            <circle
              cx="50" cy="50" r="45" fill="none" stroke="var(--color-accent)" strokeWidth="3"
              strokeDasharray={`${progress * 2.83} 283`}
              strokeLinecap="round"
              className="transition-all duration-1000"
            />
          </svg>
          <div className="absolute inset-0 flex flex-col items-center justify-center">
            <p className="text-3xl font-mono text-accent">{formatDuration(elapsed)}</p>
            <p className="text-xs text-text-muted mt-1">剩余 {formatDuration(remaining)}</p>
          </div>
        </div>

        <Card className="w-full mb-6">
          <p className="text-xs text-text-muted">今日累计专注</p>
          <p className="text-lg font-mono text-text">{formatDuration(todayTotal)}</p>
        </Card>
      </div>

      {showPauseMenu ? (
        <div className="space-y-2">
          <p className="text-sm text-text-secondary mb-3">选择暂停原因</p>
          {pauseReasons.map((reason) => (
            <Button key={reason} variant="secondary" className="w-full" onClick={() => handlePause(reason)}>
              {reason}
            </Button>
          ))}
          <Button variant="ghost" className="w-full" onClick={() => setShowPauseMenu(false)}>取消</Button>
        </div>
      ) : (
        <div className="space-y-2">
          <div className="flex gap-2">
            <Button variant="secondary" className="flex-1" onClick={() => setShowPauseMenu(true)}>
              <Pause size={16} /> 暂停
            </Button>
            <Button variant="accent" className="flex-1" onClick={() => { completeFocus(note); navigate('/today') }}>
              <Check size={16} /> 完成
            </Button>
          </div>
          <Button variant="ghost" className="w-full" onClick={() => { markInterruption('被打断'); setShowPauseMenu(true) }}>
            <AlertTriangle size={16} /> 标记被打断
          </Button>
          <textarea
            value={note}
            onChange={(e) => setNote(e.target.value)}
            placeholder="添加备注..."
            className="w-full bg-bg-elevated border border-border rounded-xl px-4 py-2.5 text-sm text-text mt-2 resize-none"
            rows={2}
          />
        </div>
      )}
    </SubPageLayout>
  )
}
