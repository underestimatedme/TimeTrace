import SwiftUI

/// AITools.tsx
struct AIToolsView: View {
    @Environment(\.theme) private var theme
    @Environment(AppStore.self) private var store

    private func description(_ provider: AIProvider) -> String {
        switch provider {
        case .claude: return "Claude Code 桌面 Agent"
        case .codex: return "Codex CLI 命令行工具"
        case .chatgpt: return "ChatGPT API 集成"
        case .gemini: return "Google Gemini API"
        case .other: return "其他 AI 工具"
        }
    }

    var body: some View {
        SubPageScaffold(title: "AI 工具管理") {
            Text("管理已连接的 AI 工具。第一版使用模拟连接状态，未来将支持真实接入。")
                .font(Typo.sans(Typo.sm)).foregroundStyle(theme.textSecondary).padding(.bottom, 24)

            VStack(spacing: 12) {
                ForEach(store.aiTools) { tool in
                    Card {
                        HStack(alignment: .center) {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(tool.name).font(Typo.sans(Typo.sm, weight: .medium)).foregroundStyle(theme.text)
                                Text(description(tool.provider)).font(Typo.sans(Typo.xs)).foregroundStyle(theme.textMuted)
                                if let last = tool.lastSync {
                                    Text("上次同步 \(Format.relative(last, now: store.now))")
                                        .font(Typo.sans(Typo.xs)).foregroundStyle(theme.textMuted).padding(.top, 2)
                                }
                            }
                            Spacer()
                            TintPill(text: tool.connected ? "已连接" : "未连接",
                                     color: tool.connected ? theme.success : theme.textMuted, horizontal: 10, vertical: 4)
                        }
                    }
                }
            }

            Card(borderColor: theme.accent.opacity(0.1)) {
                Text("刻迹默认不记录 Prompt、代码正文和 AI 回复正文，只记录时间、状态、用量和结果摘要。")
                    .font(Typo.sans(Typo.xs)).foregroundStyle(theme.textMuted).lineSpacing(4)
            }
            .padding(.top, 24)
        }
    }
}
