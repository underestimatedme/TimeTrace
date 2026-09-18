import SwiftUI

/// `bg-bg-card rounded-2xl border border-border p-4`
struct Card<Content: View>: View {
    @Environment(\.theme) private var theme
    var borderColor: Color?
    var padding: CGFloat = Glass.cardPadding
    var radius: CGFloat = Glass.cardRadius
    @ViewBuilder var content: () -> Content

    init(borderColor: Color? = nil, padding: CGFloat = Glass.cardPadding, radius: CGFloat = Glass.cardRadius,
         @ViewBuilder content: @escaping () -> Content) {
        self.borderColor = borderColor
        self.padding = padding
        self.radius = radius
        self.content = content
    }

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: radius, style: .continuous)
        return VStack(alignment: .leading, spacing: 0) { content() }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(padding)
            // --g-panel 的半透明面板压在模糊背景上，再落一层低饱和冷色投影。
            .background(theme.panel, in: shape)
            .background(.ultraThinMaterial, in: shape)
            .clipShape(shape)
            .overlay(shape.stroke(borderColor ?? theme.border, lineWidth: 1))
            // inset 0 1px 2px #fff —— 顶部的一道白色内高光，玻璃面板的关键细节。
            .overlay(
                shape.strokeBorder(
                    LinearGradient(colors: [Color.white.opacity(theme.isDark ? 0.10 : 0.9), .clear],
                                   startPoint: .top, endPoint: .center),
                    lineWidth: 1)
            )
            .shadow(color: theme.shadowColor, radius: Theme.shadowBlur, y: Theme.shadowOffsetY)
    }
}

/// Two-line label/value card used across detail pages (`Card` with `text-xs` label and mono value).
struct StatCard: View {
    @Environment(\.theme) private var theme
    let label: String
    let value: String
    var valueColor: Color?
    var valueSize: CGFloat = Typo.sm

    var body: some View {
        Card {
            Text(label).font(Typo.sans(Typo.xs)).foregroundStyle(theme.textMuted)
            Text(value)
                .font(Typo.mono(valueSize))
                .foregroundStyle(valueColor ?? theme.text)
                .lineLimit(1)
                .minimumScaleFactor(0.7)
        }
    }
}
