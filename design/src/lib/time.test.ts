import { describe, expect, it } from 'vitest'
import { elapsedSeconds, sessionEndMillis } from './time'

describe('elapsedSeconds', () => {
  it('adds accumulated time to the non-negative live interval', () => {
    expect(elapsedSeconds('2026-09-12T10:00:00.000Z', 25, Date.parse('2026-09-12T10:00:10.900Z'))).toBe(35)
    expect(elapsedSeconds('2026-09-12T10:00:10.000Z', 25, Date.parse('2026-09-12T10:00:00.000Z'))).toBe(25)
  })
})

describe('sessionEndMillis', () => {
  it('uses the supplied clock only for an open session', () => {
    const now = Date.parse('2026-09-12T10:00:10.000Z')
    expect(sessionEndMillis('2026-09-12T10:00:04.000Z', now)).toBe(Date.parse('2026-09-12T10:00:04.000Z'))
    expect(sessionEndMillis(undefined, now)).toBe(now)
  })
})
