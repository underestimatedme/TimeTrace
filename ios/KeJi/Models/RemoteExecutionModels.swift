import Foundation

enum RemoteJobStatus: String, Codable {
    case queued, leased, running
    case waitingQuota = "waiting_quota"
    case waitingLocalAuth = "waiting_local_auth"
    case waitingInput = "waiting_input"
    case awaitingReview = "awaiting_review"
    case completed, failed, cancelled, expired, interrupted

    var label: String {
        switch self {
        case .queued: return "云端排队"
        case .leased: return "电脑已领取"
        case .running: return "AI 执行中"
        case .waitingQuota: return "等待额度"
        case .waitingLocalAuth: return "等待电脑登录"
        case .waitingInput: return "等待输入"
        case .awaitingReview: return "结果待确认"
        case .completed: return "已完成"
        case .failed: return "执行失败"
        case .cancelled: return "已取消"
        case .expired: return "已过期"
        case .interrupted: return "执行中断"
        }
    }
}

struct RemoteRunner: Codable, Identifiable, Equatable {
    var id: String
    var name: String
    var platform: String
    var clientVersion: String
    var status: String
    var lastSeenAt: Date?
    var revokedAt: Date?
    var createdAt: Date
    var updatedAt: Date
}

struct RunnerWorkspace: Codable, Identifiable, Equatable {
    var id: String
    var name: String
    var defaultBranch: String
    var enabled: Bool
    var updatedAt: Date
}

struct RunnerTool: Codable, Identifiable, Equatable {
    var id: String
    var provider: AIProvider
    var version: String
    var status: String
    /// 工具登录账号的套餐等级（如 max / plus），仅用于显示；缺省为空。
    var planTier: String = ""
    var updatedAt: Date
}

extension RunnerTool {
    /// `plan_tier` 是后加的字段：老服务端不返回时按空处理，不能整条解码失败。
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(String.self, forKey: .id)
        provider = try c.decode(AIProvider.self, forKey: .provider)
        version = try c.decode(String.self, forKey: .version)
        status = try c.decode(String.self, forKey: .status)
        planTier = try c.decodeIfPresent(String.self, forKey: .planTier) ?? ""
        updatedAt = try c.decode(Date.self, forKey: .updatedAt)
    }
}

struct RunnerInventory: Codable, Identifiable, Equatable {
    var runner: RemoteRunner
    var workspaces: [RunnerWorkspace]
    var tools: [RunnerTool]
    var id: String { runner.id }
}

struct RemoteJob: Codable, Identifiable, Equatable {
    var id: String
    var taskId: String
    var runnerId: String
    var workspaceId: String
    var toolProfileId: String
    var status: RemoteJobStatus
    var revision: Int
    var resultSummary: String?
    var prompt: String?
    var createdAt: Date
    var updatedAt: Date
    var planId: String? = nil
    /// 用户指定的执行时刻；nil 表示尽快执行。
    var notBefore: Date? = nil
    /// Runner 随终态事件回传的最后 ≤ 8 KB 输出。
    var outputTail: String? = nil
}

struct DeviceApprovalRequest: Encodable { var userCode: String }
struct DeviceApprovalResponse: Decodable { var approved: Bool }
struct RemoteCommandResponse: Decodable { var accepted: Bool }
struct RemoteJobCommandRequest: Encodable {
    var action: String
    var expectedRevision: Int
    var idempotencyKey: String
}
struct DeviceAuthorizationInspection: Decodable {
    var deviceName: String
    var platform: String
    var clientVersion: String
    var requestedAt: Date
    var expiresAt: Date
    var permissions: [String]
}
struct RemoteJobRequest: Encodable {
    var taskId: String
    var runnerId: String
    var workspaceId: String
    var toolProfileId: String
    var prompt: String
    var idempotencyKey: String
    var expectedTaskRevision: Int64
    var planId: String? = nil
    var notBefore: Date? = nil
}
