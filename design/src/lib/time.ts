import { useEffect, useState } from 'react'

export function elapsedSeconds(startedAt: string, accumulatedSeconds: number, nowMillis: number): number {
  const liveSeconds = Math.max(0, Math.floor((nowMillis - new Date(startedAt).getTime()) / 1000))
  return liveSeconds + accumulatedSeconds
}

export function sessionEndMillis(endedAt: string | undefined, nowMillis: number): number {
  return endedAt ? new Date(endedAt).getTime() : nowMillis
}

export function useNow(intervalMs = 1000): number {
  const [nowMillis, setNowMillis] = useState(() => Date.now())

  useEffect(() => {
    const interval = window.setInterval(() => setNowMillis(Date.now()), intervalMs)
    return () => window.clearInterval(interval)
  }, [intervalMs])

  return nowMillis
}
