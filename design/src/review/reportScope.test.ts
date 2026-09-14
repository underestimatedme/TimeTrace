import { describe, expect, it } from 'vitest'
import { initialGlassState } from './glassModel'
import { plansForReport } from './reportScope'

describe('report project scope', () => {
  const tasks = [{id:'t1',projectId:'keji'}, {id:'t2',projectId:'valley'}]
  it('shows all projects from the Today report entry', () => {
    expect(plansForReport(initialGlassState().plans,tasks,null).map(p=>p.id)).toEqual(['p1','p2','p3','p4'])
  })
  it('does not leak another project into a project report or export', () => {
    expect(plansForReport(initialGlassState().plans,tasks,'valley').map(p=>p.id)).toEqual(['p4'])
  })
  it('shows an empty report for a project without tasks', () => {
    expect(plansForReport(initialGlassState().plans,tasks,'new')).toEqual([])
  })
})
