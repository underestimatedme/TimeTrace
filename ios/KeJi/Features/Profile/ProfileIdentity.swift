import Foundation

/// 「我的」页与首页头部的身份：只用真实数据，不再显示写死的「刻迹用户」和示例头像。
enum ProfileIdentity {
    /// 旧版本与服务端给新账号的默认昵称；它不是用户起的名字。
    static let placeholderName = "刻迹用户"

    /// 用户自己改过的名字优先；否则用登录账号（服务端已打码的手机号）；游客显示「游客」。
    static func displayName(settingsName: String, user: UserInfo?) -> String {
        let custom = settingsName.trimmingCharacters(in: .whitespacesAndNewlines)
        if !custom.isEmpty, custom != placeholderName { return custom }
        if let user, !user.isGuest {
            return user.accountLabel ?? user.nickname.flatMap { $0 == placeholderName ? nil : $0 } ?? "已登录"
        }
        return "游客"
    }

    /// 头像用名字首字，不用示例人像。
    static func initial(of name: String) -> String {
        guard let first = name.trimmingCharacters(in: .whitespacesAndNewlines).first else { return "刻" }
        return String(first).uppercased()
    }
}

import SwiftUI

/// 名字首字头像：白边 + 冰蓝光圈，沿用 .gl-avatar 的样式。
struct InitialAvatar: View {
    @Environment(\.theme) private var theme
    let name: String
    var size: CGFloat = 42

    var body: some View {
        Text(ProfileIdentity.initial(of: name))
            .font(Typo.sans(size * 0.42, weight: .semibold))
            .foregroundStyle(theme.accent)
            .frame(width: size, height: size)
            .background(theme.accent.opacity(0.12), in: Circle())
            .overlay(Circle().stroke(Color.white, lineWidth: 2))
            .overlay(Circle().stroke(theme.accent.opacity(0.35), lineWidth: 1).padding(-2))
            .accessibilityHidden(true)
    }
}
