import SwiftUI

/// The 16 tokens of design/src/index.css, one palette per theme.
struct Theme: Equatable {
    let name: ThemeName
    let appBg: Color
    let bg: Color
    let bgElevated: Color
    let bgCard: Color
    let bgHover: Color
    let border: Color
    let text: Color
    let textSecondary: Color
    let textMuted: Color
    var accent: Color
    var accentDim: Color
    var ai: Color
    var aiDim: Color
    let success: Color
    let warning: Color
    let danger: Color

    var isDark: Bool { name != .light }

    /// --g-panel 的透明度：浅色玻璃面板是 #ffffffa8，深色稿的 #1b2d43 是实色。
    var panelOpacity: Double { isDark ? 1 : 168.0 / 255 }

    /// --g-shadow：浅色 #91b4e322，深色 #0003。低饱和、偏冷的投影。
    var shadowColor: Color {
        isDark ? Color.black.opacity(0.2) : Color(hex: "#91b4e3").opacity(34.0 / 255)
    }

    /// --g-panel 本身：半透明面板，要叠在模糊背景之上才有玻璃感。
    var panel: Color { bgCard.opacity(panelOpacity) }

    /// glass.css 的投影几何：box-shadow 0 8px 28px → SwiftUI 的 radius 14 / y 8。
    static let shadowBlur: CGFloat = 14
    static let shadowOffsetY: CGFloat = 8

    static func named(_ name: ThemeName) -> Theme {
        switch name {
        case .claude: return .claude
        case .codex: return .codex
        case .cursor: return .cursor
        case .light: return .light
        case .dark: return .dark
        }
    }

    static let claude = Theme(
        name: .claude,
        appBg: Color(hex: "#050506"), bg: Color(hex: "#0a0a0b"), bgElevated: Color(hex: "#141416"),
        bgCard: Color(hex: "#1a1a1e"), bgHover: Color(hex: "#222228"), border: Color(hex: "#2a2a30"),
        text: Color(hex: "#f5f0eb"), textSecondary: Color(hex: "#8a8580"), textMuted: Color(hex: "#5a5550"),
        accent: Color(hex: "#d4845a"), accentDim: Color(hex: "#a86840"),
        ai: Color(hex: "#6b8cae"), aiDim: Color(hex: "#4a6a8a"),
        success: Color(hex: "#5a8a6a"), warning: Color(hex: "#8a7a4a"), danger: Color(hex: "#8a5a5a"))

    static let codex = Theme(
        name: .codex,
        appBg: Color(hex: "#060707"), bg: Color(hex: "#0c0d0d"), bgElevated: Color(hex: "#151717"),
        bgCard: Color(hex: "#1b1d1d"), bgHover: Color(hex: "#232626"), border: Color(hex: "#2b2e2e"),
        text: Color(hex: "#ececec"), textSecondary: Color(hex: "#9a9e9c"), textMuted: Color(hex: "#5e6361"),
        accent: Color(hex: "#19c37d"), accentDim: Color(hex: "#129768"),
        ai: Color(hex: "#54b5c4"), aiDim: Color(hex: "#3a8794"),
        success: Color(hex: "#5a9a72"), warning: Color(hex: "#9a8744"), danger: Color(hex: "#b35c54"))

    static let cursor = Theme(
        name: .cursor,
        appBg: Color(hex: "#050608"), bg: Color(hex: "#0a0c11"), bgElevated: Color(hex: "#121620"),
        bgCard: Color(hex: "#181d29"), bgHover: Color(hex: "#212838"), border: Color(hex: "#2a3242"),
        text: Color(hex: "#eef2f8"), textSecondary: Color(hex: "#8b93a3"), textMuted: Color(hex: "#555d6d"),
        accent: Color(hex: "#5b8dff"), accentDim: Color(hex: "#3f6ad1"),
        ai: Color(hex: "#b08cff"), aiDim: Color(hex: "#8a64d8"),
        success: Color(hex: "#4f9d7a"), warning: Color(hex: "#c2a24a"), danger: Color(hex: "#d06464"))

    /// 冰晶白 —— design/src/review/glass.css 的 `--g-*`，色彩的唯一真相源。
    static let light = Theme(
        name: .light,
        appBg: Color(hex: "#eaf1f9"), bg: Color(hex: "#f5f9ff"), bgElevated: Color(hex: "#f8fbff"),
        bgCard: Color(hex: "#ffffff"), bgHover: Color(hex: "#e8f1ff"), border: Color(hex: "#dde8f7"),
        text: Color(hex: "#14213b"), textSecondary: Color(hex: "#61738f"), textMuted: Color(hex: "#697e9c"),
        accent: Color(hex: "#1680ff"), accentDim: Color(hex: "#0f66d0"),
        ai: Color(hex: "#48b8ef"), aiDim: Color(hex: "#2e94c6"),
        success: Color(hex: "#288873"), warning: Color(hex: "#88692b"), danger: Color(hex: "#b5435d"))

