import { cn } from '@/lib/utils'
import type { TaskStatus, ExecutorType, AIProvider } from '@/types'

const statusLabels: Record<TaskStatus, string> = {
  inbox: '收件箱',
  planned: '已计划',
  ready: '待开始',
  human_running: '进行中',
  ai_queued: 'AI 排队',
  ai_running: 'AI 执行中',
  waiting_human: '等待我',
  waiting_external: '等待外部',
  paused: '已暂停',
  completed: '已完成',
  failed: '失败',
  cancelled: '已取消',
}

const statusColors: Record<TaskStatus, string> = {
  inbox: 'bg-text-muted/20 text-text-muted',
  planned: 'bg-ai/20 text-ai',
  ready: 'bg-accent/20 text-accent',
  human_running: 'bg-accent/30 text-accent',
  ai_queued: 'bg-ai-dim/20 text-ai',
  ai_running: 'bg-ai/30 text-ai',
  waiting_human: 'bg-warning/20 text-warning',
  waiting_external: 'bg-warning/20 text-warning',
  paused: 'bg-text-muted/20 text-text-muted',
  completed: 'bg-success/20 text-success',
  failed: 'bg-danger/20 text-danger',
  cancelled: 'bg-text-muted/20 text-text-muted',
}

export function StatusBadge({ status }: { status: TaskStatus }) {
  return (
    <span className={cn('inline-flex px-2 py-0.5 rounded-md text-xs font-medium', statusColors[status])}>
      {statusLabels[status]}
    </span>
  )
}

const executorLabels: Record<ExecutorType, string> = {
  human: '我',
  ai: 'AI',
  collaboration: '协作',
  external: '外部',
}

const providerLabels: Record<AIProvider, string> = {
  claude: 'Claude',
  codex: 'Codex',
  chatgpt: 'ChatGPT',
  gemini: 'Gemini',
  other: '其他',
}

export function ExecutorBadge({
  type,
  provider,
}: {
  type: ExecutorType
  provider?: AIProvider
}) {
  const label =
    type === 'ai' || type === 'collaboration'
      ? provider ? providerLabels[provider] : 'AI'
      : executorLabels[type]

  const color =
    type === 'human'
      ? 'text-accent'
      : type === 'ai'
        ? 'text-ai'
        : type === 'collaboration'
          ? 'text-accent'
          : 'text-text-secondary'

  return <span className={cn('text-xs', color)}>{label}</span>
}

const priorityLabels = { low: '低', medium: '中', high: '高', urgent: '紧急' }
const priorityColors = {
  low: 'text-text-muted',
  medium: 'text-text-secondary',
  high: 'text-accent',
  urgent: 'text-danger',
}

export function PriorityBadge({ priority }: { priority: keyof typeof priorityLabels }) {
  return (
    <span className={cn('text-xs', priorityColors[priority])}>
      {priorityLabels[priority]}
    </span>
  )
}
