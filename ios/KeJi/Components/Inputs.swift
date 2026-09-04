import SwiftUI

/// `Label` + control (`FormField` in Input.tsx).
struct FormField<Content: View>: View {
    @Environment(\.theme) private var theme
    let label: String
    @ViewBuilder var content: () -> Content

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(label).font(Typo.sans(Typo.xs)).foregroundStyle(theme.textSecondary)
            content()
        }
        .padding(.bottom, 16)
    }
}

/// Input chrome: `bg-bg-elevated border border-border rounded-xl px-4 py-2.5 text-sm`.
struct InputChrome: ViewModifier {
    @Environment(\.theme) private var theme
    var focused = false

    func body(content: Content) -> some View {
        content
            .font(Typo.sans(Typo.sm))
            .foregroundStyle(theme.text)
            .padding(.horizontal, 16)
            .padding(.vertical, 10)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(theme.bgElevated)
            .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous)
                .stroke(focused ? theme.accent.opacity(0.5) : theme.border, lineWidth: 1))
    }
}

struct AppTextField: View {
    @Environment(\.theme) private var theme
    let placeholder: String
    @Binding var text: String
    var keyboard: UIKeyboardType = .default
    @FocusState private var focused: Bool

    var body: some View {
        TextField("", text: $text, prompt: Text(placeholder).foregroundColor(theme.textMuted))
            .keyboardType(keyboard)
            .textInputAutocapitalization(.never)
            .autocorrectionDisabled()
            .focused($focused)
            .modifier(InputChrome(focused: focused))
    }
}

struct AppTextEditor: View {
    @Environment(\.theme) private var theme
    let placeholder: String
    @Binding var text: String
    var minHeight: CGFloat = 76
    @FocusState private var focused: Bool

    var body: some View {
        ZStack(alignment: .topLeading) {
            if text.isEmpty {
                Text(placeholder).font(Typo.sans(Typo.sm)).foregroundStyle(theme.textMuted)
                    .padding(.horizontal, 16).padding(.vertical, 10)
            }
            TextEditor(text: $text)
                .font(Typo.sans(Typo.sm))
                .foregroundStyle(theme.text)
                .scrollContentBackground(.hidden)
                .padding(.horizontal, 12)
                .padding(.vertical, 2)
                .focused($focused)
        }
        .frame(minHeight: minHeight)
        .background(theme.bgElevated)
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous)
            .stroke(focused ? theme.accent.opacity(0.5) : theme.border, lineWidth: 1))
    }
}

/// `<select>` equivalent: styled like an input, opens a menu.
struct AppSelect<T: Hashable>: View {
    @Environment(\.theme) private var theme
    let options: [T]
    @Binding var selection: T
    let label: (T) -> String

    var body: some View {
        Menu {
            ForEach(options, id: \.self) { option in
                Button {
                    selection = option
                } label: {
                    if option == selection {
                        Label(label(option), systemImage: "checkmark")
                    } else {
                        Text(label(option))
                    }
                }
            }
        } label: {
            HStack {
                Text(label(selection)).lineLimit(1)
                Spacer(minLength: 8)
                Image(systemName: "chevron.up.chevron.down").font(.system(size: 11)).foregroundStyle(theme.textMuted)
            }
            .modifier(InputChrome())
        }
    }
}

/// Optional date input (`<input type="date|datetime-local">` starts empty).
struct OptionalDateField: View {
    @Environment(\.theme) private var theme
    @Binding var date: Date?
    var components: DatePickerComponents = [.date]

    var body: some View {
        HStack(spacing: 8) {
            if let bound = Binding($date) {
                DatePicker("", selection: bound, displayedComponents: components)
                    .labelsHidden()
                    .datePickerStyle(.compact)
                    .tint(theme.accent)
                    .scaleEffect(0.9, anchor: .leading)
                Spacer(minLength: 0)
                Button { date = nil } label: {
                    Image(systemName: "xmark.circle.fill").foregroundStyle(theme.textMuted)
                }
                .buttonStyle(.plain)
            } else {
                Button { date = Date() } label: {
                    HStack {
                        Text("未设置").foregroundStyle(theme.textMuted)
                        Spacer(minLength: 0)
                        Image(systemName: "calendar").foregroundStyle(theme.textMuted).font(.system(size: 13))
                    }
                }
                .buttonStyle(.plain)
            }
        }
        .modifier(InputChrome())
    }
}

/// Selectable option tile (executor 2x2 / provider 3-col grids).
struct OptionTile: View {
    @Environment(\.theme) private var theme
    let label: String
    let selected: Bool
    var tint: Color?
    var fontSize: CGFloat = Typo.sm
    var vertical: CGFloat = 10
    let action: () -> Void

    var body: some View {
        let color = tint ?? theme.accent
        Button(action: action) {
            Text(label)
                .font(Typo.sans(fontSize))
                .foregroundStyle(selected ? color : theme.textSecondary)
                .lineLimit(1)
                .minimumScaleFactor(0.8)
                .frame(maxWidth: .infinity)
                .padding(.horizontal, 12)
                .padding(.vertical, vertical)
                .background(selected ? color.opacity(0.1) : .clear)
                .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .stroke(selected ? color : theme.border, lineWidth: 1))
        }
        .buttonStyle(.plain)
    }
}
