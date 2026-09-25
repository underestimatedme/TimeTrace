import Foundation

enum HTTPMethod: String { case get = "GET", post = "POST", put = "PUT", patch = "PATCH", delete = "DELETE" }

struct Endpoint {
    var method: HTTPMethod
    var path: String
    var requiresAuth: Bool
    var body: Encodable?

    static let contentVersion = Endpoint(method: .get, path: "/content/version", requiresAuth: false, body: nil)
    static let guest = Endpoint(method: .post, path: "/auth/guest", requiresAuth: false, body: nil)
    static func sendCode(identifier: String) -> Endpoint {
        Endpoint(method: .post, path: "/auth/send-code", requiresAuth: false, body: ["identifier": identifier])
    }
    /// bearer optional: when the caller is a guest the backend merges guest data into the identity.
    static func login(identifier: String, code: String) -> Endpoint {
        Endpoint(method: .post, path: "/auth/login", requiresAuth: false, body: ["identifier": identifier, "code": code])
    }
    static func refresh(refreshToken: String) -> Endpoint {
        Endpoint(method: .post, path: "/auth/refresh", requiresAuth: false, body: ["refresh_token": refreshToken])
    }
    static let logout = Endpoint(method: .post, path: "/auth/logout", requiresAuth: true, body: nil)
    static let deleteAccount = Endpoint(method: .delete, path: "/account", requiresAuth: true, body: nil)
    static let bootstrap = Endpoint(method: .get, path: "/bootstrap", requiresAuth: true, body: nil)
    static func sync(_ request: SyncRequest) -> Endpoint {
        Endpoint(method: .post, path: "/sync", requiresAuth: true, body: request)
    }
    static let runners = Endpoint(method: .get, path: "/runners", requiresAuth: true, body: nil)
    /// 解绑一台电脑：服务端吊销它的凭据并取消还在等它的任务。
    static func unbindRunner(id: String) -> Endpoint {
        Endpoint(method: .delete, path: "/runners/\(id)", requiresAuth: true, body: nil)
    }
    /// 给电脑改个名字（1–80 个字符，服务端去掉首尾空白）。
    static func renameRunner(id: String, name: String) -> Endpoint {
        Endpoint(method: .patch, path: "/runners/\(id)", requiresAuth: true, body: ["name": name])
    }
    static func approveRunner(code: String) -> Endpoint {
        Endpoint(method: .post, path: "/device-authorizations/approve", requiresAuth: true,
                 body: DeviceApprovalRequest(userCode: code))
    }
    static func inspectRunner(code: String) -> Endpoint {
        Endpoint(method: .post, path: "/device-authorizations/inspect", requiresAuth: true,
                 body: DeviceApprovalRequest(userCode: code))
    }
    static func createRemoteJob(_ request: RemoteJobRequest) -> Endpoint {
        Endpoint(method: .post, path: "/remote-jobs", requiresAuth: true, body: request)
    }
    static func remoteJob(id: String) -> Endpoint {
        Endpoint(method: .get, path: "/remote-jobs/\(id)", requiresAuth: true, body: nil)
    }
    static func remoteJobCommand(id: String, action: String, expectedRevision: Int, idempotencyKey: String) -> Endpoint {
        Endpoint(method: .post, path: "/remote-jobs/\(id)/commands", requiresAuth: true,
                 body: RemoteJobCommandRequest(action: action, expectedRevision: expectedRevision,
                                               idempotencyKey: idempotencyKey))
    }

    // MARK: - Workspace (Plans / quota / reports)

