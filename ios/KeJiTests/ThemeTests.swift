import XCTest
import SwiftUI
@testable import KeJi

/// The light theme is the design's 冰晶白 glass palette (design/src/review/glass.css),
/// and it is the default. Values below are the `--g-*` custom properties, which are
/// the single source of truth for colour.
final class ThemeTests: XCTestCase {
    func testLightThemeUsesIceGlassTokens() {
        let light = Theme.light
        // --g-bg / --g-solid / --g-soft / --g-line
        XCTAssertEqual(light.bg, Color(hex: "#f5f9ff"), "bg should be the ice-white --g-bg")
        XCTAssertEqual(light.bgElevated, Color(hex: "#f8fbff"), "bgElevated should be --g-solid")
        XCTAssertEqual(light.bgHover, Color(hex: "#e8f1ff"), "bgHover should be --g-soft")
        XCTAssertEqual(light.border, Color(hex: "#dde8f7"), "border should be --g-line")
        // --g-text / --g-sub / --g-muted
        XCTAssertEqual(light.text, Color(hex: "#14213b"), "text should be the deep navy --g-text")
        XCTAssertEqual(light.textSecondary, Color(hex: "#61738f"), "textSecondary should be --g-sub")
        XCTAssertEqual(light.textMuted, Color(hex: "#697e9c"), "textMuted should be --g-muted")
        // --g-blue (冰蓝 accent) / --g-cyan
        XCTAssertEqual(light.accent, Color(hex: "#1680ff"), "accent should be the ice-blue --g-blue")
        XCTAssertEqual(light.ai, Color(hex: "#48b8ef"), "ai should be --g-cyan")
        // --g-success / --g-danger
        XCTAssertEqual(light.success, Color(hex: "#288873"), "success should be --g-success")
        XCTAssertEqual(light.danger, Color(hex: "#b5435d"), "danger should be --g-danger")
    }

    /// 冰晶白 is the confirmed default; 深海蓝 is the optional dark theme.
    func testGlassLightIsTheDefaultTheme() {
        XCTAssertEqual(EnvironmentValues().theme.name, .light,
                       "the default theme should be the 冰晶白 glass light theme")
        XCTAssertEqual(UserSettings.defaults().theme, .light,
                       "a fresh user's settings should default to the 冰晶白 glass theme")
    }

    /// The theme picker names it 冰晶白, not a warm-paper light.
    func testLightThemeIsNamedIceWhite() {
        XCTAssertEqual(ThemeMeta.meta(for: .light).name, "冰晶白")
    }

    /// The light theme must not report itself as dark (drives status bar / contrast).
    func testLightThemeIsNotDark() {
        XCTAssertFalse(Theme.light.isDark)
    }

    /// 玻璃面板叠在模糊背景之上：--g-panel 是 #ffffffa8，--g-shadow 是 #91b4e322。
    /// 这两个值放在 Theme 里，避免散落到各个 View。
    func testLightThemeCarriesGlassSurfaceTokens() {
        XCTAssertEqual(Theme.light.panelOpacity, 168.0 / 255, accuracy: 0.002,
                       "panelOpacity should be the a8 alpha of --g-panel")
        XCTAssertEqual(Theme.light.shadowColor, Color(hex: "#91b4e3").opacity(34.0 / 255),
                       "shadowColor should be --g-shadow")
    }

    /// 深色稿的 --g-panel(#1b2d43) 是实色，没有透明度。
    func testDarkThemesUseOpaquePanels() {
        XCTAssertEqual(Theme.claude.panelOpacity, 1, accuracy: 0.002)
    }
    /// 深海蓝：design/src/review/glass.css 的 [data-theme=dark] 一组 --g-*。
    func testDarkThemeUsesDeepSeaTokens() {
        let dark = Theme.dark
        XCTAssertEqual(dark.bg, Color(hex: "#101c2c"))
        XCTAssertEqual(dark.bgCard, Color(hex: "#1b2d43"))
        XCTAssertEqual(dark.bgElevated, Color(hex: "#17273c"))
        XCTAssertEqual(dark.bgHover, Color(hex: "#273e59"))
        XCTAssertEqual(dark.border, Color(hex: "#30465f"))
        XCTAssertEqual(dark.text, Color(hex: "#e5effd"))
        XCTAssertEqual(dark.textSecondary, Color(hex: "#b0c3dd"))
        XCTAssertEqual(dark.textMuted, Color(hex: "#9db2cf"))
        XCTAssertEqual(dark.accent, Color(hex: "#78bbff"))
        XCTAssertEqual(dark.ai, Color(hex: "#6ed8f0"))
        XCTAssertEqual(dark.success, Color(hex: "#85d9bd"))
        XCTAssertEqual(dark.danger, Color(hex: "#ffa9b9"))
        XCTAssertTrue(dark.isDark)
        XCTAssertEqual(ThemeMeta.meta(for: .dark).name, "深海蓝")
    }

