import SwiftUI

/// `text-xs font-medium text-text-secondary uppercase tracking-wider mb-3`
struct SectionTitle: View {
    @Environment(\.theme) private var theme
    let text: String
    var trailing: String?

    init(_ text: String, trailing: String? = nil) { self.text = text; self.trailing = trailing }

    /// .gl-section-heading h2 —— 正常大小写的 14px/600，右侧可带一条小字说明。
    var body: some View {
        HStack(alignment: .firstTextBaseline) {
            Text(text)
                .font(Typo.sans(Glass.sectionTitle, weight: .semibold))
                .foregroundStyle(theme.text)
            if let trailing {
                Spacer(minLength: 8)
                Text(trailing).font(Typo.sans(Glass.tiny)).foregroundStyle(theme.textMuted)
            }
        }
        .padding(.bottom, 10)
    }
}

struct ProgressBar: View {
    @Environment(\.theme) private var theme
    /// 0...100
    let value: Double
    var height: CGFloat = 4

    var body: some View {
        GeometryReader { geo in
            ZStack(alignment: .leading) {
                Capsule().fill(theme.bgElevated)
                Capsule().fill(theme.accent)
                    .frame(width: geo.size.width * CGFloat(min(100, max(0, value)) / 100))
                    .animation(.easeInOut(duration: 0.5), value: value)
            }
        }
        .frame(height: height)
    }
}

/// `bg-bg-card rounded-xl border border-border p-3` with mono value.
struct MetricCard: View {
    @Environment(\.theme) private var theme
    let label: String
    let value: String
    var sub: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(label).font(Typo.sans(Typo.xs)).foregroundStyle(theme.textMuted).padding(.bottom, 2)
            Text(value)
                .font(Typo.mono(Typo.lg, weight: .medium))
                .foregroundStyle(theme.text)
                .lineLimit(1)
                .minimumScaleFactor(0.6)
            if let sub {
                Text(sub).font(Typo.sans(Typo.xs)).foregroundStyle(theme.textSecondary)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(12)
        .background(theme.panel, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).stroke(theme.border, lineWidth: 1))
    }
}

struct EmptyState<Action: View>: View {
    @Environment(\.theme) private var theme
    var icon: String?
    let title: String
    var description: String?
    @ViewBuilder var action: () -> Action

    init(icon: String? = nil, title: String, description: String? = nil,
         @ViewBuilder action: @escaping () -> Action = { EmptyView() }) {
        self.icon = icon; self.title = title; self.description = description; self.action = action
    }

    var body: some View {
        VStack(spacing: 0) {
            if let icon {
                Text(icon).font(.system(size: 30)).opacity(0.5).padding(.bottom, 16)
            }
            Text(title).font(Typo.sans(Typo.sm, weight: .medium)).foregroundStyle(theme.text).padding(.bottom, 4)
            if let description {
                Text(description).font(Typo.sans(Typo.xs)).foregroundStyle(theme.textMuted).padding(.bottom, 16)
            }
            action()
        }
        .multilineTextAlignment(.center)
        .frame(maxWidth: .infinity)
        .padding(.vertical, 48)
        .padding(.horizontal, 24)
    }
}

struct PageTitle: View {
    @Environment(\.theme) private var theme
    let title: String
    var subtitle: String?

    init(title: String, subtitle: String? = nil) { self.title = title; self.subtitle = subtitle }

    var body: some View {
        VStack(alignment: .leading, spacing: 9) {
            Text(title)
                .font(Typo.sans(Glass.pageTitle, weight: .semibold))
                .kerning(Glass.pageTitleTracking)
                .foregroundStyle(theme.text)
            if let subtitle {
                Text(subtitle).font(Typo.sans(Glass.small)).foregroundStyle(theme.textSecondary)
                    .lineSpacing(4)
            }
        }
    }
}

/// Rounded-full tab/filter chip: `bg-accent/20 text-accent` when selected, else `bg-bg-card text-text-secondary`.
struct PillChip: View {
    @Environment(\.theme) private var theme
    let label: String
    let selected: Bool
    var horizontalPadding: CGFloat = 12
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Text(label)
                .font(Typo.sans(Typo.xs))
                .foregroundStyle(selected ? theme.accent : theme.textSecondary)
                .padding(.horizontal, horizontalPadding)
                .padding(.vertical, 6)
                .background(selected ? theme.accent.opacity(0.2) : theme.panel)
                .clipShape(Capsule())
        }
        .buttonStyle(.plain)
    }
}

/// Outlined project chip: `border-accent/50 text-accent` when selected, else `border-border text-text-muted`.
struct OutlineChip: View {
    @Environment(\.theme) private var theme
    let label: String
    let selected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Text(label)
                .font(Typo.sans(Typo.xs))
                .foregroundStyle(selected ? theme.accent : theme.textMuted)
                .padding(.horizontal, 12)
                .padding(.vertical, 4)
                .overlay(RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .stroke(selected ? theme.accent.opacity(0.5) : theme.border, lineWidth: 1))
        }
        .buttonStyle(.plain)
    }
}

/// Small rounded status pill (`text-xs px-2 py-0.5 rounded-full` with tinted background).
struct TintPill: View {
    let text: String
    let color: Color
    var radius: CGFloat = 999
    var horizontal: CGFloat = 8
    var vertical: CGFloat = 2

    var body: some View {
        Text(text)
            .font(Typo.sans(Typo.xs))
            .foregroundStyle(color)
            .padding(.horizontal, horizontal)
            .padding(.vertical, vertical)
            .background(color.opacity(0.2))
            .clipShape(RoundedRectangle(cornerRadius: radius, style: .continuous))
    }
}

struct Divider1: View {
    @Environment(\.theme) private var theme
    var body: some View { Rectangle().fill(theme.border).frame(height: 1) }
}
