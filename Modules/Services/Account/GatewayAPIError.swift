import Foundation

enum GatewayAPIError: Error {
    /// No Gateway URL is baked into this build.
    case notConfigured
    /// The device could not reach the Gateway (DNS, TLS, timeout, offline).
    case transport(URLError)
    /// The Gateway answered with a structured error. `details` keeps the scalar fields of the
    /// wire object (`grpcCode`, `grpcStatus`, `pendingToken`, …); see `GatewayAPIClient`.
    case server(code: String, message: String, status: Int, details: [String: any Sendable])
    /// A 2xx response that did not match the contract.
    case invalidResponse

    var serverCode: String? {
        if case .server(let code, _, _, _) = self { return code }
        return nil
    }

    var details: [String: any Sendable] {
        if case .server(_, _, _, let details) = self { return details }
        return [:]
    }

    /// Transport-level failure: retryable later, but never evidence that the
    /// session or the account is invalid.
    var isConnectivityFailure: Bool {
        if case .transport = self { return true }
        if case .server(let code, _, _, _) = self, code == "upstream-unavailable" { return true }
        return false
    }

    /// The server has definitively rejected the session or the account.
    var isSessionInvalid: Bool {
        guard case .server(let code, _, _, _) = self else { return false }
        return code == "unauthenticated" || code == "user-disabled" || code == "user-not-found"
    }

    /// The operation needs a fresh credential before it can proceed.
    var requiresRecentAuth: Bool {
        serverCode == "reauth-required"
    }

    /// The ID token itself was rejected (expired or revoked), so a refresh may fix it.
    /// Other 401s — `reauth-required`, a wrong password — are not helped by one, and
    /// resending a password only counts as another failed attempt.
    var isStaleToken: Bool {
        serverCode == "unauthenticated"
    }

    var isRateLimited: Bool {
        serverCode == "rate-limited"
    }

    var grpcCode: Int? {
        details["grpcCode"] as? Int
    }

    var grpcStatus: String? {
        details["grpcStatus"] as? String
    }
}

extension GatewayAPIError: LocalizedError {
    var errorDescription: String? {
        switch self {
        case .notConfigured:
            return localized("此版本未设置中转服务")
        case .transport:
            return localized("目前无法连线中转服务，请检查网路后再试")
        case .server(let code, _, _, let details):
            // The Gateway's own text is English and technical (a zh-Hans deletion
            // showed "Apple access could not be revoked."); read the code instead.
            return Self.localizedMessage(code: code, upstream: details["upstream"] as? String)
        case .invalidResponse:
            return localized("中转服务回应格式不正确")
        }
    }

    private static func localizedMessage(code: String, upstream: String?) -> String {
        switch code {
        case "invalid-credentials":
            return localized("登入资讯不正确，请再试一次")
        case "wrong-account":
            return localized("请用这个帐号已连结的 Apple 或 Google 帐号验证")
        case "email-exists":
            return localized("这个电子邮件已被其他帐号使用")
        case "user-disabled":
            return localized("这个帐号已被停用")
        case "user-not-found":
            return localized("这个帐号已不存在")
        case "unauthenticated":
            return localized("登入状态已失效，请重新登入")
        case "reauth-required":
            return localized("为了保护帐号安全，请重新登入后再试")
        case "provider-already-linked":
            return localized("这个帐号已经连结过此登入方式")
        case "credential-already-in-use":
            return localized("此登入方式属于另一个帐号。你可以改用它登入那个帐号，或先在那个帐号解除连结。")
        case "cannot-unlink-last-provider":
            return localized("这是唯一的登入方式，解除后就无法再登入，请先连结另一种方式")
        case "rate-limited":
            return localized("尝试次数过多，请稍后再试")
        case "upstream-unavailable":
            return localized("服务暂时无法使用，请稍后再试")
        case "apple-revoke-failed":
            return localized("无法撤销 Apple 授权，帐号没有被删除，请稍后再试")
        case "cleanup-failed":
            return localized("帐号资料没有删除完成，帐号仍保留，请再试一次")
        case "invalid-argument" where upstream == "WEAK_PASSWORD":
            return localized("密码至少需要 6 个字元")
        case "invalid-argument" where upstream?.hasPrefix("INVALID_EMAIL") == true:
            return localized("电子邮件格式不正确")
        default:
            return String(format: localized("伺服器无法完成这个请求（%@）"), code)
        }
    }
}
