import { useParams, useNavigate } from 'react-router-dom'
import { Pause, X, Shield, Check, Eye } from 'lucide-react'
import { SubPageLayout } from '@/components/layout/SubPageLayout'
import { Button } from '@/components/ui/Button'
import { Card } from '@/components/ui/Card'
import { SectionTitle } from '@/components/ui/Common'
import { useStore } from '@/store/useStore'
import { formatDuration, formatCost } from '@/lib/format'
import { cn } from '@/lib/utils'

const statusLabels: Record<string, string> = {
  queued: '排队中',
  running: '执行中',
  waiting_auth: '等待授权',
  waiting_input: '等待用户输入',
  completed: '已完成',
  failed: '执行失败',
  cancelled: '已取消',
}

export function AIExecutionPage() {
  const { id } = useParams<{ id: string }>()
  const navigate = useNavigate()
  const {
    getTask, aiExecutions, pauseAIExecution, cancelAIExecution,
    authorizeAI, completeAIReview,
  } = useStore()

  const task = getTask(id!)
  const execution = aiExecutions.find((ae) => ae.taskId === id)

  if (!task) {
    return <SubPageLayout title="AI 执行"><p className="text-center text-text-muted py-12">任务不存在</p></SubPageLayout>
  }

  return (
    <SubPageLayout title="AI 执行">
      <div className="mb-6">
        <div className="flex items-center gap-2 mb-2">
          <span className="text-sm text-ai font-medium">{task.aiProvider}</span>
          <span className={cn(
            'text-xs px-2 py-0.5 rounded-full',
            execution?.status === 'running' ? 'bg-ai/20 text-ai animate-pulse-soft' :
            execution?.status === 'completed' ? 'bg-success/20 text-success' :
            'bg-text-muted/20 text-text-muted'
          )}>
            {statusLabels[execution?.status || 'queued']}
          </span>
        </div>
        <h2 className="text-lg font-medium text-text">{task.title}</h2>
        {execution?.currentStep && (
          <p className="text-sm text-text-secondary mt-2">当前步骤: {execution.currentStep}</p>
        )}
      </div>

      <div className="grid grid-cols-2 gap-2 mb-6">
        <Card>
          <p className="text-xs text-text-muted">已运行</p>
          <p className="text-lg font-mono text-ai">{formatDuration(execution?.activeSeconds || 0)}</p>
        </Card>
        <Card>
          <p className="text-xs text-text-muted">估算费用</p>
          <p className="text-lg font-mono text-text">{formatCost(execution?.estimatedCost || 0)}</p>
        </Card>
        <Card>
          <p className="text-xs text-text-muted">Token 使用</p>
          <p className="text-sm font-mono text-text">
            {(execution?.tokenInput || 0).toLocaleString()} / {(execution?.tokenOutput || 0).toLocaleString()}
          </p>
        </Card>
        <Card>
          <p className="text-xs text-text-muted">工具调用</p>
          <p className="text-lg font-mono text-text">{execution?.toolCallCount || 0}</p>
        </Card>
      </div>

      <SectionTitle>活动日志</SectionTitle>
      <Card className="mb-6 max-h-48 overflow-y-auto">
        {execution?.logs && execution.logs.length > 0 ? (
          <div className="space-y-2">
            {execution.logs.map((log, i) => (
              <div key={i} className="flex gap-3 text-sm">
                <span className="font-mono text-text-muted shrink-0">{log.time}</span>
                <span className="text-text-secondary">{log.message}</span>
              </div>
            ))}
          </div>
        ) : (
          <p className="text-sm text-text-muted text-center py-4">等待执行...</p>
        )}
      </Card>

      {execution?.resultSummary && (
        <Card className="mb-6 border-success/20">
          <p className="text-xs text-success mb-1">结果摘要</p>
          <p className="text-sm text-text-secondary">{execution.resultSummary}</p>
        </Card>
      )}

      {execution?.errorMessage && (
        <Card className="mb-6 border-danger/20">
          <p className="text-xs text-danger mb-1">错误</p>
          <p className="text-sm text-text-secondary">{execution.errorMessage}</p>
        </Card>
      )}

      <div className="space-y-2">
        {execution?.status === 'running' && (
          <div className="flex gap-2">
            <Button variant="secondary" className="flex-1" onClick={() => pauseAIExecution(task.id)}>
              <Pause size={16} /> 暂停
            </Button>
            <Button variant="danger" className="flex-1" onClick={() => { cancelAIExecution(task.id); navigate('/tasks') }}>
              <X size={16} /> 取消
            </Button>
          </div>
        )}
        {execution?.status === 'waiting_auth' && (
          <Button variant="accent" className="w-full" onClick={() => authorizeAI(task.id)}>
            <Shield size={16} /> 授权继续
          </Button>
        )}
        {(execution?.status === 'completed' || task.status === 'waiting_human') && (
          <div className="flex gap-2">
            <Button variant="accent" className="flex-1" onClick={() => { completeAIReview(task.id); navigate('/today') }}>
              <Check size={16} /> 审核完成
            </Button>
            <Button variant="secondary" className="flex-1" onClick={() => navigate(`/tasks/${task.id}`)}>
              <Eye size={16} /> 查看详情
            </Button>
          </div>
        )}
      </div>
    </SubPageLayout>
  )
}
