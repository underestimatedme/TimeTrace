import SwiftUI

/// .gl-segments —— 容器是 --g-soft 底色的圆角条，选中项是一块带投影的白面板。
/// 代替 SwiftUI 原生 segmented picker，保证和设计稿一致。
struct GlassSegments<Value: Hashable>: View {
    @Environment(\.theme) private var theme
    let options: [(value: Value, label: String)]
    @Binding var selection: Value
    var onChange: ((Value) -> Void)?

    var body: some View {
        HStack(spacing: 3) {
            ForEach(options, id: \.value) { option in
                let active = option.value == selection
                Button {
                    selection = option.value
                    onChange?(option.value)
                } label: {
                    Text(option.label)
                        .font(Typo.sans(Glass.small, weight: active ? .medium : .regular))
                        .foregroundStyle(active ? theme.accent : theme.textSecondary)
                        .frame(maxWidth: .infinity, minHeight: 35)
                        .background {
                            if active {
                                RoundedRectangle(cornerRadius: Glass.segmentItemRadius, style: .continuous)
                                    .fill(theme.bgCard)
                                    .shadow(color: theme.shadowColor, radius: 4, y: 2)
                            }
                        }
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }
        }
        .padding(4)
        .background(theme.bgHover, in: RoundedRectangle(cornerRadius: Glass.segmentsRadius, style: .continuous))
    }
}
