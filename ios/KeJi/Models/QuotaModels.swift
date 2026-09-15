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
    var availability: String   // available / blocked / unknown
    var windows: [QuotaWindow]

    var id: String { poolId }
}

struct AccountQuota: Codable, Equatable {
    var pools: [AccountQuotaPool]
    var observedAt: Date
}
