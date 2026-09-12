import { Check } from 'lucide-react'
import { SubPageLayout } from '@/components/layout/SubPageLayout'
import { useStore } from '@/store/useStore'
import { THEMES, applyTheme } from '@/lib/themes'
import { cn } from '@/lib/utils'
import type { ThemeName } from '@/types'

export function AppearancePage() {
  const theme = useStore((s) => s.settings.theme)
  const updateSettings = useStore((s) => s.updateSettings)

  const handleSelect = (id: ThemeName) => {
    applyTheme(id)
    updateSettings({ theme: id })
  }

  return (
    <SubPageLayout title="外观设置">
      <p className="text-sm text-text-secondary mb-6">
        刻迹始终保持深色优先。选择一套与你的 AI 工具气质相符的配色。
      </p>

      <div className="space-y-3">
        {THEMES.map((t) => {
          const active = theme === t.id
          return (
            <button
              key={t.id}
              onClick={() => handleSelect(t.id)}
              className={cn(
                'w-full text-left rounded-2xl border p-4 transition-colors',
                active ? 'border-accent bg-accent/5' : 'border-border hover:bg-bg-hover'
              )}
            >
              <div className="flex items-center gap-3">
                <div
                  className="flex items-center gap-1 rounded-xl p-2 shrink-0"
                  style={{ background: t.swatches.bg }}
                >
                  <span className="w-5 h-8 rounded-md" style={{ background: t.swatches.card }} />
                  <span className="w-5 h-8 rounded-md" style={{ background: t.swatches.accent }} />
                  <span className="w-5 h-8 rounded-md" style={{ background: t.swatches.ai }} />
                </div>
                <div className="flex-1 min-w-0">
                  <div className="flex items-center gap-2">
                    <h3 className="text-sm font-medium text-text">{t.name}</h3>
                    {active && (
                      <span className="flex items-center justify-center w-4 h-4 rounded-full bg-accent text-bg">
                        <Check size={11} strokeWidth={3} />
                      </span>
                    )}
                  </div>
                  <p className="text-xs text-text-muted mt-0.5">{t.tagline}</p>
                </div>
              </div>
            </button>
          )
        })}
      </div>

      <div className="mt-8">
        <p className="text-xs font-medium text-text-secondary uppercase tracking-wider mb-3">
          预览
        </p>
        <div className="rounded-2xl border border-border bg-bg-card p-4 space-y-3">
          <div className="flex items-center justify-between">
            <span className="text-sm text-text">设计刻迹首页</span>
            <span className="text-xs px-2 py-0.5 rounded-md bg-accent/20 text-accent">进行中</span>
          </div>
          <div className="flex items-center justify-between">
            <span className="text-sm text-text">Codex 补充单元测试</span>
            <span className="text-xs px-2 py-0.5 rounded-md bg-ai/20 text-ai">AI 执行中</span>
          </div>
          <div className="flex gap-2 pt-1">
            <span className="text-xs px-2 py-1 rounded-md bg-success/20 text-success">已完成</span>
            <span className="text-xs px-2 py-1 rounded-md bg-warning/20 text-warning">等待我</span>
            <span className="text-xs px-2 py-1 rounded-md bg-danger/20 text-danger">失败</span>
          </div>
          <div className="h-1 rounded-full bg-bg-elevated overflow-hidden">
            <div className="h-full w-2/3 bg-accent rounded-full" />
          </div>
        </div>
      </div>
    </SubPageLayout>
  )
}
