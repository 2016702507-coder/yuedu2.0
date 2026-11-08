import FirebaseAuth
import Foundation
import os

/// Firebase's `internalError` surfaces only the unhelpful "An internal error has
/// occurred…" string; the real reason (e.g. a provider not enabled in the console)
/// lives inside the NSError userInfo. This digs it out for display + logging.
enum AuthErrorReporter {

    static func describe(_ error: Error) -> String {
        // Gateway errors carry their own structured code; map them first so a
        // route decision or session state is never mistaken for a bad password.
        if let gatewayError = error as? GatewayAPIError {
            AppLogger.network(
                "sign-in failed (gateway): code=\(gatewayError.serverCode ?? "transport")",
                level: .error
            )
            if gatewayError.isConnectivityFailure {
                return localized("目前无法连线中转服务，请检查网路后再试")
            }
            return gatewayError.errorDescription ?? localized("登入失败，请稍后再试")
        }

        let ns = error as NSError
        AppLogger.network("sign-in failed: domain=\(ns.domain) code=\(ns.code) userInfo=\(ns.userInfo)", level: .error)

        if let server = serverMessage(from: ns) {
            if server.contains("CONFIGURATION_NOT_FOUND") || server.contains("OPERATION_NOT_ALLOWED") {
                return localized("此登入方式尚未在 Firebase 启用，请在 Console 开启对应的登入提供者")
            }
            return server
        }
        if let underlying = ns.userInfo[NSUnderlyingErrorKey] as? NSError,
           !underlying.localizedDescription.isEmpty {
            return "\(ns.localizedDescription)\n[\(underlying.domain) \(underlying.code)] \(underlying.localizedDescription)"
        }
        return ns.localizedDescription
    }

    /// Pulls the server-side message out of Firebase's deserialized response payload.
    private static func serverMessage(from error: NSError) -> String? {
        guard let response = error.userInfo["FIRAuthErrorUserInfoDeserializedResponseKey"] else {
            return nil
        }
        if let dict = response as? [String: Any] {
            if let errorDict = dict["error"] as? [String: Any], let message = errorDict["message"] as? String {
                return message
            }
            if let message = dict["message"] as? String {
                return message
            }
        }
        return String(describing: response)
    }
}
