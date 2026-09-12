import type { ThemeName } from '@/types'

export interface ThemeMeta {
  id: ThemeName
  name: string
  tagline: string
  /** Preview swatches: [背景, 卡片, 强调(人), AI] */
  swatches: { bg: string; card: string; accent: string; ai: string }
}

export const THEMES: ThemeMeta[] = [
  {
    id: 'claude',
    name: '琥珀 · Claude',
    tagline: '暖色、克制、夜色中的微光',
    swatches: { bg: '#0a0a0b', card: '#1a1a1e', accent: '#d4845a', ai: '#6b8cae' },
  },
  {
    id: 'codex',
    name: '翠绿 · Codex',
    tagline: '中性冷调，OpenAI 风格的清爽绿',
    swatches: { bg: '#0c0d0d', card: '#1b1d1d', accent: '#19c37d', ai: '#54b5c4' },
  },
  {
    id: 'cursor',
    name: '靛蓝 · Cursor',
    tagline: '冷峻蓝紫，理性的科技质感',
    swatches: { bg: '#0a0c11', card: '#181d29', accent: '#5b8dff', ai: '#b08cff' },
  },
  {
    id: 'light',
    name: '晨光 · Light',
    tagline: '纸张般的暖白，日间清晰可读',
    swatches: { bg: '#f5f2ec', card: '#ffffff', accent: '#c2643a', ai: '#4a6fa0' },
  },
]

export function getThemeMeta(id: ThemeName): ThemeMeta {
  return THEMES.find((t) => t.id === id) ?? THEMES[0]
}

export function applyTheme(id: ThemeName): void {
  document.documentElement.setAttribute('data-theme', id)
}
