import { format, formatDistanceToNow, isToday, parseISO } from 'date-fns'
import { zhCN } from 'date-fns/locale'

export function formatDuration(seconds: number): string {
  const h = Math.floor(seconds / 3600)
  const m = Math.floor((seconds % 3600) / 60)
  const s = seconds % 60
  if (h > 0) return `${h} 小时 ${m} 分钟`
  if (m > 0) return s > 0 ? `${m} 分 ${s} 秒` : `${m} 分钟`
  return `${s} 秒`
}

export function formatDurationShort(seconds: number): string {
  const h = Math.floor(seconds / 3600)
  const m = Math.floor((seconds % 3600) / 60)
  if (h > 0) return `${h}h ${m}m`
  return `${m}m`
}

export function formatTime(iso: string): string {
  return format(parseISO(iso), 'HH:mm')
}

export function formatDate(iso: string): string {
  return format(parseISO(iso), 'M月d日 EEEE', { locale: zhCN })
}

export function formatDateShort(iso: string): string {
  return format(parseISO(iso), 'M/d')
}

export function formatRelative(iso: string): string {
  return formatDistanceToNow(parseISO(iso), { addSuffix: true, locale: zhCN })
}

export function isDateToday(iso: string): boolean {
  return isToday(parseISO(iso))
}

export function getGreeting(): string {
  const hour = new Date().getHours()
  if (hour < 6) return '夜深了'
  if (hour < 12) return '早上好'
  if (hour < 14) return '中午好'
  if (hour < 18) return '下午好'
  return '晚上好'
}

export function formatLeverage(leverage: number): string {
  return `${leverage.toFixed(1)}×`
}

export function formatPercent(value: number): string {
  return `${Math.round(value * 100)}%`
}

export function formatCost(cost: number): string {
  return `$${cost.toFixed(2)}`
}
