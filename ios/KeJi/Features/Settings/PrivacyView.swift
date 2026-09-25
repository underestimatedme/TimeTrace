import SwiftUI

/// Explains what syncs, where data lives, and keeps diagnostics opt-in.
struct PrivacyView: View {
    @Environment(\.theme) private var theme
    @Environment(AppStore.self) private var store
    @State private var usageStatsEnabled = UsageEvents.shared.isEnabled

    var body: some View {
        SubPageScaffold(title: "隐私") {
            SectionTitle("同步范围")
            Card {
                Text("项目、任务、Plan、时间记录会同步到你的账号；工具凭据与代码始终留在电脑本地，绝不上传。")
                    .font(Typo.sans(Typo.sm)).foregroundStyle(theme.textSecondary)
            }
            .padding(.bottom, 20)

            SectionTitle("诊断")
            Card {
                Toggle(isOn: Binding(
                    get: { store.preferences.diagnosticsEnabled },
                    set: { value in store.updatePreferences { $0.diagnosticsEnabled = value } }
                )) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("发送诊断信息").font(Typo.sans(Typo.sm)).foregroundStyle(theme.text)
                        Text("默认关闭；开启后诊断逐次确认、脱敏，不含代码或环境变量。")
                            .font(Typo.sans(Typo.xs)).foregroundStyle(theme.textMuted)
                    }
                }
                .tint(theme.accent)
                .accessibilityIdentifier("privacy.diagnostics")
            }
            .padding(.bottom, 20)

            SectionTitle("使用统计")
            Card {
                Toggle(isOn: Binding(
                    get: { usageStatsEnabled },
                    set: { value in
                        usageStatsEnabled = value
                        UsageEvents.shared.isEnabled = value
                    }
                )) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("帮助改进刻迹（匿名使用统计）").font(Typo.sans(Typo.sm)).foregroundStyle(theme.text)
                        Text("只记录打开了哪些页面、派发与配对是否成功这类操作；不含任务标题、提示词、代码、仓库路径或账号信息。关闭后立即停止并清空未上传的记录。")
                            .font(Typo.sans(Typo.xs)).foregroundStyle(theme.textMuted)
                    }
                }
                .tint(theme.accent)
                .accessibilityIdentifier("privacy.usageStats")
            }
            .padding(.bottom, 20)

            SectionTitle("数据导出与注销")
            Card {
                Text("导出通过系统分享生成，失败可重试。注销需二次身份确认，会列出范围与保留期限，并撤销会话与 Runner 授权；不会删除厂商 AI 账号。")
                    .font(Typo.sans(Typo.sm)).foregroundStyle(theme.textSecondary)
            }
        }
    }
}
