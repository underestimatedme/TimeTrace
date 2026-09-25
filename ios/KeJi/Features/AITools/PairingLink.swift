import Foundation

/// `keji://pair?code=<8 位授权码>&name=<电脑名>&exp=<unix 秒>&platform=darwin&v=1`：
/// `keji cloud login` 打印的二维码和 Valley 的 verification_uri 都用这个形式。
/// 链接里只有授权码和展示用的电脑名，没有任何凭据；真正的电脑信息仍以
/// inspect 接口返回为准。
struct PairingLink: Equatable {
    var code: String
    var name: String?
    /// 二维码失效时刻（unix 秒）；旧 CLI 不带，服务端授权码有效 2 分钟。
    var exp: Int? = nil

    static let expiredMessage = "二维码已过期，请看电脑上刷新出的新二维码"

    /// 没有 exp 时不在本地判过期，交给服务端（41000）。
    func isExpired(now: Date) -> Bool {
        guard let exp else { return false }
        return now.timeIntervalSince1970 >= TimeInterval(exp)
    }

    static func parse(_ url: URL) -> PairingLink? {
        guard url.scheme?.lowercased() == "keji", url.host?.lowercased() == "pair",
              let components = URLComponents(url: url, resolvingAgainstBaseURL: false) else { return nil }
        let items = components.queryItems ?? []
        func value(_ key: String) -> String? {
            items.first(where: { $0.name == key })?.value?.trimmingCharacters(in: .whitespacesAndNewlines)
        }
        guard let code = value("code")?.uppercased(), code.count == 8,
              code.unicodeScalars.allSatisfy({ CharacterSet.uppercaseLetters.contains($0) && $0.isASCII
                                                || CharacterSet.decimalDigits.contains($0) && $0.isASCII }) else { return nil }
        let name = value("name").flatMap { $0.isEmpty ? nil : $0 }
        return PairingLink(code: code, name: name, exp: value("exp").flatMap { Int($0) })
    }

    /// 相机读到的是字符串：只认 keji://pair 链接。
    static func parse(scanned: String) -> PairingLink? {
        URL(string: scanned.trimmingCharacters(in: .whitespacesAndNewlines)).flatMap { parse($0) }
    }
}

/// 二维码上的电脑名与服务端 inspect 返回的不一致时给出的警告（忽略首尾空白与大小写）。
func pairingNameMismatchWarning(linkName: String?, serverName: String) -> String? {
    guard let linkName = linkName?.trimmingCharacters(in: .whitespacesAndNewlines), !linkName.isEmpty else { return nil }
    let server = serverName.trimmingCharacters(in: .whitespacesAndNewlines)
    guard linkName.lowercased() != server.lowercased() else { return nil }
    return "⚠️ 二维码上的电脑名（\(linkName)）与服务器记录（\(server)）不一致，确认是你自己的电脑再绑定"
}

/// 确认绑定对话框的正文；电脑名对不上时第一行就是警告。
func pairingConfirmMessage(_ info: DeviceAuthorizationInspection, linkName: String?, now: Date) -> String {
    let body = "\(info.deviceName) · \(info.platform) · v\(info.clientVersion)\n请求时间：\(Format.relative(info.requestedAt, now: now))\n权限：仅接收任务、运行本机已登记仓库、回报状态及取消进程"
    guard let warning = pairingNameMismatchWarning(linkName: linkName, serverName: info.deviceName) else { return body }
    return warning + "\n" + body
}
