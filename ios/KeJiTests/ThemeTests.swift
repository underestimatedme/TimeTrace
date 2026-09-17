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
}
