import SwiftUI

/// StatusBadge (Badge.tsx): `px-2 py-0.5 rounded-md text-xs font-medium` with tinted background.
struct StatusBadge: View {
    @Environment(\.theme) private var theme
    let status: TaskStatus

    private var colors: (bg: Color, fg: Color) {
        switch status {
        case .inbox, .paused, .cancelled: return (theme.textMuted.opacity(0.2), theme.textMuted)
        case .planned: return (theme.ai.opacity(0.2), theme.ai)
        case .ready: return (theme.accent.opacity(0.2), theme.accent)
        case .humanRunning: return (theme.accent.opacity(0.3), theme.accent)
        case .aiQueued: return (theme.aiDim.opacity(0.2), theme.ai)
        case .aiRunning: return (theme.ai.opacity(0.3), theme.ai)
        case .waitingHuman, .waitingExternal: return (theme.warning.opacity(0.2), theme.warning)
        case .completed: return (theme.success.opacity(0.2), theme.success)
        case .failed: return (theme.danger.opacity(0.2), theme.danger)
        }
    }

    var body: some View {
        Text(status.label)
            .font(Typo.sans(Typo.xs, weight: .medium))
            .foregroundStyle(colors.fg)
            .padding(.horizontal, 8)
            .padding(.vertical, 2)
            .background(colors.bg)
            .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
    }
}

struct ExecutorBadge: View {
    @Environment(\.theme) private var theme
    let type: ExecutorType
    var provider: AIProvider?

    private var label: String {
        if type == .ai || type == .collaboration { return provider?.label ?? "AI" }
        return type.label
    }

    private var color: Color {
        switch type {
        case .human, .collaboration: return theme.accent
        case .ai: return theme.ai
        case .external: return theme.textSecondary
        }
    }

    var body: some View {
        Text(label).font(Typo.sans(Typo.xs)).foregroundStyle(color)
    }
}

struct PriorityBadge: View {
    @Environment(\.theme) private var theme
    let priority: TaskPriority

    private var color: Color {
        switch priority {
        case .low: return theme.textMuted
        case .medium: return theme.textSecondary
        case .high: return theme.accent
        case .urgent: return theme.danger
        }
    }

    var body: some View {
        Text(priority.label).font(Typo.sans(Typo.xs)).foregroundStyle(color)
    }
}
