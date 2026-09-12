import { useNavigate, useParams } from 'react-router-dom'
import { ChevronRight } from 'lucide-react'
import { SubPageLayout } from '@/components/layout/SubPageLayout'
import { Card } from '@/components/ui/Card'
import { ProgressBar, SectionTitle } from '@/components/ui/Common'
import { useStore } from '@/store/useStore'
import { formatDuration } from '@/lib/format'
import { getHumanSeconds, getAIActiveSeconds } from '@/lib/stats'

export function ProjectsPage() {
  const navigate = useNavigate()
  const { projects, goals, tasks, timeSessions } = useStore()

  return (
    <SubPageLayout title="项目与目标">
      <div className="space-y-3">
        {projects.map((project) => {
          const projectGoals = goals.filter((g) => g.projectId === project.id)
          const projectTasks = tasks.filter((t) => t.projectId === project.id)
          const completedTasks = projectTasks.filter((t) => t.status === 'completed').length
          const progress = projectTasks.length > 0 ? (completedTasks / projectTasks.length) * 100 : 0
          const humanTime = getHumanSeconds(timeSessions.filter((s) => projectTasks.some((t) => t.id === s.taskId)))
          const aiTime = getAIActiveSeconds(timeSessions.filter((s) => projectTasks.some((t) => t.id === s.taskId)))

          return (
            <Card
              key={project.id}
              className="cursor-pointer hover:bg-bg-hover transition-colors"
              onClick={() => navigate(`/projects/${project.id}`)}
            >
              <div className="flex items-center justify-between mb-3">
                <div className="flex items-center gap-2">
                  <span className="text-xl">{project.icon}</span>
                  <div>
                    <h3 className="text-sm font-medium text-text">{project.name}</h3>
                    <p className="text-xs text-text-muted">{projectTasks.length} 个任务</p>
                  </div>
                </div>
                <ChevronRight size={16} className="text-text-muted" />
              </div>
              <ProgressBar value={progress} className="mb-2" />
              <div className="flex gap-4 text-xs text-text-muted">
                <span>人工 {formatDuration(humanTime)}</span>
                <span>AI {formatDuration(aiTime)}</span>
              </div>
              {projectGoals.length > 0 && (
                <p className="text-xs text-text-secondary mt-2">
                  当前目标: {projectGoals[0].title}
                </p>
              )}
            </Card>
          )
        })}
      </div>
    </SubPageLayout>
  )
}

export function ProjectDetailPage() {
  const { id } = useParams<{ id: string }>()
  const navigate = useNavigate()
  const { getProject, goals, tasks, timeSessions } = useStore()

  const project = getProject(id!)
  if (!project) return <SubPageLayout title="项目"><p className="text-center text-text-muted py-12">项目不存在</p></SubPageLayout>

  const projectGoals = goals.filter((g) => g.projectId === project.id)
  const projectTasks = tasks.filter((t) => t.projectId === project.id)
  const pendingTasks = projectTasks.filter((t) => !['completed', 'cancelled', 'failed'].includes(t.status))
  const humanTime = getHumanSeconds(timeSessions.filter((s) => projectTasks.some((t) => t.id === s.taskId)))
  const aiTime = getAIActiveSeconds(timeSessions.filter((s) => projectTasks.some((t) => t.id === s.taskId)))

  return (
    <SubPageLayout title={project.name}>
      <div className="flex items-center gap-3 mb-6">
        <span className="text-3xl">{project.icon}</span>
        <div>
          <p className="text-sm text-text-secondary">{project.description}</p>
        </div>
      </div>

      <div className="grid grid-cols-2 gap-2 mb-6">
        <Card><p className="text-xs text-text-muted">人工投入</p><p className="text-sm font-mono text-accent">{formatDuration(humanTime)}</p></Card>
        <Card><p className="text-xs text-text-muted">AI 投入</p><p className="text-sm font-mono text-ai">{formatDuration(aiTime)}</p></Card>
      </div>

      <SectionTitle>目标</SectionTitle>
      <div className="space-y-2 mb-6">
        {projectGoals.map((goal) => (
          <Card key={goal.id} className="cursor-pointer hover:bg-bg-hover" onClick={() => navigate(`/goals/${goal.id}`)}>
            <div className="flex items-center justify-between mb-2">
              <h3 className="text-sm font-medium text-text">{goal.title}</h3>
              <span className="text-xs font-mono text-accent">{goal.progress}%</span>
            </div>
            <ProgressBar value={goal.progress} />
          </Card>
        ))}
      </div>

      <SectionTitle>待完成任务 ({pendingTasks.length})</SectionTitle>
      <div className="space-y-2">
        {pendingTasks.slice(0, 5).map((task) => (
          <Card key={task.id} className="cursor-pointer hover:bg-bg-hover" onClick={() => navigate(`/tasks/${task.id}`)}>
            <p className="text-sm text-text">{task.title}</p>
          </Card>
        ))}
      </div>
    </SubPageLayout>
  )
}

export function GoalDetailPage() {
  const { id } = useParams<{ id: string }>()
  const navigate = useNavigate()
  const { goals, tasks, timeSessions, getProject } = useStore()

  const goal = goals.find((g) => g.id === id)
  if (!goal) return <SubPageLayout title="目标"><p className="text-center text-text-muted py-12">目标不存在</p></SubPageLayout>

  const project = getProject(goal.projectId)
  const goalTasks = tasks.filter((t) => t.goalId === goal.id)
  const humanTime = getHumanSeconds(timeSessions.filter((s) => goalTasks.some((t) => t.id === s.taskId)))
  const aiTime = getAIActiveSeconds(timeSessions.filter((s) => goalTasks.some((t) => t.id === s.taskId)))
  const completedCount = goalTasks.filter((t) => t.status === 'completed').length

  return (
    <SubPageLayout title="目标详情">
      <h2 className="text-lg font-medium text-text mb-2">{goal.title}</h2>
      {project && <p className="text-sm text-text-muted mb-4">{project.icon} {project.name}</p>}
      <p className="text-sm text-text-secondary mb-4">{goal.description}</p>

      <div className="mb-4">
        <div className="flex justify-between text-sm mb-1">
          <span className="text-text-secondary">完成进度</span>
          <span className="font-mono text-accent">{goal.progress}%</span>
        </div>
        <ProgressBar value={goal.progress} />
      </div>

      <div className="grid grid-cols-2 gap-2 mb-6">
        <Card><p className="text-xs text-text-muted">已投入时间</p><p className="text-sm font-mono">{formatDuration(humanTime + aiTime)}</p></Card>
        <Card><p className="text-xs text-text-muted">AI 贡献</p><p className="text-sm font-mono text-ai">{formatDuration(aiTime)}</p></Card>
        <Card><p className="text-xs text-text-muted">关联任务</p><p className="text-sm font-mono">{goalTasks.length}</p></Card>
        <Card><p className="text-xs text-text-muted">已完成</p><p className="text-sm font-mono text-success">{completedCount}</p></Card>
      </div>

      <SectionTitle>关联任务</SectionTitle>
      <div className="space-y-2">
        {goalTasks.map((task) => (
          <Card key={task.id} className="cursor-pointer hover:bg-bg-hover" onClick={() => navigate(`/tasks/${task.id}`)}>
            <p className="text-sm text-text">{task.title}</p>
          </Card>
        ))}
      </div>
    </SubPageLayout>
  )
}