export const STORAGE_KEY = 'timetrace-app-state'

export function clearState(): void {
  try {
    localStorage.removeItem(STORAGE_KEY)
  } catch {
    // ignore
  }
}
