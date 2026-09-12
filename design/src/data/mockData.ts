import type { AppState } from '@/types'
import { subDays, format } from 'date-fns'

const today = format(new Date(), 'yyyy-MM-dd')
const now = new Date()

function hoursAgo(h: number, m = 0): string {
  const d = new Date(now)
  d.setHours(d.getHours() - h, d.getMinutes() - m)
  return d.toISOString()
}

function todayAt(h: number, m = 0): string {
  const d = new Date()
  d.setHours(h, m, 0, 0)
  return d.toISOString()
}

function daysAgo(n: number, h = 10, m = 0): string {
  const d = subDays(new Date(), n)
  d.setHours(h, m, 0, 0)
  return d.toISOString()
}

export function createSampleData(): AppState {
  const projects = [
    { id: 'p1', name: '刻迹 App', description: 'AI 时代个人事务与时间管理系统', icon: '⏳', color: '#d4845a', status: 'active' as const, createdAt: daysAgo(30) },
    { id: 'p2', name: '日常工作', description: '日常工作事务', icon: '💼', color: '#6b8cae', status: 'active' as const, createdAt: daysAgo(60) },
    { id: 'p3', name: '健身计划', description: '身体健康管理', icon: '🏃', color: '#5a8a6a', status: 'active' as const, createdAt: daysAgo(45) },
    { id: 'p4', name: '个人成长', description: '阅读与学习', icon: '📚', color: '#8a7a4a', status: 'active' as const, createdAt: daysAgo(90) },
  ]

  const goals = [
    { id: 'g1', projectId: 'p1', title: '在 30 天内完成刻迹 MVP', description: '完成核心功能原型', targetDate: daysAgo(-20), progress: 65, status: 'active' as const },
    { id: 'g2', projectId: 'p1', title: '设计完整视觉系统', description: '建立品牌视觉语言', targetDate: daysAgo(-10), progress: 80, status: 'active' as const },
    { id: 'g3', projectId: 'p2', title: 'Q2 项目交付', description: '按时完成季度目标', targetDate: daysAgo(-45), progress: 40, status: 'active' as const },
    { id: 'g4', projectId: 'p3', title: '每周运动 4 次', description: '保持健康体魄', targetDate: daysAgo(-60), progress: 75, status: 'active' as const },
    { id: 'g5', projectId: 'p4', title: '每月阅读 2 本书', description: '持续学习成长', targetDate: daysAgo(-15), progress: 50, status: 'active' as const },
  ]

  const tasks = [
    { id: 't1', projectId: 'p1', goalId: 'g1', title: '整理刻迹产品需求', description: '梳理核心功能与数据模型', executorType: 'human' as const, status: 'completed' as const, priority: 'high' as const, estimatedMinutes: 60, dueDate: today, scheduledStart: todayAt(9, 0), scheduledEnd: todayAt(10, 0), createdAt: daysAgo(2, 9), completedAt: todayAt(9, 55), resultSummary: '完成 PRD 初稿' },
    { id: 't2', projectId: 'p1', goalId: 'g2', title: '设计今日首页', description: '设计核心首页交互与布局', executorType: 'human' as const, status: 'human_running' as const, priority: 'high' as const, estimatedMinutes: 90, dueDate: today, scheduledStart: todayAt(10, 30), scheduledEnd: todayAt(12, 0), createdAt: daysAgo(1, 14) },
    { id: 't3', projectId: 'p1', goalId: 'g1', title: 'Claude 生成数据模型', description: '生成 TypeScript 类型定义', executorType: 'ai' as const, aiProvider: 'claude' as const, collaborationMode: 'ai_independent' as const, status: 'ai_running' as const, priority: 'high' as const, estimatedMinutes: 30, dueDate: today, scheduledStart: todayAt(9, 18), createdAt: daysAgo(1, 9, 18) },
    { id: 't4', projectId: 'p1', goalId: 'g1', title: 'Codex 补充单元测试', description: '为数据层补充测试', executorType: 'ai' as const, aiProvider: 'codex' as const, collaborationMode: 'ai_first_review' as const, status: 'waiting_human' as const, priority: 'medium' as const, estimatedMinutes: 45, dueDate: today, scheduledStart: todayAt(16, 0), createdAt: daysAgo(1, 10), resultSummary: '生成 12 个测试用例，全部通过' },
    { id: 't5', projectId: 'p1', goalId: 'g1', title: '审核 AI 生成代码', description: '审核 Claude 输出的数据模型', executorType: 'collaboration' as const, aiProvider: 'claude' as const, collaborationMode: 'ai_first_review' as const, status: 'waiting_human' as const, priority: 'high' as const, estimatedMinutes: 20, dueDate: today, scheduledStart: todayAt(10, 30), createdAt: daysAgo(1, 9, 31) },
    { id: 't6', projectId: 'p1', goalId: 'g2', title: '完成登录页面', description: '实现登录注册 UI', executorType: 'collaboration' as const, aiProvider: 'claude' as const, collaborationMode: 'human_first_ai' as const, status: 'planned' as const, priority: 'medium' as const, estimatedMinutes: 120, dueDate: daysAgo(-2), scheduledStart: todayAt(14, 0), createdAt: daysAgo(3) },
    { id: 't7', projectId: 'p4', goalId: 'g5', title: '阅读 30 分钟', description: '阅读《深度工作》', executorType: 'human' as const, status: 'ready' as const, priority: 'low' as const, estimatedMinutes: 30, dueDate: today, scheduledStart: todayAt(20, 0), createdAt: daysAgo(1) },
    { id: 't8', projectId: 'p3', goalId: 'g4', title: '午间健身', description: '力量训练 45 分钟', executorType: 'human' as const, status: 'planned' as const, priority: 'medium' as const, estimatedMinutes: 45, dueDate: today, scheduledStart: todayAt(12, 30), scheduledEnd: todayAt(13, 15), createdAt: daysAgo(5) },
    { id: 't9', projectId: 'p2', goalId: 'g3', title: '回复工作邮件', description: '处理收件箱', executorType: 'human' as const, status: 'completed' as const, priority: 'medium' as const, estimatedMinutes: 30, dueDate: today, scheduledStart: todayAt(8, 30), createdAt: daysAgo(1, 8), completedAt: todayAt(8, 52) },
    { id: 't10', projectId: 'p1', goalId: 'g1', title: '复盘今日时间', description: '回顾时间分配', executorType: 'human' as const, status: 'inbox' as const, priority: 'low' as const, estimatedMinutes: 15, dueDate: today, scheduledStart: todayAt(21, 0), createdAt: daysAgo(0) },
    { id: 't11', projectId: 'p2', goalId: 'g3', title: '产品需求整理', description: '整理下周需求', executorType: 'human' as const, status: 'ready' as const, priority: 'high' as const, estimatedMinutes: 60, dueDate: today, scheduledStart: todayAt(11, 0), createdAt: daysAgo(2) },
    { id: 't12', projectId: 'p1', goalId: 'g1', title: 'ChatGPT 生成文案', description: '生成产品介绍文案', executorType: 'ai' as const, aiProvider: 'chatgpt' as const, status: 'completed' as const, priority: 'low' as const, estimatedMinutes: 15, createdAt: daysAgo(3), completedAt: daysAgo(3, 15), resultSummary: '生成 3 版文案' },
    { id: 't13', projectId: 'p1', goalId: 'g1', title: '数据库设计审核', description: '审核数据库 schema', executorType: 'collaboration' as const, aiProvider: 'claude' as const, status: 'completed' as const, priority: 'high' as const, estimatedMinutes: 45, createdAt: daysAgo(4), completedAt: daysAgo(4, 11) },
    { id: 't14', projectId: 'p2', goalId: 'g3', title: '周报撰写', description: '撰写本周工作周报', executorType: 'human' as const, status: 'failed' as const, priority: 'medium' as const, estimatedMinutes: 30, dueDate: daysAgo(1), createdAt: daysAgo(2) },
    { id: 't15', projectId: 'p1', goalId: 'g1', title: 'Gemini 分析竞品', description: '分析竞品功能', executorType: 'ai' as const, aiProvider: 'gemini' as const, status: 'cancelled' as const, priority: 'low' as const, estimatedMinutes: 20, createdAt: daysAgo(5) },
    { id: 't16', projectId: 'p1', goalId: 'g2', title: '设计底部导航', description: '设计 5 项底部导航', executorType: 'human' as const, status: 'completed' as const, priority: 'high' as const, estimatedMinutes: 60, createdAt: daysAgo(2), completedAt: daysAgo(2, 16) },
    { id: 't17', projectId: 'p3', goalId: 'g4', title: '晨跑 5 公里', description: '有氧训练', executorType: 'human' as const, status: 'completed' as const, priority: 'medium' as const, estimatedMinutes: 35, createdAt: daysAgo(1, 7), completedAt: daysAgo(1, 7, 35) },
    { id: 't18', projectId: 'p2', goalId: 'g3', title: '等待设计稿确认', description: '等待设计师反馈', executorType: 'external' as const, status: 'waiting_external' as const, priority: 'medium' as const, estimatedMinutes: 0, createdAt: daysAgo(1) },
    { id: 't19', projectId: 'p1', goalId: 'g1', title: '实现状态管理', description: 'Zustand store 实现', executorType: 'collaboration' as const, aiProvider: 'codex' as const, collaborationMode: 'alternating' as const, status: 'paused' as const, priority: 'high' as const, estimatedMinutes: 90, createdAt: daysAgo(1) },
    { id: 't20', projectId: 'p4', goalId: 'g5', title: '写学习笔记', description: '整理本周阅读笔记', executorType: 'human' as const, status: 'inbox' as const, priority: 'low' as const, estimatedMinutes: 25, createdAt: daysAgo(0) },
  ]

  const timeSessions = [
    { id: 'ts1', taskId: 't1', type: 'human_focus' as const, executor: 'human' as const, startedAt: todayAt(9, 0), endedAt: todayAt(9, 55), durationSeconds: 3300, source: 'timer' as const, confidence: 'exact' as const },
    { id: 'ts2', taskId: 't3', type: 'ai_active' as const, executor: 'claude' as const, startedAt: todayAt(9, 18), endedAt: todayAt(9, 35), durationSeconds: 1020, source: 'simulated' as const, confidence: 'exact' as const },
    { id: 'ts3', taskId: 't3', type: 'waiting_human' as const, executor: 'human' as const, startedAt: todayAt(9, 35), endedAt: todayAt(9, 52), durationSeconds: 1020, source: 'inferred' as const, confidence: 'estimated' as const },
    { id: 'ts4', taskId: 't5', type: 'human_review' as const, executor: 'human' as const, startedAt: todayAt(9, 52), endedAt: todayAt(10, 5), durationSeconds: 780, source: 'timer' as const, confidence: 'exact' as const },
    { id: 'ts5', taskId: 't2', type: 'human_focus' as const, executor: 'human' as const, startedAt: hoursAgo(0, 42), endedAt: undefined, durationSeconds: 2520, source: 'timer' as const, confidence: 'exact' as const, note: '进行中' },
    { id: 'ts6', taskId: 't3', type: 'ai_active' as const, executor: 'claude' as const, startedAt: hoursAgo(0, 8), endedAt: undefined, durationSeconds: 480, source: 'simulated' as const, confidence: 'exact' as const },
    { id: 'ts7', taskId: 't4', type: 'ai_active' as const, executor: 'codex' as const, startedAt: todayAt(10, 3), endedAt: todayAt(10, 15), durationSeconds: 720, source: 'simulated' as const, confidence: 'exact' as const },
    { id: 'ts8', taskId: 't4', type: 'waiting_human' as const, executor: 'human' as const, startedAt: todayAt(10, 15), endedAt: undefined, durationSeconds: 1080, source: 'inferred' as const, confidence: 'estimated' as const },
    { id: 'ts9', taskId: 't9', type: 'human_focus' as const, executor: 'human' as const, startedAt: todayAt(8, 30), endedAt: todayAt(8, 52), durationSeconds: 1320, source: 'timer' as const, confidence: 'exact' as const },
    { id: 'ts10', taskId: 't17', type: 'human_focus' as const, executor: 'human' as const, startedAt: daysAgo(1, 7), endedAt: daysAgo(1, 7, 35), durationSeconds: 2100, source: 'timer' as const, confidence: 'exact' as const },
    { id: 'ts11', taskId: 't8', type: 'human_focus' as const, executor: 'human' as const, startedAt: daysAgo(1, 12, 30), endedAt: daysAgo(1, 13, 15), durationSeconds: 2700, source: 'timer' as const, confidence: 'exact' as const },
    { id: 'ts12', taskId: 't13', type: 'human_review' as const, executor: 'human' as const, startedAt: daysAgo(4, 10, 30), endedAt: daysAgo(4, 11), durationSeconds: 1800, source: 'timer' as const, confidence: 'exact' as const },
    { id: 'ts13', taskId: 't13', type: 'ai_active' as const, executor: 'claude' as const, startedAt: daysAgo(4, 9, 30), endedAt: daysAgo(4, 10, 15), durationSeconds: 2700, source: 'simulated' as const, confidence: 'exact' as const },
    { id: 'ts14', taskId: 't2', type: 'interruption' as const, executor: 'human' as const, startedAt: todayAt(10, 20), endedAt: todayAt(10, 25), durationSeconds: 300, source: 'manual' as const, confidence: 'exact' as const, note: '收到消息' },
    { id: 'ts15', taskId: 't19', type: 'rework' as const, executor: 'human' as const, startedAt: daysAgo(1, 15), endedAt: daysAgo(1, 15, 30), durationSeconds: 1800, source: 'manual' as const, confidence: 'estimated' as const },
    { id: 'ts16', taskId: 't12', type: 'ai_active' as const, executor: 'chatgpt' as const, startedAt: daysAgo(3, 14), endedAt: daysAgo(3, 14, 12), durationSeconds: 720, source: 'simulated' as const, confidence: 'exact' as const },
    { id: 'ts17', taskId: 't16', type: 'human_focus' as const, executor: 'human' as const, startedAt: daysAgo(2, 15), endedAt: daysAgo(2, 16), durationSeconds: 3600, source: 'timer' as const, confidence: 'exact' as const },
    { id: 'ts18', taskId: 't18', type: 'waiting_external' as const, executor: 'external' as const, startedAt: daysAgo(1, 10), endedAt: undefined, durationSeconds: 86400, source: 'inferred' as const, confidence: 'estimated' as const },
    { id: 'ts19', taskId: 't6', type: 'ai_active' as const, executor: 'claude' as const, startedAt: daysAgo(2, 14), endedAt: daysAgo(2, 14, 45), durationSeconds: 2700, source: 'simulated' as const, confidence: 'exact' as const },
    { id: 'ts20', taskId: 't6', type: 'human_focus' as const, executor: 'human' as const, startedAt: daysAgo(2, 13), endedAt: daysAgo(2, 13, 40), durationSeconds: 2400, source: 'timer' as const, confidence: 'exact' as const },
    { id: 'ts21', taskId: 't1', type: 'human_focus' as const, executor: 'human' as const, startedAt: daysAgo(2, 9), endedAt: daysAgo(2, 10), durationSeconds: 3600, source: 'timer' as const, confidence: 'exact' as const },
    { id: 'ts22', taskId: 't3', type: 'ai_active' as const, executor: 'claude' as const, startedAt: daysAgo(2, 10, 5), endedAt: daysAgo(2, 10, 30), durationSeconds: 1500, source: 'simulated' as const, confidence: 'exact' as const },
    { id: 'ts23', taskId: 't11', type: 'human_focus' as const, executor: 'human' as const, startedAt: daysAgo(3, 11), endedAt: daysAgo(3, 12), durationSeconds: 3600, source: 'timer' as const, confidence: 'exact' as const },
    { id: 'ts24', taskId: 't7', type: 'human_focus' as const, executor: 'human' as const, startedAt: daysAgo(3, 20), endedAt: daysAgo(3, 20, 30), durationSeconds: 1800, source: 'timer' as const, confidence: 'exact' as const },
    { id: 'ts25', taskId: 't4', type: 'ai_active' as const, executor: 'codex' as const, startedAt: daysAgo(4, 16), endedAt: daysAgo(4, 16, 20), durationSeconds: 1200, source: 'simulated' as const, confidence: 'exact' as const },
    { id: 'ts26', taskId: 't5', type: 'waiting_ai' as const, executor: 'claude' as const, startedAt: daysAgo(5, 9), endedAt: daysAgo(5, 9, 15), durationSeconds: 900, source: 'inferred' as const, confidence: 'estimated' as const },
    { id: 'ts27', taskId: 't2', type: 'human_focus' as const, executor: 'human' as const, startedAt: daysAgo(5, 14), endedAt: daysAgo(5, 15, 30), durationSeconds: 5400, source: 'timer' as const, confidence: 'exact' as const },
    { id: 'ts28', taskId: 't9', type: 'human_focus' as const, executor: 'human' as const, startedAt: daysAgo(6, 8, 30), endedAt: daysAgo(6, 9), durationSeconds: 1800, source: 'timer' as const, confidence: 'exact' as const },
    { id: 'ts29', taskId: 't17', type: 'human_focus' as const, executor: 'human' as const, startedAt: daysAgo(6, 7), endedAt: daysAgo(6, 7, 35), durationSeconds: 2100, source: 'timer' as const, confidence: 'exact' as const },
    { id: 'ts30', taskId: 't8', type: 'human_focus' as const, executor: 'human' as const, startedAt: daysAgo(6, 12, 30), endedAt: daysAgo(6, 13, 10), durationSeconds: 2400, source: 'timer' as const, confidence: 'exact' as const },
  ]

  const aiExecutions = [
    {
      id: 'ai1', taskId: 't3', provider: 'claude' as const, model: 'claude-sonnet-4', status: 'running' as const,
      startedAt: hoursAgo(0, 8), activeSeconds: 480, elapsedSeconds: 480, waitingHumanSeconds: 0,
      tokenInput: 12400, tokenOutput: 3200, estimatedCost: 0.18, toolCallCount: 8, filesChanged: 3,
      currentStep: '修改 Task 类型定义',
      logs: [
        { time: format(new Date(hoursAgo(0, 8)), 'HH:mm'), message: '读取项目结构' },
        { time: format(new Date(hoursAgo(0, 6)), 'HH:mm'), message: '分析数据模型' },
        { time: format(new Date(hoursAgo(0, 4)), 'HH:mm'), message: '修改 Task 类型' },
      ],
    },
    {
      id: 'ai2', taskId: 't4', provider: 'codex' as const, model: 'gpt-4o', status: 'completed' as const,
      startedAt: todayAt(10, 3), endedAt: todayAt(10, 15), activeSeconds: 720, elapsedSeconds: 720, waitingHumanSeconds: 0,
      tokenInput: 8600, tokenOutput: 4100, estimatedCost: 0.24, toolCallCount: 12, filesChanged: 5,
      resultSummary: '生成 12 个测试用例，全部通过',
      logs: [
        { time: '10:03', message: '分析现有代码' },
        { time: '10:05', message: '生成测试用例' },
        { time: '10:09', message: '运行测试' },
        { time: '10:11', message: '测试失败，修复类型错误' },
        { time: '10:13', message: '测试通过' },
      ],
    },
    {
      id: 'ai3', taskId: 't13', provider: 'claude' as const, model: 'claude-sonnet-4', status: 'completed' as const,
      startedAt: daysAgo(4, 9, 30), endedAt: daysAgo(4, 10, 15), activeSeconds: 2700, elapsedSeconds: 2700, waitingHumanSeconds: 0,
      tokenInput: 15200, tokenOutput: 6800, estimatedCost: 0.32, toolCallCount: 6, filesChanged: 2,
      resultSummary: '数据库 schema 设计完成',
      logs: [{ time: '09:30', message: '分析需求' }, { time: '09:45', message: '生成 schema' }, { time: '10:10', message: '完成' }],
    },
    {
      id: 'ai4', taskId: 't12', provider: 'chatgpt' as const, model: 'gpt-4o', status: 'completed' as const,
      startedAt: daysAgo(3, 14), endedAt: daysAgo(3, 14, 12), activeSeconds: 720, elapsedSeconds: 720, waitingHumanSeconds: 0,
      tokenInput: 3200, tokenOutput: 2800, estimatedCost: 0.08, toolCallCount: 0, filesChanged: 0,
      resultSummary: '生成 3 版产品介绍文案',
      logs: [{ time: '14:00', message: '生成文案' }, { time: '14:10', message: '完成' }],
    },
    {
      id: 'ai5', taskId: 't6', provider: 'claude' as const, model: 'claude-sonnet-4', status: 'completed' as const,
      startedAt: daysAgo(2, 14), endedAt: daysAgo(2, 14, 45), activeSeconds: 2700, elapsedSeconds: 2700, waitingHumanSeconds: 0,
      tokenInput: 9800, tokenOutput: 5200, estimatedCost: 0.22, toolCallCount: 10, filesChanged: 4,
      resultSummary: '登录页面组件生成完成',
      logs: [{ time: '14:00', message: '生成组件' }, { time: '14:30', message: '样式调整' }, { time: '14:45', message: '完成' }],
    },
    {
      id: 'ai6', taskId: 't14', provider: 'codex' as const, model: 'gpt-4o', status: 'failed' as const,
      startedAt: daysAgo(2, 16), endedAt: daysAgo(2, 16, 10), activeSeconds: 600, elapsedSeconds: 600, waitingHumanSeconds: 0,
      tokenInput: 4200, tokenOutput: 800, estimatedCost: 0.06, toolCallCount: 3, filesChanged: 0,
      errorMessage: '上下文不足，无法生成完整周报',
      logs: [{ time: '16:00', message: '尝试生成' }, { time: '16:08', message: '失败：上下文不足' }],
    },
    {
      id: 'ai7', taskId: 't19', provider: 'codex' as const, model: 'gpt-4o', status: 'cancelled' as const,
      startedAt: daysAgo(1, 14), endedAt: daysAgo(1, 14, 20), activeSeconds: 1200, elapsedSeconds: 1200, waitingHumanSeconds: 300,
      tokenInput: 6800, tokenOutput: 2400, estimatedCost: 0.14, toolCallCount: 5, filesChanged: 2,
      logs: [{ time: '14:00', message: '开始实现' }, { time: '14:15', message: '用户取消' }],
    },
    {
      id: 'ai8', taskId: 't15', provider: 'gemini' as const, model: 'gemini-2.0', status: 'cancelled' as const,
      startedAt: daysAgo(5, 11), endedAt: daysAgo(5, 11, 5), activeSeconds: 300, elapsedSeconds: 300, waitingHumanSeconds: 0,
      tokenInput: 2100, tokenOutput: 600, estimatedCost: 0.02, toolCallCount: 1, filesChanged: 0,
      logs: [{ time: '11:00', message: '开始分析' }, { time: '11:05', message: '已取消' }],
    },
  ]

  const dailyStats: AppState['dailyStats'] = Array.from({ length: 7 }, (_, i) => {
    const date = format(subDays(new Date(), 6 - i), 'yyyy-MM-dd')
    const base = {
      humanSeconds: 7200 + i * 600 + Math.floor(Math.random() * 1800),
      aiActiveSeconds: 5400 + i * 400 + Math.floor(Math.random() * 1200),
      waitingSeconds: 1200 + Math.floor(Math.random() * 1800),
      deepWorkSeconds: 3600 + i * 300,
      interruptionCount: 2 + Math.floor(Math.random() * 4),
      reworkSeconds: 600 + Math.floor(Math.random() * 900),
      completedTasks: 3 + Math.floor(Math.random() * 4),
      plannedMinutes: 360 + i * 20,
      actualHumanMinutes: 140 + i * 15 + Math.floor(Math.random() * 30),
    }
    return { date, ...base }
  })

  const experiments = [
    { id: 'e1', title: '明天上午 9:00–11:00 开启免打扰模式', description: '减少中断，提升深度工作时间', startDate: daysAgo(-1), durationDays: 7, status: 'active' as const, beforeMetric: '深度工作 1.2h/天', afterMetric: '深度工作 1.8h/天', effective: true },
    { id: 'e2', title: '每天固定两次 AI 审核时段', description: '10:30 和 16:00 集中审核 AI 输出', startDate: daysAgo(3), durationDays: 14, status: 'active' as const, beforeMetric: '平均等待 42 分钟', afterMetric: '平均等待 18 分钟', effective: true },
    { id: 'e3', title: '开发任务预估 ×1.4', description: '根据历史数据调整预估', startDate: daysAgo(-7), durationDays: 14, status: 'planned' as const, beforeMetric: '计划准确率 58%' },
  ]

  return {
    projects,
    goals,
    tasks,
    timeSessions,
    aiExecutions,
    dailyStats,
    experiments,
    settings: {
      name: '刻迹用户',
      weeklyTimeGoalHours: 40,
      workStartHour: 9,
      workEndHour: 18,
      defaultFocusMinutes: 45,
      streakDays: 12,
      theme: 'claude',
    },
    aiTools: [
      { provider: 'claude', name: 'Claude Code', connected: true, lastSync: hoursAgo(0, 1) },
      { provider: 'codex', name: 'Codex CLI', connected: true, lastSync: hoursAgo(0, 2) },
      { provider: 'chatgpt', name: 'ChatGPT', connected: false },
      { provider: 'gemini', name: 'Gemini', connected: false },
    ],
    activeFocus: {
      taskId: 't2',
      startedAt: hoursAgo(0, 42),
      accumulatedSeconds: 2520,
    },
    hasOnboarded: false,
    useSampleData: true,
  }
}

export function createEmptyData(): AppState {
  return {
    projects: [],
    goals: [],
    tasks: [],
    timeSessions: [],
    aiExecutions: [],
    dailyStats: [],
    experiments: [],
    settings: {
      name: '刻迹用户',
      weeklyTimeGoalHours: 40,
      workStartHour: 9,
      workEndHour: 18,
      defaultFocusMinutes: 45,
      streakDays: 0,
      theme: 'claude',
    },
    aiTools: [
      { provider: 'claude', name: 'Claude Code', connected: false },
      { provider: 'codex', name: 'Codex CLI', connected: false },
      { provider: 'chatgpt', name: 'ChatGPT', connected: false },
      { provider: 'gemini', name: 'Gemini', connected: false },
    ],
    hasOnboarded: false,
    useSampleData: false,
  }
}
