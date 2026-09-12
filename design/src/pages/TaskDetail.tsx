import { useParams, useNavigate } from 'react-router-dom'
import { SubPageLayout } from '@/components/layout/SubPageLayout'
import { Card } from '@/components/ui/Card'
import { Button } from '@/components/ui/Button'
import { StatusBadge, ExecutorBadge } from '@/components/ui/Badge'
import { SectionTitle } from '@/components/ui/Common'
import { useStore } from '@/store/useStore'
import { formatDuration, formatTime, formatCost } from '@/lib/format'
import { getTaskTimeBreakdown } from '@/lib/stats'

export function TaskDetailPage() {
  const { id } = useParams<{ id: string }>()
  const navigate = useNavigate()
  const { getTask, getProject, getGoal, timeSessions, aiExecutions, startFocus, completeAIReview } = useStore()

  const task = getTask(id!)
  if (!task) {
    return (
      <SubPageLayout title="任务详情">
        <p className="text-text-muted text-center py-12">任务不存在</p>
      </SubPageLayout>
    )
  }

  const project = getProject(task.projectId)
  const goal = task.goalId ? getGoal(task.goalId) : undefined
  const breakdown = getTaskTimeBreakdown(timeSessions, task.id)
  const aiExec = aiExecutions.find((ae) => ae.taskId === task.id)

  const taskSessions = timeSessions
    .filter((s) => s.taskId === task.id)
    .sort((a, b) => a.startedAt.localeCompare(b.startedAt))

  const timelineEvents = [
    { time: task.createdAt, label: '创建任务' },
    ...taskSessions.map((s) => ({
      time: s.startedAt,
      label: `${s.executor === 'human' ? '我' : s.executor}: ${s.type.replace(/_/g, ' ')}`,
    })),
    ...(task.completedAt ? [{ time: task.completedAt, label: '任务完成' }] : []),
  ].sort((a, b) => a.time.localeCompare(b.time))

  return (
    <SubPageLayout title="任务详情">
      <div className="mb-6">
        <h2 className="text-lg font-medium text-text mb-2">{task.title}</h2>
        <div className="flex items-center gap-2 flex-wrap mb-3">
          <StatusBadge status={task.status} />
          <ExecutorBadge type={task.executorType} provider={task.aiProvider} />
        </div>
        {task.description && (
          <p className="text-sm text-text-secondary leading-relaxed">{task.description}</p>
        )}
      </div>

      <div className="grid grid-cols-2 gap-2 mb-6">
        <Card>
          <p className="text-xs text-text-muted">预计时间</p>
          <p className="text-sm font-mono text-text">{task.estimatedMinutes} 分钟</p>
        </Card>
        <Card>
          <p className="text-xs text-text-muted">实际人工</p>
          <p className="text-sm font-mono text-accent">{formatDuration(breakdown.human)}</p>
        </Card>
        {goal && (
          <Card className="col-span-2">
            <p className="text-xs text-text-muted">所属目标</p>
            <p className="text-sm text-text">{goal.title}</p>
          </Card>
        )}
        {project && (
          <Card className="col-span-2">
            <p className="text-xs text-text-muted">所属项目</p>
            <p className="text-sm text-text">{project.icon} {project.name}</p>
          </Card>
        )}
      </div>

      <SectionTitle>流程时间线</SectionTitle>
      <div className="relative pl-4 mb-6">
        <div className="absolute left-1.5 top-2 bottom-2 w-px bg-border" />
        {timelineEvents.map((event, i) => (
          <div key={i} className="relative pb-4">
            <div className="absolute -left-2.5 top-1.5 w-2 h-2 rounded-full bg-accent" />
            <p className="text-xs font-mono text-text-muted">{formatTime(event.time)}</p>
            <p className="text-sm text-text">{event.label}</p>
          </div>
        ))}
      </div>

      <SectionTitle>时间拆分</SectionTitle>
      <div className="grid grid-cols-2 gap-2 mb-6">
        <Card><p className="text-xs text-text-muted">人工投入</p><p className="text-sm font-mono text-accent">{formatDuration(breakdown.human)}</p></Card>
        <Card><p className="text-xs text-text-muted">AI 活跃</p><p className="text-sm font-mono text-ai">{formatDuration(breakdown.ai)}</p></Card>
        <Card><p className="text-xs text-text-muted">等待人工</p><p className="text-sm font-mono text-warning">{formatDuration(breakdown.waitingHuman)}</p></Card>
        <Card><p className="text-xs text-text-muted">总历时</p><p className="text-sm font-mono text-text">{formatDuration(breakdown.total)}</p></Card>
      </div>

      {aiExec && (
        <>
          <SectionTitle>AI 执行信息</SectionTitle>
          <Card className="mb-6">
            <div className="grid grid-cols-2 gap-3 text-sm">
              <div><p className="text-xs text-text-muted">提供商</p><p className="text-ai">{aiExec.provider}</p></div>
              <div><p className="text-xs text-text-muted">模型</p><p>{aiExec.model}</p></div>
              <div><p className="text-xs text-text-muted">Token 输入</p><p className="font-mono">{aiExec.tokenInput.toLocaleString()}</p></div>
              <div><p className="text-xs text-text-muted">Token 输出</p><p className="font-mono">{aiExec.tokenOutput.toLocaleString()}</p></div>
              <div><p className="text-xs text-text-muted">估算费用</p><p className="font-mono">{formatCost(aiExec.estimatedCost)}</p></div>
              <div><p className="text-xs text-text-muted">工具调用</p><p className="font-mono">{aiExec.toolCallCount}</p></div>
              <div><p className="text-xs text-text-muted">修改文件</p><p className="font-mono">{aiExec.filesChanged}</p></div>
            </div>
            {aiExec.resultSummary && (
              <p className="text-sm text-text-secondary mt-3 pt-3 border-t border-border">{aiExec.resultSummary}</p>
            )}
          </Card>
        </>
      )}

      <div className="flex gap-2">
        {task.status === 'waiting_human' && (
          <Button variant="accent" className="flex-1" onClick={() => completeAIReview(task.id)}>
            审核完成
          </Button>
        )}
        {['ready', 'planned', 'inbox', 'paused'].includes(task.status) && (
          <Button variant="accent" className="flex-1" onClick={() => { startFocus(task.id); navigate(`/focus/${task.id}`) }}>
            开始执行
          </Button>
        )}
        {task.status === 'ai_running' && (
          <Button variant="secondary" className="flex-1" onClick={() => navigate(`/ai/${task.id}`)}>
            查看 AI 执行
          </Button>
        )}
      </div>
    </SubPageLayout>
  )
}
