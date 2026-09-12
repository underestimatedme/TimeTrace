export type ProjectStatus = 'active' | 'archived' | 'paused'

export interface Project {
  id: string
  name: string
  description: string
  icon: string
  color: string
  status: ProjectStatus
  createdAt: string
}

export type GoalStatus = 'active' | 'completed' | 'paused' | 'cancelled'

export interface Goal {
  id: string
  projectId: string
  title: string
  description: string
  targetDate: string
  progress: number
  status: GoalStatus
}

export type ExecutorType = 'human' | 'ai' | 'collaboration' | 'external'
export type AIProvider = 'claude' | 'codex' | 'chatgpt' | 'gemini' | 'other'

export type TaskStatus =
  | 'inbox'
  | 'planned'
  | 'ready'
  | 'human_running'
  | 'ai_queued'
  | 'ai_running'
  | 'waiting_human'
  | 'waiting_external'
  | 'paused'
  | 'completed'
  | 'failed'
  | 'cancelled'

export type TaskPriority = 'low' | 'medium' | 'high' | 'urgent'
export type CollaborationMode =
  | 'ai_independent'
  | 'ai_first_review'
  | 'human_first_ai'
  | 'alternating'

export interface Task {
  id: string
  projectId: string
  goalId?: string
  title: string
  description: string
  executorType: ExecutorType
  aiProvider?: AIProvider
  collaborationMode?: CollaborationMode
  status: TaskStatus
  priority: TaskPriority
  estimatedMinutes: number
  dueDate?: string
  scheduledStart?: string
  scheduledEnd?: string
  createdAt: string
  completedAt?: string
  resultSummary?: string
}

export type TimeSessionType =
  | 'human_focus'
  | 'human_review'
  | 'ai_active'
  | 'ai_idle'
  | 'waiting_human'
  | 'waiting_ai'
  | 'waiting_external'
  | 'interruption'
  | 'rework'

export type TimeSessionSource = 'manual' | 'timer' | 'integration' | 'inferred' | 'simulated'
export type Confidence = 'exact' | 'estimated'

export interface TimeSession {
  id: string
  taskId: string
  type: TimeSessionType
  executor: 'human' | AIProvider | 'external'
  startedAt: string
  endedAt?: string
  durationSeconds: number
  source: TimeSessionSource
  confidence: Confidence
  note?: string
}

export type AIExecutionStatus =
  | 'queued'
  | 'running'
  | 'waiting_auth'
  | 'waiting_input'
  | 'completed'
  | 'failed'
  | 'cancelled'

export interface AIExecutionLog {
  time: string
  message: string
}

export interface AIExecution {
  id: string
  taskId: string
  provider: AIProvider
  model: string
  status: AIExecutionStatus
  startedAt: string
  endedAt?: string
  activeSeconds: number
  elapsedSeconds: number
  waitingHumanSeconds: number
  tokenInput: number
  tokenOutput: number
  estimatedCost: number
  toolCallCount: number
  filesChanged: number
  resultSummary?: string
  errorMessage?: string
  logs: AIExecutionLog[]
  currentStep?: string
}

export interface DailyStats {
  date: string
  humanSeconds: number
  aiActiveSeconds: number
  waitingSeconds: number
  deepWorkSeconds: number
  interruptionCount: number
  reworkSeconds: number
  completedTasks: number
  plannedMinutes: number
  actualHumanMinutes: number
}

export interface EfficiencyExperiment {
  id: string
  title: string
  description: string
  startDate: string
  durationDays: number
  status: 'active' | 'completed' | 'planned'
  beforeMetric: string
  afterMetric?: string
  effective?: boolean
}

export type ThemeName = 'claude' | 'codex' | 'cursor' | 'light'

export interface UserSettings {
  name: string
  weeklyTimeGoalHours: number
  workStartHour: number
  workEndHour: number
  defaultFocusMinutes: number
  streakDays: number
  theme: ThemeName
}

export interface AIToolConnection {
  provider: AIProvider
  name: string
  connected: boolean
  lastSync?: string
}

export interface ActiveFocus {
  taskId: string
  startedAt: string
  pausedAt?: string
  accumulatedSeconds: number
}

export interface AppState {
  projects: Project[]
  goals: Goal[]
  tasks: Task[]
  timeSessions: TimeSession[]
  aiExecutions: AIExecution[]
  dailyStats: DailyStats[]
  experiments: EfficiencyExperiment[]
  settings: UserSettings
  aiTools: AIToolConnection[]
  activeFocus?: ActiveFocus
  hasOnboarded: boolean
  useSampleData: boolean
}