    static let accountQuota = Endpoint(method: .get, path: "/quota", requiresAuth: true, body: nil)
    static let resetSignals = Endpoint(method: .get, path: "/reset-signals", requiresAuth: true, body: nil)
    static let getPreferences = Endpoint(method: .get, path: "/preferences", requiresAuth: true, body: nil)
    static func putPreferences(expectedRevision: Int64, prefs: UserPreferences) -> Endpoint {
        Endpoint(method: .put, path: "/preferences", requiresAuth: true,
                 body: PutPreferencesBody(expectedRevision: expectedRevision, data: prefs))
    }
    /// 反馈走 Valley 的 POST /feedback：body / idempotency_key / include_diagnostics。
    /// 含凭据、邮箱、环境信息或超长的草稿在客户端就拒绝，不发出去。
    static func feedback(_ draft: FeedbackDraft) throws -> Endpoint {
        guard draft.isValid else { throw APIError(code: -8, message: "反馈请勿包含凭据、邮箱或环境信息，且不得超过 4000 字节。") }
        return Endpoint(method: .post, path: "/feedback", requiresAuth: true, body: FeedbackBody(draft: draft))
    }
    /// 匿名使用统计：Valley 的 POST /events，一次最多 100 条。
    static func usageEvents(_ body: UsageEventsBody) -> Endpoint {
        Endpoint(method: .post, path: "/events", requiresAuth: true, body: body)
    }
    static func taskPlans(taskID: String) -> Endpoint {
        Endpoint(method: .get, path: "/tasks/\(taskID)/plans", requiresAuth: true, body: nil)
    }
    static func createPlan(taskID: String, draft: PlanItem) -> Endpoint {
        Endpoint(method: .post, path: "/tasks/\(taskID)/plans", requiresAuth: true, body: CreatePlanBody(draft: draft))
    }
    static func retryPlan(id: String, expectedRevision: Int) -> Endpoint {
        Endpoint(method: .post, path: "/plans/\(id)/retry", requiresAuth: true,
                 body: RevisionBody(expectedRevision: expectedRevision))
    }
    static func acceptPlan(id: String, expectedRevision: Int, evidenceIDs: [String], criteria: [CriterionResultBody]) -> Endpoint {
        Endpoint(method: .post, path: "/plans/\(id)/accept", requiresAuth: true,
                 body: AcceptPlanBody(expectedRevision: expectedRevision, evidenceIds: evidenceIDs, criteria: criteria))
    }
    static func updatePlanPolicy(id: String, expectedRevision: Int, policy: PlanExecutionPolicy) -> Endpoint {
        Endpoint(method: .patch, path: "/plans/\(id)", requiresAuth: true,
                 body: UpdatePlanPolicyBody(expectedRevision: expectedRevision, executionPolicy: policy))
    }
    static func cancelPlan(id: String, expectedRevision: Int) -> Endpoint {
        Endpoint(method: .post, path: "/plans/\(id)/cancel", requiresAuth: true,
                 body: RevisionBody(expectedRevision: expectedRevision))
    }
    static func report(date: String, zone: String? = nil) -> Endpoint {
        let query = zone.map { "&zone=" + ($0.addingPercentEncoding(withAllowedCharacters: .alphanumerics) ?? "") } ?? ""
        return Endpoint(method: .get, path: "/reports?date=\(date)\(query)", requiresAuth: true, body: nil)
    }
    static func generateReport(date: String, zone: String) -> Endpoint {
        Endpoint(method: .post, path: "/reports", requiresAuth: true, body: GenerateReportBody(date: date, zone: zone))
    }
}

struct CriterionResultBody: Codable, Equatable {
    var index: Int
    var accepted: Bool
}

struct CreatePlanBody: Encodable {
    var title: String
    var priority: Int
    var status = "ready"
    var criteria: [String]
    var dependsOn: [String]
    var estimatedHumanMinutes: Int
    var estimatedAiMinutes: Int
    var workWeight: Double
    var risk: Int
    var executionPolicy: PlanExecutionPolicy

    init(draft: PlanItem) {
        title = draft.title; priority = draft.priority; criteria = draft.criteria; dependsOn = draft.dependsOn
        estimatedHumanMinutes = draft.estimatedHumanMinutes; estimatedAiMinutes = draft.estimatedAiMinutes
        workWeight = draft.workWeight; risk = draft.risk; executionPolicy = draft.executionPolicy
    }
}

struct AcceptPlanBody: Encodable {
    var expectedRevision: Int
    var evidenceIds: [String]
    var criteria: [CriterionResultBody]
}

struct UpdatePlanPolicyBody: Encodable {
    var expectedRevision: Int
    var executionPolicy: PlanExecutionPolicy
}

struct PutPreferencesBody: Encodable {
    var expectedRevision: Int64
    var data: UserPreferences
}

struct FeedbackBody: Encodable {
    var body: String
    var idempotencyKey: String
    var includeDiagnostics: Bool

    init(draft: FeedbackDraft) {
        body = draft.trimmedText
        idempotencyKey = draft.idempotencyKey
        includeDiagnostics = draft.attachDiagnostics
    }
}

struct RevisionBody: Encodable {
    var expectedRevision: Int
}

struct GenerateReportBody: Encodable {
    var date: String
    var zone: String
}

struct APIError: Error, LocalizedError, Equatable {
    var code: Int
    var message: String
    var currentPlan: PlanItem? = nil

    var errorDescription: String? { message }

    static let offline = APIError(code: -1, message: "离线模式")
    static let noSession = APIError(code: -2, message: "尚未建立会话")
    static let sessionChanged = APIError(code: -9, message: "账号会话已变化，请重试")
    static func transport(_ error: Error) -> APIError { APIError(code: -3, message: error.localizedDescription) }
    static func decoding(_ error: Error) -> APIError { APIError(code: -4, message: "响应解析失败: \(error.localizedDescription)") }
    static let unauthorizedCode = 40100
}
