import SwiftUI

/// Appearance.tsx: 4 theme rows with swatches + preview block.
struct AppearanceView: View {
    @Environment(\.theme) private var theme
    @Environment(AppStore.self) private var store

    var body: some View {
        SubPageScaffold(title: "外观设置") {
            Text("刻迹始终保持深色优先。选择一套与你的 AI 工具气质相符的配色。")
                .font(Typo.sans(Typo.sm)).foregroundStyle(theme.textSecondary).padding(.bottom, 24)

            VStack(spacing: 12) {
                ForEach(ThemeMeta.all) { meta in themeRow(meta) }
            }

            SectionTitle("预览").padding(.top, 32)
            preview
        }
    }

    private func themeRow(_ meta: ThemeMeta) -> some View {
        let active = store.settings.theme == meta.id
        return Button {
            store.updateSettings { $0.theme = meta.id }
        } label: {
            HStack(spacing: 12) {
                HStack(spacing: 4) {
                    swatch(meta.swatchCard)
                    swatch(meta.swatchAccent)
                    swatch(meta.swatchAI)
                }
                .padding(8)
                .background(meta.swatchBg)
                .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                VStack(alignment: .leading, spacing: 2) {
                    HStack(spacing: 8) {
                        Text(meta.name).font(Typo.sans(Typo.sm, weight: .medium)).foregroundStyle(theme.text)
                        if active {
                            Image(systemName: "checkmark").font(.system(size: 9, weight: .bold))
                                .foregroundStyle(theme.bg).frame(width: 16, height: 16)
                                .background(theme.accent).clipShape(Circle())
                        }
                    }
                    Text(meta.tagline).font(Typo.sans(Typo.xs)).foregroundStyle(theme.textMuted)
                }
                Spacer(minLength: 0)
            }
            .padding(16)
            .background(active ? theme.accent.opacity(0.05) : .clear)
            .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous)
                .stroke(active ? theme.accent : theme.border, lineWidth: 1))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    private func swatch(_ color: Color) -> some View {
        RoundedRectangle(cornerRadius: 6, style: .continuous).fill(color).frame(width: 20, height: 32)
    }

    private var preview: some View {
        Card {
            VStack(spacing: 12) {
                HStack {
                    Text("设计刻迹首页").font(Typo.sans(Typo.sm)).foregroundStyle(theme.text)
                    Spacer()
                    TintPill(text: "进行中", color: theme.accent, radius: 6)
                }
                HStack {
                    Text("Codex 补充单元测试").font(Typo.sans(Typo.sm)).foregroundStyle(theme.text)
                    Spacer()
                    TintPill(text: "AI 执行中", color: theme.ai, radius: 6)
                }
                HStack(spacing: 8) {
                    TintPill(text: "已完成", color: theme.success, radius: 6, vertical: 4)
                    TintPill(text: "等待我", color: theme.warning, radius: 6, vertical: 4)
                    TintPill(text: "失败", color: theme.danger, radius: 6, vertical: 4)
                    Spacer()
                }
                .padding(.top, 4)
                ProgressBar(value: 66)
            }
        }
    }
}
