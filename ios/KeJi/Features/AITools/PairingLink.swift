import Foundation

/// `keji://pair?code=<8 位授权码>&name=<电脑名>&platform=darwin&v=1`：
/// `keji cloud login` 打印的二维码和 Valley 的 verification_uri 都用这个形式。
/// 链接里只有授权码和展示用的电脑名，没有任何凭据；真正的电脑信息仍以
/// inspect 接口返回为准。
struct PairingLink: Equatable {
    var code: String
    var name: String?

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
        return PairingLink(code: code, name: name)
    }

    /// 相机读到的是字符串：只认 keji://pair 链接。
    static func parse(scanned: String) -> PairingLink? {
        URL(string: scanned.trimmingCharacters(in: .whitespacesAndNewlines)).flatMap { parse($0) }
    }
}
