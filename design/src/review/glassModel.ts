export type Status = 'ready' | 'running' | 'waiting' | 'review' | 'accepted' | 'cancelled'
export type GlassPlan = {id: string; taskId: string; title: string; tool: string; status: Status; depends: string[]; criteria: string[]; priority: number}
export type GlassState = {plans: GlassPlan[]; quotaRestored: boolean}
export function initialGlassState(): GlassState { return {plans: [
  {id:'p1',taskId:'t1',title:'定义账号与额度窗口',tool:'Codex',status:'accepted',depends:[],criteria:['支持多窗口'],priority:1},
  {id:'p2',taskId:'t1',title:'完成额度数据采集',tool:'Claude Code',status:'accepted',depends:[],criteria:['采样来源可追溯'],priority:1},
  {id:'p3',taskId:'t1',title:'额度数据模型',tool:'Codex',status:'review',depends:['p1','p2'],criteria:['短时与周额度分别展示','未知额度不显示为满额','重复采样不会重复计数'],priority:1},
  {id:'p4',taskId:'t2',title:'远程运行日志与恢复验证',tool:'Claude Code',status:'waiting',depends:[],criteria:['保留原会话','不重复启动任务','没有额外付费'],priority:2},
],quotaRestored:false} }
export function transitionPlan(state: GlassState, id: string, action: 'run' | 'finish' | 'accept' | 'cancel'): {state: GlassState; error?: string} {
  const plan = state.plans.find(p => p.id === id)
  if (!plan) return {state,error:'missing'}
  if (action === 'run' && plan.depends.some(dep => state.plans.find(p => p.id === dep)?.status !== 'accepted')) return {state,error:'dependencies'}
  const next: Partial<Record<typeof action, Status>> = {
    run: plan.status === 'ready' || (plan.status === 'waiting' && state.quotaRestored) ? 'running' : undefined,
    finish: plan.status === 'running' ? 'review' : undefined,
    accept: plan.status === 'review' ? 'accepted' : undefined,
    cancel: !['accepted','cancelled'].includes(plan.status) ? 'cancelled' : undefined,
  }
  if (!next[action]) return {state,error:'invalid_transition'}
  return {state:{...state,plans:state.plans.map(p => p.id === id ? {...p,status:next[action]!} : p)}}
}
export function restoreQuota(state: GlassState, weekBlocked: boolean, autoResume: boolean): GlassState {
  return {...state,quotaRestored:!weekBlocked,plans:state.plans.map(p => p.status === 'waiting' && !weekBlocked && autoResume ? {...p,status:'running'} : p)}
}
export function validateAuth(identifier: string, code: string, consent: boolean): string | null {
  if (!consent) return 'consent'
  if (!/^[^\s@]+@[^\s@]+\.[^\s@]+$/.test(identifier.trim()) && !/^\+?[0-9]{7,15}$/.test(identifier.trim())) return 'identifier'
  return code === '246810' ? null : 'code'
}
export function validateFeedback(value: string): boolean { return value.trim().length >= 10 && value.length <= 1000 }
