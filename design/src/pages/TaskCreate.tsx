import { useState } from 'react'
import { useNavigate } from 'react-router-dom'
import { SubPageLayout } from '@/components/layout/SubPageLayout'
import { Button } from '@/components/ui/Button'
import { Input, Textarea, Select, FormField } from '@/components/ui/Input'
import { useStore } from '@/store/useStore'
import type { ExecutorType, AIProvider, TaskPriority, CollaborationMode } from '@/types'

export function TaskCreatePage() {
  const navigate = useNavigate()
  const { projects, goals, addTask, startFocus, startAIExecution } = useStore()

  const [title, setTitle] = useState('')
  const [description, setDescription] = useState('')
  const [projectId, setProjectId] = useState(projects[0]?.id || '')
  const [goalId, setGoalId] = useState('')
  const [executorType, setExecutorType] = useState<ExecutorType>('human')
  const [aiProvider, setAIProvider] = useState<AIProvider>('claude')
  const [collaborationMode, setCollaborationMode] = useState<CollaborationMode>('ai_independent')
  const [estimatedMinutes, setEstimatedMinutes] = useState(30)
  const [priority, setPriority] = useState<TaskPriority>('medium')
  const [scheduledStart, setScheduledStart] = useState('')
  const [dueDate, setDueDate] = useState('')

  const projectGoals = goals.filter((g) => g.projectId === projectId)

  const buildTask = () => ({
    title,
    description,
    projectId,
    goalId: goalId || undefined,
    executorType,
    aiProvider: executorType === 'ai' || executorType === 'collaboration' ? aiProvider : undefined,
    collaborationMode: executorType === 'collaboration' ? collaborationMode : undefined,
    status: 'inbox' as const,
    priority,
    estimatedMinutes,
    scheduledStart: scheduledStart || undefined,
    dueDate: dueDate || undefined,
  })

  const handleSave = (action: 'save' | 'start' | 'schedule') => {
    if (!title || !projectId) return
    const id = addTask(buildTask())
    if (action === 'start') {
      if (executorType === 'ai') {
        startAIExecution(id)
        navigate(`/ai/${id}`)
      } else {
        startFocus(id)
        navigate(`/focus/${id}`)
      }
    } else {
      navigate('/tasks')
    }
  }

  return (
    <SubPageLayout title="新建任务">
      <FormField label="任务名称">
        <Input value={title} onChange={(e) => setTitle(e.target.value)} placeholder="输入任务名称" />
      </FormField>

      <FormField label="所属项目">
        <Select value={projectId} onChange={(e) => { setProjectId(e.target.value); setGoalId('') }}>
          {projects.map((p) => (
            <option key={p.id} value={p.id}>{p.icon} {p.name}</option>
          ))}
        </Select>
      </FormField>

      {projectGoals.length > 0 && (
        <FormField label="所属目标">
          <Select value={goalId} onChange={(e) => setGoalId(e.target.value)}>
            <option value="">不关联目标</option>
            {projectGoals.map((g) => (
              <option key={g.id} value={g.id}>{g.title}</option>
            ))}
          </Select>
        </FormField>
      )}

      <FormField label="执行者">
        <div className="grid grid-cols-2 gap-2">
          {([
            { value: 'human' as const, label: '我来做' },
            { value: 'ai' as const, label: 'AI 来做' },
            { value: 'collaboration' as const, label: '协作' },
            { value: 'external' as const, label: '等待其他人' },
          ]).map((opt) => (
            <button
              key={opt.value}
              onClick={() => setExecutorType(opt.value)}
              className={`px-3 py-2.5 rounded-xl text-sm border transition-colors ${
                executorType === opt.value ? 'border-accent bg-accent/10 text-accent' : 'border-border text-text-secondary'
              }`}
            >
              {opt.label}
            </button>
          ))}
        </div>
      </FormField>

      {(executorType === 'ai' || executorType === 'collaboration') && (
        <>
          <FormField label="AI 提供商">
            <div className="grid grid-cols-3 gap-2">
              {(['claude', 'codex', 'chatgpt', 'gemini', 'other'] as AIProvider[]).map((p) => (
                <button
                  key={p}
                  onClick={() => setAIProvider(p)}
                  className={`px-3 py-2 rounded-xl text-xs border transition-colors ${
                    aiProvider === p ? 'border-ai bg-ai/10 text-ai' : 'border-border text-text-secondary'
                  }`}
                >
                  {p.charAt(0).toUpperCase() + p.slice(1)}
                </button>
              ))}
            </div>
          </FormField>

          {executorType === 'collaboration' && (
            <FormField label="协作方式">
              <Select value={collaborationMode} onChange={(e) => setCollaborationMode(e.target.value as CollaborationMode)}>
                <option value="ai_independent">AI 独立完成</option>
                <option value="ai_first_review">AI 先做，我审核</option>
                <option value="human_first_ai">我先准备，AI 执行</option>
                <option value="alternating">我和 AI 交替完成</option>
              </Select>
            </FormField>
          )}
        </>
      )}

      <div className="grid grid-cols-2 gap-4">
        <FormField label="预计时间（分钟）">
          <Input type="number" value={estimatedMinutes} onChange={(e) => setEstimatedMinutes(Number(e.target.value))} />
        </FormField>
        <FormField label="优先级">
          <Select value={priority} onChange={(e) => setPriority(e.target.value as TaskPriority)}>
            <option value="low">低</option>
            <option value="medium">中</option>
            <option value="high">高</option>
            <option value="urgent">紧急</option>
          </Select>
        </FormField>
      </div>

      <div className="grid grid-cols-2 gap-4">
        <FormField label="计划开始">
          <Input type="datetime-local" value={scheduledStart} onChange={(e) => setScheduledStart(e.target.value)} />
        </FormField>
        <FormField label="截止日期">
          <Input type="date" value={dueDate} onChange={(e) => setDueDate(e.target.value)} />
        </FormField>
      </div>

      <FormField label="任务描述">
        <Textarea rows={3} value={description} onChange={(e) => setDescription(e.target.value)} placeholder="描述任务详情..." />
      </FormField>

      <div className="space-y-2 mt-6">
        <Button variant="accent" className="w-full" onClick={() => handleSave('save')}>保存任务</Button>
        <Button variant="secondary" className="w-full" onClick={() => handleSave('start')}>保存并开始</Button>
        <Button variant="ghost" className="w-full" onClick={() => handleSave('schedule')}>保存并安排时间</Button>
      </div>
    </SubPageLayout>
  )
}