    /// 深海蓝 —— glass.css 的 `.gl-app[data-theme=dark]`。
    static let dark = Theme(
        name: .dark,
        appBg: Color(hex: "#0b1522"), bg: Color(hex: "#101c2c"), bgElevated: Color(hex: "#17273c"),
        bgCard: Color(hex: "#1b2d43"), bgHover: Color(hex: "#273e59"), border: Color(hex: "#30465f"),
        text: Color(hex: "#e5effd"), textSecondary: Color(hex: "#b0c3dd"), textMuted: Color(hex: "#9db2cf"),
        accent: Color(hex: "#78bbff"), accentDim: Color(hex: "#4f9be8"),
        ai: Color(hex: "#6ed8f0"), aiDim: Color(hex: "#49b3cc"),
        success: Color(hex: "#85d9bd"), warning: Color(hex: "#e7c993"), danger: Color(hex: "#ffa9b9"))
}


/// 主题模式：设计稿只提供这三项。
enum ThemeMode: String, Codable, CaseIterable, Identifiable {
    case light, dark, system
    var id: String { rawValue }
    var label: String {
        switch self {
        case .light: return "冰晶白"
        case .dark: return "深海蓝"
        case .system: return "跟随系统"
        }
    }
}

/// 强调色：冰蓝（--g-blue）与鸢紫（data-accent=violet）。
enum AccentPalette: String, Codable, CaseIterable, Identifiable {
    case blue, violet
    var id: String { rawValue }
    var label: String { self == .blue ? "冰蓝" : "鸢紫" }
}

/// 把「模式 + 系统深浅色 + 强调色」解析成一套实际生效的 Theme。
func resolveTheme(mode: ThemeMode, systemIsDark: Bool, accent: AccentPalette) -> Theme {
    var theme: Theme
    switch mode {
    case .light: theme = .light
    case .dark: theme = .dark
    case .system: theme = systemIsDark ? .dark : .light
    }
    guard accent == .violet else { return theme }
    // 鸢紫只替换强调色，底色与文字保持不变。
    theme.accent = theme.isDark ? Color(hex: "#b7a2ff") : Color(hex: "#7962e5")
    theme.accentDim = theme.isDark ? Color(hex: "#9a86e8") : Color(hex: "#5f49c4")
    theme.ai = Color(hex: "#b29bf4")
    theme.aiDim = Color(hex: "#8a72d8")
    return theme
}

/// Port of design/src/lib/themes.ts.
struct ThemeMeta: Identifiable {
    let id: ThemeName
    let name: String
    let tagline: String
    let swatchBg: Color
    let swatchCard: Color
    let swatchAccent: Color
    let swatchAI: Color

    static let all: [ThemeMeta] = [
        ThemeMeta(id: .claude, name: "琥珀 · Claude", tagline: "暖色、克制、夜色中的微光",
                  swatchBg: Color(hex: "#0a0a0b"), swatchCard: Color(hex: "#1a1a1e"),
                  swatchAccent: Color(hex: "#d4845a"), swatchAI: Color(hex: "#6b8cae")),
        ThemeMeta(id: .codex, name: "翠绿 · Codex", tagline: "中性冷调，OpenAI 风格的清爽绿",
                  swatchBg: Color(hex: "#0c0d0d"), swatchCard: Color(hex: "#1b1d1d"),
                  swatchAccent: Color(hex: "#19c37d"), swatchAI: Color(hex: "#54b5c4")),
        ThemeMeta(id: .cursor, name: "靛蓝 · Cursor", tagline: "冷峻蓝紫，理性的科技质感",
                  swatchBg: Color(hex: "#0a0c11"), swatchCard: Color(hex: "#181d29"),
                  swatchAccent: Color(hex: "#5b8dff"), swatchAI: Color(hex: "#b08cff")),
        ThemeMeta(id: .dark, name: "深海蓝", tagline: "深海蓝底、冰蓝强调的深色玻璃",
                  swatchBg: Color(hex: "#101c2c"), swatchCard: Color(hex: "#1b2d43"),
                  swatchAccent: Color(hex: "#78bbff"), swatchAI: Color(hex: "#6ed8f0")),
        ThemeMeta(id: .light, name: "冰晶白", tagline: "冰晶白底、冰蓝强调的浅色玻璃",
                  swatchBg: Color(hex: "#f5f9ff"), swatchCard: Color(hex: "#ffffff"),
                  swatchAccent: Color(hex: "#1680ff"), swatchAI: Color(hex: "#48b8ef")),
    ]

    static func meta(for id: ThemeName) -> ThemeMeta { all.first { $0.id == id } ?? all[0] }
}

extension Color {
    init(hex: String) {
        var value = hex.trimmingCharacters(in: .whitespacesAndNewlines)
        if value.hasPrefix("#") { value.removeFirst() }
        var rgb: UInt64 = 0
        Scanner(string: value).scanHexInt64(&rgb)
        let r = Double((rgb >> 16) & 0xFF) / 255
        let g = Double((rgb >> 8) & 0xFF) / 255
        let b = Double(rgb & 0xFF) / 255
        self.init(.sRGB, red: r, green: g, blue: b, opacity: 1)
    }
}
