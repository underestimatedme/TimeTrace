import { create } from 'zustand'
import { persist, createJSONStorage } from 'zustand/middleware'
import type {
  AppState,
  Task,
  TaskStatus,
  TimeSession,
  AIExecution,
  ActiveFocus,
  Project,
  Goal,
} from '@/types'
import { createSampleData, createEmptyData } from '@/data/mockData'
import { STORAGE_KEY, clearState } from '@/lib/storage'
import { generateId } from '@/lib/utils'
import { format } from 'date-fns'

interface StoreActions {
  /** Kept for backward compatibility; persistence is auto-hydrated by middleware. */
  init: () => void
  completeOnboarding: (useSample: boolean) => void
  resetToSample: () => void
  clearAll: () => void

  getProject: (id: string) => Project | undefined
  getGoal: (id: string) => Goal | undefined
  getTask: (id: string) => Task | undefined

  addTask: (task: Omit<Task, 'id' | 'createdAt'>) => string
  updateTask: (id: string, updates: Partial<Task>) => void
  deleteTask: (id: string) => void
  setTaskStatus: (id: string, status: TaskStatus) => void

  startFocus: (taskId: string) => void
  pauseFocus: (reason?: string) => void
  resumeFocus: () => void
  completeFocus: (note?: string) => void
  markInterruption: (reason: string) => void

  startAIExecution: (taskId: string) => void
  pauseAIExecution: (taskId: string) => void
  cancelAIExecution: (taskId: string) => void
  authorizeAI: (taskId: string) => void
  completeAIReview: (taskId: string) => void
  tickAIExecutions: () => void

  addTimeSession: (session: Omit<TimeSession, 'id'>) => void
  updateSettings: (updates: Partial<AppState['settings']>) => void

  getRunningHumanTask: () => Task | undefined
  getRunningAITasks: () => Task[]
  getWaitingHumanTasks: () => Task[]
}

type Store = AppState & StoreActions

const AI_STEPS = [
  '读取项目结构',
  '分析数据模型',
  '生成代码',
  '运行测试',
  '修复错误',
  '优化输出',
  '写入文件',
] as const

const nowIso = () => new Date().toISOString()
const nowLabel = () => format(new Date(), 'HH:mm')
const secondsSince = (iso: string) => Math.floor((Date.now() - new Date(iso).getTime()) / 1000)

/** Helpers that return new arrays so reducers stay pure (no nested set/get). */
function withTask(tasks: Task[], id: string, updates: Partial<Task>): Task[] {
  return tasks.map((t) => (t.id === id ? { ...t, ...updates } : t))
}

function closeOpenSession(
  sessions: TimeSession[],
  predicate: (s: TimeSession) => boolean,
  endedAt: string,
  extra?: Partial<TimeSession>
): TimeSession[] {
  return sessions.map((s) =>
    predicate(s) && !s.endedAt
      ? { ...s, endedAt, durationSeconds: s.durationSeconds || secondsSince(s.startedAt), ...extra }
      : s
  )
}

function newSession(session: Omit<TimeSession, 'id'>): TimeSession {
  return { ...session, id: generateId() }
}

