import { useState } from 'react'
import { useNavigate } from 'react-router-dom'
import { MoreVertical, Play, Pause, Check, Bot, Trash2, Plus } from 'lucide-react'
import { AppLayout, PageLayout } from '@/components/layout/Layout'
import { TaskCard } from '@/components/layout/SubPageLayout'
import { Button } from '@/components/ui/Button'
import { EmptyState } from '@/components/ui/Common'
import { useStore } from '@/store/useStore'
import type { TaskStatus } from '@/types'
import { cn } from '@/lib/utils'

type Filter = 'all' | 'pending' | 'human' | 'ai' | 'waiting' | 'completed'

const filters: { key: Filter; label: string }[] = [
  { key: 'all', label: '全部' },
  { key: 'pending', label: '待处理' },
  { key: 'human', label: '我来做' },
  { key: 'ai', label: 'AI 执行' },
  { key: 'waiting', label: '等待我' },
  { key: 'completed', label: '已完成' },
]

const pendingStatuses: TaskStatus[] = ['inbox', 'planned', 'ready', 'human_running', 'ai_queued', 'ai_running', 'waiting_human', 'waiting_external', 'paused']

export function TasksPage() {
  const navigate = useNavigate()
  const { tasks, projects, startFocus, setTaskStatus, deleteTask, startAIExecution, pauseFocus } = useStore()
  const [filter, setFilter] = useState<Filter>('all')
  const [projectFilter, setProjectFilter] = useState<string>('all')
  const [menuOpen, setMenuOpen] = useState<string | null>(null)

  const filtered = tasks.filter((t) => {
    if (projectFilter !== 'all' && t.projectId !== projectFilter) return false
    switch (filter) {
      case 'pending': return pendingStatuses.includes(t.status)
      case 'human': return t.executorType === 'human' || t.executorType === 'collaboration'
      case 'ai': return t.executorType === 'ai' || t.status === 'ai_running' || t.status === 'ai_queued'
      case 'waiting': return t.status === 'waiting_human'
      case 'completed': return t.status === 'completed'
      default: return true
    }
  })

  const handleAction = (taskId: string, action: string) => {
    setMenuOpen(null)
    const task = tasks.find((t) => t.id === taskId)
    if (!task) return

    switch (action) {
      case 'start':
        if (task.executorType === 'ai') {
          startAIExecution(taskId)
          navigate(`/ai/${taskId}`)
        } else {
          startFocus(taskId)
          navigate(`/focus/${taskId}`)
        }
        break
      case 'pause':
        pauseFocus()
        setTaskStatus(taskId, 'paused')
        break
      case 'complete':
        setTaskStatus(taskId, 'completed')
        break
      case 'delegate':
        startAIExecution(taskId)
        break
      case 'delete':
        deleteTask(taskId)
        break
    }
  }

  return (
    <AppLayout>
      <PageLayout>
        <div className="flex items-center justify-between mb-4">
          <h1 className="text-xl font-medium text-text">任务</h1>
          <button
            onClick={() => navigate('/tasks/new')}
            className="flex items-center justify-center w-9 h-9 rounded-xl bg-accent/15 text-accent hover:bg-accent/25 transition-colors"
            aria-label="新建任务"
          >
            <Plus size={20} strokeWidth={1.5} />
          </button>
        </div>

        <div className="flex gap-2 overflow-x-auto pb-2 mb-3 -mx-1 px-1 scrollbar-hide">
          {filters.map((f) => (
            <button
              key={f.key}
              onClick={() => setFilter(f.key)}
              className={cn(
                'px-3 py-1.5 rounded-full text-xs whitespace-nowrap transition-colors',
                filter === f.key ? 'bg-accent/20 text-accent' : 'bg-bg-card text-text-secondary'
              )}
            >
              {f.label}
            </button>
          ))}
        </div>

        <div className="flex gap-2 overflow-x-auto pb-3 mb-4 -mx-1 px-1">
          <button
            onClick={() => setProjectFilter('all')}
            className={cn(
              'px-3 py-1 rounded-lg text-xs whitespace-nowrap border transition-colors',
              projectFilter === 'all' ? 'border-accent/50 text-accent' : 'border-border text-text-muted'
            )}
          >
            全部项目
          </button>
          {projects.map((p) => (
            <button
              key={p.id}
              onClick={() => setProjectFilter(p.id)}
              className={cn(
                'px-3 py-1 rounded-lg text-xs whitespace-nowrap border transition-colors',
                projectFilter === p.id ? 'border-accent/50 text-accent' : 'border-border text-text-muted'
              )}
            >
              {p.icon} {p.name}
            </button>
          ))}
        </div>

        {filtered.length === 0 ? (
          <EmptyState
            icon="📋"
            title="暂无任务"
            description="点击右上角 + 创建新任务"
            action={
              <Button variant="accent" onClick={() => navigate('/tasks/new')}>
                新建任务
              </Button>
            }
          />
        ) : (
          <div className="space-y-3">
            {filtered.map((task) => {
              const project = projects.find((p) => p.id === task.projectId)
              return (
                <div key={task.id} className="relative">
                  <TaskCard
                    task={task}
                    project={project}
                    showMenu={
                      <button
                        onClick={(e) => {
                          e.stopPropagation()
                          setMenuOpen(menuOpen === task.id ? null : task.id)
                        }}
                        className="p-1 text-text-muted hover:text-text"
                      >
                        <MoreVertical size={16} />
                      </button>
                    }
                  />
                  {menuOpen === task.id && (
                    <div className="absolute right-2 top-12 z-10 bg-bg-elevated border border-border rounded-xl shadow-lg py-1 min-w-[140px]">
                      {['ready', 'planned', 'inbox', 'paused'].includes(task.status) && (
                        <button className="w-full px-4 py-2 text-left text-xs text-text hover:bg-bg-hover flex items-center gap-2" onClick={() => handleAction(task.id, 'start')}>
                          <Play size={14} /> 开始
                        </button>
                      )}
                      {task.status === 'human_running' && (
                        <button className="w-full px-4 py-2 text-left text-xs text-text hover:bg-bg-hover flex items-center gap-2" onClick={() => handleAction(task.id, 'pause')}>
                          <Pause size={14} /> 暂停
                        </button>
                      )}
                      <button className="w-full px-4 py-2 text-left text-xs text-text hover:bg-bg-hover flex items-center gap-2" onClick={() => handleAction(task.id, 'complete')}>
                        <Check size={14} /> 完成
                      </button>
                      {task.executorType === 'human' && (
                        <button className="w-full px-4 py-2 text-left text-xs text-text hover:bg-bg-hover flex items-center gap-2" onClick={() => handleAction(task.id, 'delegate')}>
                          <Bot size={14} /> 委派给 AI
                        </button>
                      )}
                      <button className="w-full px-4 py-2 text-left text-xs text-danger hover:bg-bg-hover flex items-center gap-2" onClick={() => handleAction(task.id, 'delete')}>
                        <Trash2 size={14} /> 删除
                      </button>
                    </div>
                  )}
                </div>
              )
            })}
          </div>
        )}
      </PageLayout>
    </AppLayout>
  )
}
