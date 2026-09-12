import { useNavigate } from 'react-router-dom'
import { ArrowLeft } from 'lucide-react'
import { cn } from '@/lib/utils'
import { StatusBadge, ExecutorBadge, PriorityBadge } from '@/components/ui/Badge'
import type { Task, Project } from '@/types'

export function SubPageLayout({
  title,
  children,
  action,
  onBack,
}: {
  title: string
  children: React.ReactNode
  action?: React.ReactNode
  onBack?: () => void
}) {
  const navigate = useNavigate()

  return (
    <div className="app-shell flex flex-col animate-fade-in">
      <header className="flex items-center justify-between px-4 py-3 border-b border-border bg-bg/80 backdrop-blur-md sticky top-0 z-40">
        <button
          onClick={onBack || (() => navigate(-1))}
          className="flex items-center gap-1 text-text-secondary hover:text-text transition-colors"
        >
          <ArrowLeft size={20} />
          <span className="text-sm">返回</span>
        </button>
        <h1 className="text-sm font-medium text-text absolute left-1/2 -translate-x-1/2">{title}</h1>
        <div className="min-w-[60px] flex justify-end">{action}</div>
      </header>
      <main className="flex-1 scroll-area px-4 py-4 pb-8">{children}</main>
    </div>
  )
}

export function TaskCard({
  task,
  project,
  onClick,
  showMenu,
}: {
  task: Pick<Task, 'id' | 'title' | 'status' | 'executorType' | 'aiProvider' | 'priority' | 'estimatedMinutes' | 'dueDate'>
  project?: Pick<Project, 'name' | 'color' | 'icon'>
  onClick?: () => void
  showMenu?: React.ReactNode
}) {
  const navigate = useNavigate()

  return (
    <div
      onClick={onClick || (() => navigate(`/tasks/${task.id}`))}
      className={cn(
        'bg-bg-card rounded-2xl border border-border p-4 cursor-pointer hover:bg-bg-hover transition-colors',
        task.status === 'human_running' && 'border-accent/30',
        task.status === 'ai_running' && 'border-ai/30'
      )}
    >
      <div className="flex items-start justify-between gap-2 mb-2">
        <div className="flex-1 min-w-0">
          <h3 className="text-sm font-medium text-text truncate">{task.title}</h3>
          {project && (
            <p className="text-xs text-text-muted mt-0.5">
              {project.icon} {project.name}
            </p>
          )}
        </div>
        {showMenu}
      </div>
      <div className="flex items-center gap-2 flex-wrap">
        <StatusBadge status={task.status} />
        <ExecutorBadge type={task.executorType} provider={task.aiProvider} />
        <PriorityBadge priority={task.priority} />
        <span className="text-xs text-text-muted ml-auto">{task.estimatedMinutes} 分钟</span>
      </div>
    </div>
  )
}