export const useStore = create<Store>()(
  persist(
    (set, get) => ({
      ...createEmptyData(),

      init: () => {
        // Persistence is hydrated automatically by the persist middleware.
      },

      completeOnboarding: (useSample) => {
        const data = useSample ? createSampleData() : createEmptyData()
        set({ ...data, hasOnboarded: true, useSampleData: useSample })
      },

      resetToSample: () => {
        set({ ...createSampleData(), hasOnboarded: true, useSampleData: true })
      },

      clearAll: () => {
        clearState()
        set({ ...createEmptyData(), hasOnboarded: false })
      },

      getProject: (id) => get().projects.find((p) => p.id === id),
      getGoal: (id) => get().goals.find((g) => g.id === id),
      getTask: (id) => get().tasks.find((t) => t.id === id),

      addTask: (taskData) => {
        const task: Task = {
          ...taskData,
          id: generateId(),
          createdAt: nowIso(),
          status: taskData.status || 'inbox',
        }
        set((s) => ({ tasks: [...s.tasks, task] }))
        return task.id
      },

      updateTask: (id, updates) => {
        set((s) => ({ tasks: withTask(s.tasks, id, updates) }))
      },

      deleteTask: (id) => {
        set((s) => ({
          tasks: s.tasks.filter((t) => t.id !== id),
          timeSessions: s.timeSessions.filter((ts) => ts.taskId !== id),
          aiExecutions: s.aiExecutions.filter((ae) => ae.taskId !== id),
        }))
      },

      setTaskStatus: (id, status) => {
        set((s) => ({
          tasks: withTask(s.tasks, id, {
            status,
            ...(status === 'completed' ? { completedAt: nowIso() } : {}),
          }),
        }))
      },

      startFocus: (taskId) => {
        const at = nowIso()
        const focus: ActiveFocus = { taskId, startedAt: at, accumulatedSeconds: 0 }
        set((s) => ({
          tasks: withTask(s.tasks, taskId, { status: 'human_running' }),
          activeFocus: focus,
          timeSessions: [
            ...s.timeSessions,
            newSession({
              taskId,
              type: 'human_focus',
              executor: 'human',
              startedAt: at,
              durationSeconds: 0,
              source: 'timer',
              confidence: 'exact',
            }),
          ],
        }))
      },

      pauseFocus: (reason) => {
        const { activeFocus } = get()
        if (!activeFocus) return
        const at = nowIso()
        const elapsed = secondsSince(activeFocus.startedAt) + activeFocus.accumulatedSeconds

        set((s) => {
          let sessions = closeOpenSession(
            s.timeSessions,
            (x) => x.taskId === activeFocus.taskId && x.type === 'human_focus',
            at,
            { durationSeconds: elapsed }
          )
          if (reason) {
            sessions = [
              ...sessions,
              newSession({
                taskId: activeFocus.taskId,
                type: 'interruption',
                executor: 'human',
                startedAt: at,
                endedAt: at,
                durationSeconds: 0,
                source: 'manual',
                confidence: 'exact',
                note: reason,
              }),
            ]
          }
          return {
            tasks: withTask(s.tasks, activeFocus.taskId, { status: 'paused' }),
            timeSessions: sessions,
            activeFocus: undefined,
          }
        })
      },

      resumeFocus: () => {
        const { activeFocus } = get()
        if (!activeFocus) return
        const at = nowIso()
        set((s) => ({
          tasks: withTask(s.tasks, activeFocus.taskId, { status: 'human_running' }),
          activeFocus: { ...activeFocus, startedAt: at },
          timeSessions: [
            ...s.timeSessions,
            newSession({
              taskId: activeFocus.taskId,
              type: 'human_focus',
              executor: 'human',
              startedAt: at,
              durationSeconds: 0,
              source: 'timer',
              confidence: 'exact',
            }),
          ],
        }))
      },

      completeFocus: (note) => {
        const { activeFocus } = get()
        if (!activeFocus) return
        const at = nowIso()
        const elapsed = secondsSince(activeFocus.startedAt) + activeFocus.accumulatedSeconds
        set((s) => ({
          tasks: withTask(s.tasks, activeFocus.taskId, { status: 'completed', completedAt: at }),
          timeSessions: closeOpenSession(
            s.timeSessions,
            (x) => x.taskId === activeFocus.taskId && x.type === 'human_focus',
            at,
            { durationSeconds: elapsed, note }
          ),
          activeFocus: undefined,
        }))
      },

      markInterruption: (reason) => {
        const { activeFocus } = get()
        if (!activeFocus) return
        const at = nowIso()
        set((s) => ({
          timeSessions: [
            ...s.timeSessions,
            newSession({
              taskId: activeFocus.taskId,
              type: 'interruption',
              executor: 'human',
              startedAt: at,
              endedAt: at,
              durationSeconds: 0,
              source: 'manual',
              confidence: 'exact',
              note: reason,
            }),
          ],
        }))
      },

      startAIExecution: (taskId) => {
        const task = get().getTask(taskId)
        if (!task) return
        const at = nowIso()
        const provider = task.aiProvider || 'claude'
        const execution: AIExecution = {
          id: generateId(),
          taskId,
          provider,
          model: provider === 'codex' ? 'gpt-4o' : 'claude-sonnet-4',
          status: 'running',
          startedAt: at,
          activeSeconds: 0,
          elapsedSeconds: 0,
          waitingHumanSeconds: 0,
          tokenInput: 0,
          tokenOutput: 0,
          estimatedCost: 0,
          toolCallCount: 0,
          filesChanged: 0,
          logs: [{ time: nowLabel(), message: '开始执行' }],
          currentStep: AI_STEPS[0],
        }
        set((s) => ({
          tasks: withTask(s.tasks, taskId, { status: 'ai_running' }),
          aiExecutions: [...s.aiExecutions, execution],
          timeSessions: [
            ...s.timeSessions,
            newSession({
              taskId,
              type: 'ai_active',
              executor: provider,
              startedAt: at,
              durationSeconds: 0,
              source: 'simulated',
              confidence: 'exact',
            }),
          ],
        }))
      },

      pauseAIExecution: (taskId) => {
        set((s) => ({
          tasks: withTask(s.tasks, taskId, { status: 'paused' }),
          aiExecutions: s.aiExecutions.map((ae) =>
            ae.taskId === taskId && ae.status === 'running'
              ? { ...ae, status: 'waiting_input' as const }
              : ae
          ),
        }))
      },

      cancelAIExecution: (taskId) => {
        const at = nowIso()
        set((s) => ({
          tasks: withTask(s.tasks, taskId, { status: 'cancelled' }),
          aiExecutions: s.aiExecutions.map((ae) =>
            ae.taskId === taskId ? { ...ae, status: 'cancelled' as const, endedAt: at } : ae
          ),
          timeSessions: closeOpenSession(s.timeSessions, (x) => x.taskId === taskId, at),
        }))
      },

      authorizeAI: (taskId) => {
        set((s) => ({
          tasks: withTask(s.tasks, taskId, { status: 'ai_running' }),
          aiExecutions: s.aiExecutions.map((ae) =>
            ae.taskId === taskId ? { ...ae, status: 'running' as const } : ae
          ),
        }))
      },

      completeAIReview: (taskId) => {
        const at = nowIso()
        set((s) => ({
          tasks: withTask(s.tasks, taskId, { status: 'completed', completedAt: at }),
          timeSessions: [
            ...closeOpenSession(
              s.timeSessions,
              (x) => x.taskId === taskId && x.type === 'waiting_human',
              at
            ),
            newSession({
              taskId,
              type: 'human_review',
              executor: 'human',
              startedAt: at,
              endedAt: at,
              durationSeconds: 480,
              source: 'manual',
              confidence: 'estimated',
            }),
          ],
        }))
      },

      tickAIExecutions: () => {
        const { aiExecutions, activeFocus } = get()
        const hasRunningAI = aiExecutions.some((ae) => ae.status === 'running')
        // Avoid churning state/localStorage when nothing is in motion.
        if (!hasRunningAI && !activeFocus) return

        set((s) => {
          let tasks = s.tasks
          const spawnedSessions: TimeSession[] = []

          const nextExecutions = s.aiExecutions.map((ae) => {
            if (ae.status !== 'running') return ae

            const active = ae.activeSeconds + 1
            const stepIdx = Math.min(Math.floor(active / 30), AI_STEPS.length - 1)
            const shouldFinish = active > 120 && active % 60 === 0

            if (shouldFinish) {
              const at = nowIso()
              tasks = withTask(tasks, ae.taskId, { status: 'waiting_human' })
              spawnedSessions.push(
                newSession({
                  taskId: ae.taskId,
                  type: 'waiting_human',
                  executor: 'human',
                  startedAt: at,
                  durationSeconds: 0,
                  source: 'inferred',
                  confidence: 'estimated',
                })
              )
              return {
                ...ae,
                activeSeconds: active,
                elapsedSeconds: active,
                tokenInput: ae.tokenInput + Math.floor(Math.random() * 50),
                estimatedCost: ae.estimatedCost + 0.001,
                status: 'completed' as const,
                endedAt: at,
                resultSummary: '执行完成，等待审核',
                logs: [...ae.logs, { time: nowLabel(), message: AI_STEPS[stepIdx] }],
              }
            }

            return {
              ...ae,
              activeSeconds: active,
              elapsedSeconds: active,
              tokenInput: ae.tokenInput + Math.floor(Math.random() * 50),
              tokenOutput: ae.tokenOutput + Math.floor(Math.random() * 20),
              estimatedCost: ae.estimatedCost + 0.001,
              toolCallCount: ae.toolCallCount + (active % 15 === 0 ? 1 : 0),
              currentStep: AI_STEPS[stepIdx],
              logs:
                active % 30 === 0
                  ? [...ae.logs, { time: nowLabel(), message: AI_STEPS[stepIdx] }]
                  : ae.logs,
            }
          })

          let timeSessions = s.timeSessions.map((ts) => {
            if (!ts.endedAt && (ts.type === 'ai_active' || ts.type === 'waiting_human')) {
              return { ...ts, durationSeconds: ts.durationSeconds + 1 }
            }
            return ts
          })

          if (s.activeFocus) {
            const elapsed = secondsSince(s.activeFocus.startedAt) + s.activeFocus.accumulatedSeconds
            timeSessions = timeSessions.map((ts) =>
              ts.taskId === s.activeFocus!.taskId && !ts.endedAt && ts.type === 'human_focus'
                ? { ...ts, durationSeconds: elapsed }
                : ts
            )
          }

          return {
            tasks,
            aiExecutions: nextExecutions,
            timeSessions: [...timeSessions, ...spawnedSessions],
          }
        })
      },

      addTimeSession: (session) => {
        set((s) => ({ timeSessions: [...s.timeSessions, newSession(session)] }))
      },

      updateSettings: (updates) => {
        set((s) => ({ settings: { ...s.settings, ...updates } }))
      },

      getRunningHumanTask: () => {
        const { tasks, activeFocus } = get()
        if (!activeFocus) return undefined
        return tasks.find((t) => t.id === activeFocus.taskId)
      },

      getRunningAITasks: () => get().tasks.filter((t) => t.status === 'ai_running'),

      getWaitingHumanTasks: () => get().tasks.filter((t) => t.status === 'waiting_human'),
    }),
    {
      name: STORAGE_KEY,
      storage: createJSONStorage(() => localStorage),
      // Only persist data, never the action functions.
      partialize: (s): AppState => ({
        projects: s.projects,
        goals: s.goals,
        tasks: s.tasks,
        timeSessions: s.timeSessions,
        aiExecutions: s.aiExecutions,
        dailyStats: s.dailyStats,
        experiments: s.experiments,
        settings: s.settings,
        aiTools: s.aiTools,
        activeFocus: s.activeFocus,
        hasOnboarded: s.hasOnboarded,
        useSampleData: s.useSampleData,
      }),
    }
  )
)
