import SwiftUI

/// `bg-bg-card rounded-2xl border border-border p-4`
struct Card<Content: View>: View {
    @Environment(\.theme) private var theme
    var borderColor: Color?
    var padding: CGFloat = 16
    var radius: CGFloat = 16
    @ViewBuilder var content: () -> Content

    init(borderColor: Color? = nil, padding: CGFloat = 16, radius: CGFloat = 16,
         @ViewBuilder content: @escaping () -> Content) {
        self.borderColor = borderColor
        self.padding = padding
        self.radius = radius
        self.content = content
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) { content() }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(padding)
            .background(theme.bgCard)
            .clipShape(RoundedRectangle(cornerRadius: radius, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: radius, style: .continuous)
                    .stroke(borderColor ?? theme.border, lineWidth: 1)
            )
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
