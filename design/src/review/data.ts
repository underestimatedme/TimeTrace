export type Page = 'today' | 'projects' | 'timeline' | 'ai' | 'reports'
export type PlanStatus = '待执行' | '等待额度' | '待验收' | '已验收' | '执行中'
export type Plan = { id: string; title: string; tool: string; status: PlanStatus; priority: string; minutes: number; criteria: string[] }
export const initialPlans: Plan[] = [
  { id: '01', title: '统一额度窗口与账号数据', tool: 'Codex', status: '待验收', priority: 'P1', minutes: 35, criteria: ['支持短时与周额度同时展示', '缺失数据明确标为未知', '重复采样不会重复计算额度'] },
  { id: '02', title: '完成 AI 额度卡片与倒计时', tool: 'Claude Code', status: '等待额度', priority: 'P1', minutes: 45, criteria: ['展示额度采样时间', '恢复时间包含本地时区', '周额度耗尽时保持等待'] },
  { id: '03', title: '验证跨窗口恢复与取消', tool: 'Codex', status: '待执行', priority: 'P1', minutes: 30, criteria: ['取消后不会被定时器恢复', '原会话继续且没有重复执行', '不产生额外付费'] },
]
export const pages: { id: Page; label: string; eyebrow: string; title: string; description: string }[] = [
  { id: 'today', label: '今日', eyebrow: 'MONDAY, SEPTEMBER 14', title: '每一份投入，走向交付。', description: '目标优先，随后是个人行动、AI 运行和待审核事项。让你打开 App 就知道下一步做什么。' },
  { id: 'projects', label: '项目', eyebrow: 'PROJECTS & MILESTONES', title: '从目标，到每一步。', description: '项目 → 任务 → Plan。版本目标关联任务，Plan 承载执行和验收，不再增加第四级目录。' },
  { id: 'timeline', label: '时间线', eyebrow: 'HUMAN × AI', title: '不同节奏，同一条时间线。', description: '人工投入和 AI 活跃时间分开统计。等待额度、等待审核和真实执行有明确的视觉区别。' },
  { id: 'ai', label: 'AI', eyebrow: 'YOUR AI WORKFORCE', title: '让额度跟上你的计划。', description: '个人账号额度与公共重置信号分开。额度恢复后续跑原会话，并始终遵守零额外付费。' },
  { id: 'reports', label: '报告', eyebrow: 'PROGRESS, WITH PROOF', title: '看见完成，而不只是忙碌。', description: '日报以验收和提交记录为依据。任务价值、模型适配和生产力是三个不同的评分。' },
]
export const tools = [
  { name: 'Codex', glyph: 'C', color: 'blue', remaining: 62, status: '可执行', detail: '短时剩余 62% · 周剩余 41%', reset: '17:30 恢复', capability: '额度 · 派发 · 恢复' },
  { name: 'Claude Code', glyph: '✳', color: 'amber', remaining: 0, status: '等待恢复', detail: '短时已用尽 · 周剩余 28%', reset: '14:30 预计恢复', capability: '采样 · 派发 · 恢复' },
  { name: 'Cursor', glyph: '↗', color: 'violet', remaining: 34, status: '仅管理', detail: '月额度剩余 34% · 手动录入', reset: '9 月 22 日恢复', capability: '记录 · 提醒' },
  { name: 'Gemini CLI', glyph: '✦', color: 'green', remaining: null, status: '额度未知', detail: '尚未取得可信额度样本', reset: '恢复时间未知', capability: '记录 · 待适配' },
]
