import Foundation

enum RemoteJobStatus: String, Codable {
    case queued, leased, running
    case waitingQuota = "waiting_quota"
    case waitingLocalAuth = "waiting_local_auth"
    case waitingInput = "waiting_input"
    case awaitingReview = "awaiting_review"
    case failed, cancelled, expired

    var label: String {
        switch self {
        case .queued: return "云端排队"
        case .leased: return "电脑已领取"
        case .running: return "AI 执行中"
        case .waitingQuota: return "等待额度"
        case .waitingLocalAuth: return "等待电脑登录"
        case .waitingInput: return "等待输入"
        case .awaitingReview: return "等待审核"
        case .failed: return "执行失败"
        case .cancelled: return "已取消"
        case .expired: return "已过期"
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
    var updatedAt: Date
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
}

struct DeviceApprovalRequest: Encodable { var userCode: String }
struct DeviceApprovalResponse: Decodable { var approved: Bool }
struct RemoteJobRequest: Encodable {
    var taskId: String
    var runnerId: String
    var workspaceId: String
    var toolProfileId: String
    var prompt: String
    var idempotencyKey: String
}
