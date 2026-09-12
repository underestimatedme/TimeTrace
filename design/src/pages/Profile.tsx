import { useNavigate } from 'react-router-dom'
import {
  User, Target, Clock, Bot, Shield, Download, Bell, Palette, Info, ChevronRight, FolderOpen, RotateCcw,
} from 'lucide-react'
import { AppLayout, PageLayout } from '@/components/layout/Layout'
import { Card } from '@/components/ui/Card'
import { Button } from '@/components/ui/Button'
import { useStore } from '@/store/useStore'
import { formatDuration } from '@/lib/format'
import { getHumanSeconds, getAIActiveSeconds } from '@/lib/stats'
import { getThemeMeta } from '@/lib/themes'
import { format } from 'date-fns'

export function ProfilePage() {
  const navigate = useNavigate()
  const { settings, timeSessions, resetToSample, clearAll, updateSettings } = useStore()

  const today = format(new Date(), 'yyyy-MM-dd')
  const todayHuman = getHumanSeconds(timeSessions, today)
  const todayAI = getAIActiveSeconds(timeSessions, today)

  const menuItems = [
    { icon: FolderOpen, label: '项目与目标', path: '/projects' },
    { icon: Target, label: '每周时间目标', value: `${settings.weeklyTimeGoalHours} 小时` },
    { icon: Clock, label: '工作时间设置', value: `${settings.workStartHour}:00 – ${settings.workEndHour}:00` },
    { icon: Bot, label: 'AI 工具管理', path: '/ai-tools' },
    { icon: Shield, label: '数据与隐私' },
    { icon: Download, label: '导出数据' },
    { icon: Bell, label: '通知设置' },
    { icon: Palette, label: '外观设置', value: getThemeMeta(settings.theme).name, path: '/appearance' },
    { icon: Info, label: '关于刻迹', value: 'v0.1.0' },
  ]

  return (
    <AppLayout>
      <PageLayout>
        <div className="flex items-center gap-4 mb-6">
          <div className="w-16 h-16 rounded-2xl bg-accent/20 flex items-center justify-center">
            <User size={28} className="text-accent" />
          </div>
          <div>
            <h1 className="text-xl font-medium text-text">{settings.name}</h1>
            <p className="text-sm text-text-secondary">连续专注 {settings.streakDays} 天</p>
          </div>
        </div>

        <div className="grid grid-cols-2 gap-2 mb-6">
          <Card>
            <p className="text-xs text-text-muted">今日人工</p>
            <p className="text-lg font-mono text-accent">{formatDuration(todayHuman)}</p>
          </Card>
          <Card>
            <p className="text-xs text-text-muted">今日 AI</p>
            <p className="text-lg font-mono text-ai">{formatDuration(todayAI)}</p>
          </Card>
        </div>

        <Card className="mb-4">
          <div className="flex items-center justify-between mb-3">
            <span className="text-sm text-text-secondary">默认专注时长</span>
            <span className="text-sm font-mono text-text">{settings.defaultFocusMinutes} 分钟</span>
          </div>
          <input
            type="range"
            min={15}
            max={90}
            step={5}
            value={settings.defaultFocusMinutes}
            onChange={(e) => updateSettings({ defaultFocusMinutes: Number(e.target.value) })}
            className="w-full accent-accent"
          />
        </Card>

        <div className="space-y-1 mb-6">
          {menuItems.map((item) => (
            <button
              key={item.label}
              onClick={() => item.path && navigate(item.path)}
              className="w-full flex items-center gap-3 px-4 py-3.5 rounded-xl hover:bg-bg-hover transition-colors"
            >
              <item.icon size={18} className="text-text-muted" />
              <span className="text-sm text-text flex-1 text-left">{item.label}</span>
              {item.value && <span className="text-xs text-text-muted">{item.value}</span>}
              {item.path && <ChevronRight size={16} className="text-text-muted" />}
            </button>
          ))}
        </div>

        <div className="space-y-2">
          <Button variant="secondary" className="w-full" onClick={resetToSample}>
            <RotateCcw size={16} /> 恢复示例数据
          </Button>
          <Button variant="danger" className="w-full" onClick={clearAll}>
            清除所有数据
          </Button>
        </div>
      </PageLayout>
    </AppLayout>
  )
}
