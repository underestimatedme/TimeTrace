import Foundation

/// 配对失败给一句能照着做的话，不把服务端原始错误串直接贴给用户。
/// 错误码与 Valley `repositoryError` 一致：40400 不存在、41000 过期、40900 已使用、40300 游客、40100 未登录。
func pairingErrorText(_ error: Error) -> String {
    guard let api = error as? APIError else { return "绑定失败：\(error.localizedDescription)" }
    switch api.code {
    case 40400: return "没有这个授权码，请核对电脑上显示的 8 位码。"
    case 41000: return "授权码已过期，请在电脑上重新运行 keji cloud login。"
    case 40900: return "这个授权码已经用过了，请在电脑上重新生成。"
    case 40300: return "游客账号不能绑定电脑，请先登录。"
    case 40100: return "登录已失效，请重新登录后再试。"
    default: return "绑定失败：\(api.message)"
    }
}