    /// 跟随系统时由系统的深浅色决定；显式选择时忽略系统。
    func testThemeModeResolution() {
        XCTAssertEqual(resolveTheme(mode: .system, systemIsDark: true, accent: .blue).name, .dark)
        XCTAssertEqual(resolveTheme(mode: .system, systemIsDark: false, accent: .blue).name, .light)
        XCTAssertEqual(resolveTheme(mode: .light, systemIsDark: true, accent: .blue).name, .light)
        XCTAssertEqual(resolveTheme(mode: .dark, systemIsDark: false, accent: .blue).name, .dark)
    }

    /// 强调色只换 accent/ai，底色与文字不动。
    func testVioletAccentOnlyReplacesAccentColors() {
        let blue = resolveTheme(mode: .light, systemIsDark: false, accent: .blue)
        let violet = resolveTheme(mode: .light, systemIsDark: false, accent: .violet)
        XCTAssertEqual(violet.accent, Color(hex: "#7962e5"))
        XCTAssertEqual(violet.ai, Color(hex: "#b29bf4"))
        XCTAssertEqual(violet.bg, blue.bg)
        XCTAssertEqual(violet.text, blue.text)
        XCTAssertEqual(resolveTheme(mode: .dark, systemIsDark: false, accent: .violet).accent, Color(hex: "#b7a2ff"))
    }

    /// 三个选项就是设计稿的全部：冰晶白 / 深海蓝 / 跟随系统。
    func testThemeModeLabels() {
        XCTAssertEqual(ThemeMode.allCases.map(\.label), ["冰晶白", "深海蓝", "跟随系统"])
        XCTAssertEqual(AccentPalette.allCases.map(\.label), ["冰蓝", "鸢紫"])
    }
    /// 排版与几何来自 glass.css，集中在 Glass 里，不散落到各个 View。
    func testGlassTypeScaleAndGeometryMatchTheDesign() {
        // .gl-home-header h1 / .gl-page-title h1 / .gl-project-card h2 / body
        XCTAssertEqual(Glass.display, 30)
        XCTAssertEqual(Glass.displayTracking, -1.1, accuracy: 0.01)
        XCTAssertEqual(Glass.pageTitle, 28)
        XCTAssertEqual(Glass.pageTitleTracking, -0.6, accuracy: 0.01)
        XCTAssertEqual(Glass.cardTitle, 23)
        XCTAssertEqual(Glass.body, 14)
        // .gl-section-heading h2 是正常大小写的 14px/600，不是大写字距标题
        XCTAssertEqual(Glass.sectionTitle, 14)
        // .gl-primary-task / .gl-group / .gl-primary / .gl-badge
        XCTAssertEqual(Glass.cardRadius, 21)
        XCTAssertEqual(Glass.cardPadding, 22)
        XCTAssertEqual(Glass.groupRadius, 18)
        XCTAssertEqual(Glass.buttonRadius, 14)
        XCTAssertEqual(Glass.buttonMinHeight, 44)
        XCTAssertEqual(Glass.badgeRadius, 6)
        // .gl-segments 容器 13 / 选中项 10；.gl-bottom-nav backdrop blur 18
        XCTAssertEqual(Glass.segmentsRadius, 13)
        XCTAssertEqual(Glass.segmentItemRadius, 10)
        XCTAssertEqual(Glass.navBlur, 18)
        XCTAssertEqual(Glass.navDotSize, 3)
        // .gl-report-hero h2 / .gl-quota-value b / .gl-profile-card h2 / .gl-meter
        XCTAssertEqual(Glass.heroNumber, 48)
        XCTAssertEqual(Glass.heroNumberTracking, -2, accuracy: 0.01)
        XCTAssertEqual(Glass.quotaValue, 32)
        XCTAssertEqual(Glass.quotaTitle, 17)
        XCTAssertEqual(Glass.profileName, 20)
        XCTAssertEqual(Glass.menuRowHeight, 57)
        XCTAssertEqual(Glass.meterHeight, 6)
    }
}
