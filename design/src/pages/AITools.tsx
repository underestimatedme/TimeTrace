import { SubPageLayout } from '@/components/layout/SubPageLayout'
import { Card } from '@/components/ui/Card'
import { useStore } from '@/store/useStore'
import { formatRelative } from '@/lib/format'
import { cn } from '@/lib/utils'
import type { AIProvider } from '@/types'

const providerInfo: Record<AIProvider, { desc: string }> = {
  claude: { desc: 'Claude Code 桌面 Agent' },
  codex: { desc: 'Codex CLI 命令行工具' },
  chatgpt: { desc: 'ChatGPT API 集成' },
  gemini: { desc: 'Google Gemini API' },
  other: { desc: '其他 AI 工具' },
}

export function AIToolsPage() {
  const { aiTools } = useStore()

  return (
    <SubPageLayout title="AI 工具管理">
      <p className="text-sm text-text-secondary mb-6">
        管理已连接的 AI 工具。第一版使用模拟连接状态，未来将支持真实接入。
      </p>

      <div className="space-y-3">
        {aiTools.map((tool) => (
          <Card key={tool.provider}>
            <div className="flex items-center justify-between">
              <div>
                <h3 className="text-sm font-medium text-text">{tool.name}</h3>
                <p className="text-xs text-text-muted mt-0.5">{providerInfo[tool.provider].desc}</p>
                {tool.lastSync && (
                  <p className="text-xs text-text-muted mt-1">上次同步 {formatRelative(tool.lastSync)}</p>
                )}
              </div>
              <span className={cn(
                'text-xs px-2.5 py-1 rounded-full',
                tool.connected ? 'bg-success/20 text-success' : 'bg-text-muted/20 text-text-muted'
              )}>
                {tool.connected ? '已连接' : '未连接'}
              </span>
            </div>
          </Card>
        ))}
      </div>

      <Card className="mt-6 border-accent/10">
        <p className="text-xs text-text-muted leading-relaxed">
          刻迹默认不记录 Prompt、代码正文和 AI 回复正文，只记录时间、状态、用量和结果摘要。
        </p>
      </Card>
    </SubPageLayout>
  )
}
