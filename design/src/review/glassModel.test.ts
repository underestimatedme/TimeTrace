import { describe, expect, it } from 'vitest'
import { initialGlassState, transitionPlan, validateAuth, validateFeedback, restoreQuota } from './glassModel'

describe('review workflow', () => {
  it('does not dispatch before dependencies are accepted', () => {
    const state = initialGlassState()
    state.plans[0].status = 'review'
    expect(transitionPlan(state, 'p3', 'run').error).toBe('dependencies')
  })
  it('only accepts work awaiting review and preserves original tool', () => {
    const state = initialGlassState()
    const result = transitionPlan(state, 'p3', 'accept')
    expect(result.state.plans.find(p => p.id === 'p3')?.status).toBe('accepted')
    expect(result.state.plans.find(p => p.id === 'p3')?.tool).toBe('Codex')
    expect(transitionPlan(state, 'p4', 'accept').error).toBe('invalid_transition')
  })
  it('keeps quota-blocked work paused while weekly limit is exhausted', () => {
    const state = initialGlassState()
    expect(restoreQuota(state, true, true).plans.find(p => p.id === 'p4')?.status).toBe('waiting')
  })
  it('refreshes without running when automatic resume is disabled', () => {
    const result = restoreQuota(initialGlassState(), false, false)
    expect(result.quotaRestored).toBe(true)
    expect(result.plans.find(p => p.id === 'p4')?.status).toBe('waiting')
  })
  it('never resumes a cancelled plan', () => {
    const state = initialGlassState()
    state.plans[3].status = 'cancelled'
    expect(restoreQuota(state, false, true).plans[3].status).toBe('cancelled')
  })
  it('rejects signup without consent and malformed identifiers', () => {
    expect(validateAuth('joey@example.com', '246810', false)).toBe('consent')
    expect(validateAuth('not-an-email', '246810', true)).toBe('identifier')
    expect(validateAuth('joey@example.com', '123456', true)).toBe('code')
    expect(validateAuth('joey@example.com', '246810', true)).toBe(null)
  })
  it('requires useful feedback text, not only whitespace', () => {
    expect(validateFeedback('   ')).toBe(false)
    expect(validateFeedback('时间线中希望可以按项目进行筛选')).toBe(true)
  })
})
