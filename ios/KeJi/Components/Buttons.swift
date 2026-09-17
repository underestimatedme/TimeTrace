import SwiftUI

enum ButtonVariant { case standard, secondary, ghost, danger, accent }
enum ButtonSize { case sm, md, lg }

/// Port of Button.tsx variants/sizes.
struct AppButton: View {
    @Environment(\.theme) private var theme
    let title: String
    var icon: String?
    var variant: ButtonVariant = .standard
    var size: ButtonSize = .md
    var fullWidth = false
    var disabled = false
    let action: () -> Void

    init(_ title: String, icon: String? = nil, variant: ButtonVariant = .standard, size: ButtonSize = .md,
         fullWidth: Bool = false, disabled: Bool = false, action: @escaping () -> Void) {
        self.title = title; self.icon = icon; self.variant = variant; self.size = size
        self.fullWidth = fullWidth; self.disabled = disabled; self.action = action
    }

    private var fontSize: CGFloat {
        switch size { case .sm: return Typo.xs; case .md: return Typo.sm; case .lg: return Typo.base }
    }
    private var paddingH: CGFloat { switch size { case .sm: return 12; case .md: return 16; case .lg: return 24 } }
    private var paddingV: CGFloat { switch size { case .sm: return 6; case .md: return 10; case .lg: return 12 } }
    private var radius: CGFloat { size == .sm ? 8 : 12 }

    private var foreground: Color {
        switch variant {
        case .standard: return theme.text
        case .secondary, .ghost: return theme.textSecondary
        case .danger: return theme.danger
        case .accent: return theme.bg
        }
    }

    private var background: Color {
        switch variant {
        case .standard: return theme.panel
        case .secondary: return theme.bgElevated
        case .ghost: return .clear
        case .danger: return theme.danger.opacity(0.2)
        case .accent: return theme.accent
        }
    }

    private var border: Color? {
        switch variant {
        case .standard: return theme.border
        case .danger: return theme.danger.opacity(0.3)
        default: return nil
        }
    }

    var body: some View {
        Button(action: action) {
            HStack(spacing: 8) {
                if let icon { Image(systemName: icon).font(.system(size: fontSize, weight: .medium)) }
                Text(title)
            }
            .font(Typo.sans(fontSize, weight: variant == .accent ? .medium : .regular))
            .foregroundStyle(foreground)
            .padding(.horizontal, paddingH)
            .padding(.vertical, paddingV)
            .frame(maxWidth: fullWidth ? .infinity : nil)
            .background(background)
            .clipShape(RoundedRectangle(cornerRadius: radius, style: .continuous))
            .overlay {
                if let border {
                    RoundedRectangle(cornerRadius: radius, style: .continuous).stroke(border, lineWidth: 1)
                }
            }
            .opacity(disabled ? 0.5 : 1)
        }
        .buttonStyle(.plain)
        .disabled(disabled)
    }
}

/// Plain row button used for menu-like lists.
struct RowButton<Content: View>: View {
    let action: () -> Void
    @ViewBuilder var content: () -> Content

    var body: some View {
        Button(action: action) { content() }.buttonStyle(.plain)
    }
}
