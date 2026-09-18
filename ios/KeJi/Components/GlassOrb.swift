import SwiftUI

/// .gl-orb —— 42px 实心冰蓝圆球（白边 + 内发光 + 外投影）；
/// .gl-orb.soft 是 34px 的浅色版本，用于次要一端。
struct GlassOrb: View {
    @Environment(\.theme) private var theme
    let symbol: String
    var soft = false

    var body: some View {
        let size = soft ? Glass.orbSoftSize : Glass.orbSize
        Image(systemName: symbol)
            .font(.system(size: soft ? 15 : 18, weight: .medium))
            .foregroundStyle(soft ? theme.accent : Color.white)
            .frame(width: size, height: size)
            .background(soft ? theme.bgElevated : theme.accent, in: Circle())
            .overlay(
                Circle().stroke(soft ? Color.white : theme.ai.opacity(0.35),
                                lineWidth: soft ? 1 : 4)
            )
            .overlay(
                // inset 3px 4px 8px #87edff —— 左上的一道内发光
                Circle()
                    .stroke(Color.white.opacity(soft ? 0 : 0.5), lineWidth: 1)
                    .blur(radius: 1)
                    .padding(3)
            )
            .shadow(color: theme.accent.opacity(0.25), radius: 7, y: 3)
            .accessibilityHidden(true)
    }
}
