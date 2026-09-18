import SwiftUI

/// 主题与动效（design/src/review/AccountCenter.tsx 的 theme 页）：
/// 冰晶白 / 深海蓝 / 跟随系统，外加强调色与减少动态效果。
struct AppearanceView: View {
    @Environment(\.theme) private var theme
    @Environment(AppStore.self) private var store

    var body: some View {
        SubPageScaffold(title: "主题与动效") {
            Text("清晨或深夜，都有舒适的工作界面。")
                .font(Typo.sans(Typo.sm)).foregroundStyle(theme.textSecondary).padding(.bottom, 20)

            HStack(spacing: 10) {
                ForEach(ThemeMode.allCases) { mode in modeCard(mode) }
            }
            .padding(.bottom, 24)

            SectionTitle("强调色")
            GlassSegments(options: AccentPalette.allCases.map { ($0, $0.label) },
                          selection: Binding(
                            get: { store.preferences.accent },
                            set: { next in store.updatePreferences { $0.accent = next } }))
                .padding(.bottom, 24)
                .accessibilityIdentifier("appearance.accent")

            Card {
                Toggle(isOn: Binding(
                    get: { store.preferences.reduceMotion },
                    set: { on in store.updatePreferences { $0.reduceMotion = on } })) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("减少动态效果").font(Typo.sans(Typo.sm)).foregroundStyle(theme.text)
                        Text("关闭进场、浮动与脉冲，保留状态反馈")
                            .font(Typo.sans(Typo.xs)).foregroundStyle(theme.textMuted)
                    }
                }
                .tint(theme.accent)
                .accessibilityIdentifier("appearance.reduceMotion")
            }

            Text("也会尊重系统的「减少动态效果」偏好。主题与显示设置保存在本机。")
                .font(Typo.sans(Typo.xs)).foregroundStyle(theme.textMuted).padding(.top, 12)
        }
    }

    private func modeCard(_ mode: ThemeMode) -> some View {
        let active = store.preferences.themeMode == mode
        let preview = resolveTheme(mode: mode, systemIsDark: mode == .dark, accent: store.preferences.accent)
        return Button {
            store.updatePreferences { $0.themeMode = mode }
        } label: {
            VStack(spacing: 12) {
                Image(systemName: mode == .light ? "sun.max" : mode == .dark ? "moon" : "iphone")
                    .accessibilityHidden(true)
                    .font(.system(size: 24, weight: .light))
                    .foregroundStyle(active ? theme.accent : theme.textSecondary)
                Text(mode.label)
                    .font(Typo.sans(Typo.xs, weight: .medium))
                    .foregroundStyle(active ? theme.accent : theme.textSecondary)
                HStack(spacing: 3) {
                    swatch(preview.bg); swatch(preview.accent); swatch(preview.ai)
                }
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 20)
            .background(active ? theme.bgHover : theme.panel)
            .clipShape(RoundedRectangle(cornerRadius: 15, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 15, style: .continuous)
                    .stroke(active ? theme.accent : theme.border, lineWidth: 1)
            )
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier("theme.\(mode.rawValue)")
        .accessibilityValue(active ? "已选择" : "未选择")
    }

    private func swatch(_ color: Color) -> some View {
        Circle().fill(color).frame(width: 10, height: 10)
            .overlay(Circle().stroke(theme.border, lineWidth: 0.5))
    }
}
