import Foundation

enum HTTPMethod: String { case get = "GET", post = "POST", put = "PUT", delete = "DELETE" }

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
    static func approveRunner(code: String) -> Endpoint {
        Endpoint(method: .post, path: "/device-authorizations/approve", requiresAuth: true,
                 body: DeviceApprovalRequest(userCode: code))
    }
    static func createRemoteJob(_ request: RemoteJobRequest) -> Endpoint {
        Endpoint(method: .post, path: "/remote-jobs", requiresAuth: true, body: request)
    }
    static func remoteJob(id: String) -> Endpoint {
        Endpoint(method: .get, path: "/remote-jobs/\(id)", requiresAuth: true, body: nil)
    }
}

struct APIError: Error, LocalizedError, Equatable {
    var code: Int
    var message: String

    var errorDescription: String? { message }

    static let offline = APIError(code: -1, message: "离线模式")
    static let noSession = APIError(code: -2, message: "尚未建立会话")
    static func transport(_ error: Error) -> APIError { APIError(code: -3, message: error.localizedDescription) }
    static func decoding(_ error: Error) -> APIError { APIError(code: -4, message: "响应解析失败: \(error.localizedDescription)") }
    static let unauthorizedCode = 40100
}
