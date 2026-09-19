import SwiftUI

/// 版本号来自 Info.plist，不写死；缺信息时如实说「未知」。
enum AppVersion {
    static func text(info: [String: Any]) -> String {
        guard let short = info["CFBundleShortVersionString"] as? String,
              let build = info["CFBundleVersion"] as? String else { return "版本未知" }
        return "版本 \(short)（\(build)）"
    }

    static var current: String { text(info: Bundle.main.infoDictionary ?? [:]) }
}

/// 关于刻迹（design/src/review/AccountCenter.tsx 的 about 页）。
/// 设计稿里的「演示使用说明」是给原型看的，这里换成生产版的真实说明。
struct AboutView: View {
    @Environment(\.theme) private var theme
    @Environment(AppRouter.self) private var router

    var body: some View {
        SubPageScaffold(title: "关于刻迹") {
            VStack(spacing: 0) {
                Image("glass-hero")
                    .resizable().aspectRatio(contentMode: .fill)
                    .frame(width: 80, height: 80)
                    .clipShape(RoundedRectangle(cornerRadius: 22, style: .continuous))
                    .shadow(color: theme.shadowColor, radius: 12, y: 6)
                    .padding(.bottom, 19)
                    .accessibilityHidden(true)
                Text("刻迹").font(Typo.sans(24, weight: .semibold)).foregroundStyle(theme.text)
                Text("个人与 AI 的多项目工作台")
                    .font(Typo.sans(13)).foregroundStyle(theme.textSecondary).padding(.top, 9)
                Text(AppVersion.current)
                    .font(Typo.sans(11)).foregroundStyle(theme.textMuted).padding(.top, 9)
                    .accessibilityIdentifier("about.version")
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 15)
            .padding(.bottom, 12)

            section("数据放在哪里",
                    "任务、Plan 和时间记录保存在本机，并同步到你的刻迹账号。代码、命令行工具的登录凭据和完整执行输出留在你自己的电脑上，不会上传。")
            section("AI 执行与费用",
                    "刻迹只调度你电脑上已登录的 AI 工具，使用你现有的订阅额度。额度不足时 Plan 会等待，不会转为付费执行，也不会替你购买额度。")
            section("隐私",
                    "登录时使用的邮箱或手机号只用于验证身份。刻迹不做跨 App 追踪，不接入广告或第三方统计 SDK。诊断信息只在你提交反馈并主动勾选时才会附带。")

            AppButton("联系与反馈", variant: .secondary, fullWidth: true) { router.push(.feedback) }
                .padding(.top, 8)
                .accessibilityIdentifier("about.feedback")
        }
    }

    private func section(_ title: String, _ body: String) -> some View {
        VStack(alignment: .leading, spacing: 9) {
            Text(title).font(Typo.sans(15, weight: .semibold)).foregroundStyle(theme.text)
            Text(body).font(Typo.sans(13)).foregroundStyle(theme.textSecondary).lineSpacing(6)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.bottom, 22)
    }
}
