import SwiftUI

/// AITools.tsx
struct AIToolsView: View {
    @Environment(\.theme) private var theme
    @Environment(AppStore.self) private var store
    @Environment(SyncEngine.self) private var sync
    @Environment(RemoteExecutionClient.self) private var remote
    @State private var pairingCode = ""
    @State private var pairingMessage: String?

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
            Text("通过 Valley 将 iPhone 上的任务安全派发到已授权的 Mac；Claude/Codex 账号始终留在电脑本地。")
                .font(Typo.sans(Typo.sm)).foregroundStyle(theme.textSecondary).padding(.bottom, 24)

            if !sync.isLoggedIn {
                Card(borderColor: theme.accent.opacity(0.2)) {
                    Text("请先在账号页登录，再绑定电脑。游客账号不能批准 Runner。")
                        .font(Typo.sans(Typo.sm)).foregroundStyle(theme.textSecondary)
                }
            } else {
                Card(borderColor: theme.ai.opacity(0.25)) {
                    VStack(alignment: .leading, spacing: 12) {
                        Text("绑定新电脑").font(Typo.sans(Typo.sm, weight: .medium)).foregroundStyle(theme.text)
                        Text("在 Mac 运行 `keji cloud login`，然后输入屏幕上的 8 位授权码。")
                            .font(Typo.sans(Typo.xs)).foregroundStyle(theme.textMuted)
                        AppTextField(placeholder: "例如 A1B2C3D4", text: $pairingCode)
                            .textInputAutocapitalization(.characters)
                            .accessibilityIdentifier("runner-pairing-code")
                        AppButton("批准绑定", variant: .accent, fullWidth: true,
                                  disabled: pairingCode.trimmingCharacters(in: .whitespaces).count != 8) {
                            approvePairing()
                        }
                        .accessibilityIdentifier("runner-pairing-submit")
                        if let pairingMessage {
                            Text(pairingMessage).font(Typo.sans(Typo.xs)).foregroundStyle(theme.textSecondary)
                        }
                    }
                }
            }

            if remote.isLoading {
                ProgressView("正在刷新电脑状态…").frame(maxWidth: .infinity).padding(.vertical, 16)
            }
            ForEach(remote.runners) { inventory in
                Card {
                    VStack(alignment: .leading, spacing: 8) {
                        HStack {
                            Text(inventory.runner.name).font(Typo.sans(Typo.sm, weight: .medium)).foregroundStyle(theme.text)
                            Spacer()
                            TintPill(text: inventory.runner.status == "online" ? "在线" : "离线",
                                     color: inventory.runner.status == "online" ? theme.success : theme.textMuted)
                        }
                        Text("\(inventory.workspaces.count) 个仓库 · \(inventory.tools.map { $0.provider.label }.joined(separator: " / "))")
                            .font(Typo.sans(Typo.xs)).foregroundStyle(theme.textMuted)
                    }
                }
            }

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
                Text("任务 Prompt 会经 HTTPS 发送并加密存储于 Valley；代码、CLI 登录凭据和完整输出不会离开电脑。")
                    .font(Typo.sans(Typo.xs)).foregroundStyle(theme.textMuted).lineSpacing(4)
            }
            .padding(.top, 24)
        }
        .task { if sync.isLoggedIn { await remote.loadRunners() } }
    }

    private func approvePairing() {
        pairingMessage = "正在批准…"
        _Concurrency.Task {
            do {
                try await remote.approve(code: pairingCode)
                pairingCode = ""
                pairingMessage = "电脑已绑定，可以远程派发任务。"
            } catch {
                pairingMessage = error.localizedDescription
            }
        }
    }
}
