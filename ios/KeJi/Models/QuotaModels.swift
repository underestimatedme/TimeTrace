import Foundation

/// One account quota window as returned by Valley's GET /quota. Carries only
/// opaque pool ids and de-identified readings — never credentials. A nil
/// usedPercent means an unknown reading (must not be treated as full).
struct QuotaWindow: Codable, Equatable, Identifiable {
    var poolId: String
    var scope: String
    var kind: String
    var usedPercent: Double?
    var resetAt: Date?
    var observedAt: Date
    var expiresAt: Date
    var source: String
    var confidence: String

    var id: String { "\(poolId)|\(scope)|\(kind)" }
}

struct AccountQuotaPool: Codable, Equatable, Identifiable {
    var poolId: String
    /// Tool identity (= sample kind) so clients can render per-tool cards; "" when unknown.
    var provider: String = ""
    var availability: String   // available / blocked / unknown
    var windows: [QuotaWindow]

    var id: String { poolId }

    init(poolId: String, provider: String = "", availability: String, windows: [QuotaWindow]) {
        self.poolId = poolId; self.provider = provider; self.availability = availability; self.windows = windows
    }

    /// `provider` 是后加的字段：旧快照里没有时按未知处理，不能整条解码失败。
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        poolId = try c.decode(String.self, forKey: .poolId)
        provider = try c.decodeIfPresent(String.self, forKey: .provider) ?? ""
        availability = try c.decodeIfPresent(String.self, forKey: .availability) ?? "unknown"
        windows = try c.decodeIfPresent([QuotaWindow].self, forKey: .windows) ?? []
    }
}

struct AccountQuota: Codable, Equatable {
    var pools: [AccountQuotaPool]
    var observedAt: Date
}
