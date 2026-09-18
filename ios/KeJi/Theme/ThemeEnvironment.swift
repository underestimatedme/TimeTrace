import SwiftUI
#if canImport(UIKit)
import UIKit
#endif

private struct ThemeKey: EnvironmentKey {
    static let defaultValue: Theme = .light
}

extension EnvironmentValues {
    var theme: Theme {
        get { self[ThemeKey.self] }
        set { self[ThemeKey.self] = newValue }
    }
}

/// Tailwind text sizes used by the prototype (px → pt).
enum Typo {
    static let xs: CGFloat = 12
    static let sm: CGFloat = 14
    static let base: CGFloat = 16
    static let lg: CGFloat = 18
    static let xl: CGFloat = 20
    static let xl2: CGFloat = 24
    static let xl3: CGFloat = 30
    static let xl4: CGFloat = 36
    static let xl5: CGFloat = 48

    /// 设计稿的字号是**基准值**，不是死值：跟随系统的「更大字体」缩放。
    /// 上限 1.6 倍，避免 30pt 的问候语放大到撑破玻璃卡片；
    /// 下限 0.85 倍，调小时同样跟随，但不至于小到读不清。
    static let maxScale: CGFloat = 1.6
    static let minScale: CGFloat = 0.85

    /// 纯函数，便于测试：给定内容尺寸类别，返回实际字号。
    static func scaled(_ size: CGFloat, category: UIContentSizeCategory) -> CGFloat {
        #if canImport(UIKit)
        let metrics = UIFontMetrics(forTextStyle: .body)
        let traits = UITraitCollection(preferredContentSizeCategory: category)
        return metrics.scaledValue(for: size, compatibleWith: traits)
            .clamped(to: (size * minScale)...(size * maxScale))
        #else
        return size
        #endif
    }

    private static var currentCategory: UIContentSizeCategory {
        #if canImport(UIKit)
        UIApplication.shared.preferredContentSizeCategory
        #else
        .large
        #endif
    }

    static func sans(_ size: CGFloat, weight: Font.Weight = .regular) -> Font {
        .system(size: scaled(size, category: currentCategory), weight: weight)
    }

    static func mono(_ size: CGFloat, weight: Font.Weight = .regular) -> Font {
        .system(size: scaled(size, category: currentCategory), weight: weight, design: .monospaced)
    }
}

private extension CGFloat {
    func clamped(to range: ClosedRange<CGFloat>) -> CGFloat {
        Swift.min(Swift.max(self, range.lowerBound), range.upperBound)
    }
}
