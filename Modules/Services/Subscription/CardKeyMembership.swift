import Foundation
import Combine
import Security

/// 卡密会员：输入卡密由服务端校验，通过即解锁永久会员。激活状态存 UserDefaults，跨启动保留。
/// 到期时间为永久（`expiresAt == nil` 表示永不过期）。
///
/// **一机一码**：首次激活时把设备标识与服务端绑定，之后只有同一台设备能通过。
///
/// 设备标识存在 Keychain，不是 UserDefaults —— 后者卸载即清空，重装会被当成新设备，
/// 用户明明买了却激活不了。Keychain 在卸载重装后仍然保留。
///
/// 校验走服务端（腾讯云 SCF HTTP 函数）：App 只提交卡密 + 设备号，拿回
/// `{"valid":true|false}`。卡密名单和任何密钥都不在客户端，抓包或反编译都拿不到别的卡密。
@MainActor
final class CardKeyMembership: ObservableObject {
    static let shared = CardKeyMembership()

    /// 校验接口。换服务端只动这一行。
    private static let verifyURL = URL(string: "https://1304789126-baexqdakfo.ap-shanghai.tencentscf.com")!

    private static let activatedFlag = "cardkey_membership_activated"
    /// 激活时用的是哪条卡密，复验和收回都靠它。
    private static let activatedCard = "cardkey_membership_key"
    private static let checkStamp = "cardkey_membership_check_stamp"
    /// 已激活用户的复验间隔：10 分钟内重复启动不重复请求。
    private static let cacheTTL: TimeInterval = 600

    /// 本机设备标识，进程内只读一次。
    private static let deviceId = DeviceIdentity.current()

    /// 是否已通过卡密激活永久会员。
    @Published private(set) var isUnlocked: Bool

    /// 最近一次失败原因，UI 用它区分「卡密错」和「已在别的设备激活」。
    @Published private(set) var lastFailureReason: String?

    private var lastCheck: Date = .distantPast
    private var isRefreshing = false

    private init() {
        let defaults = UserDefaults.standard
        isUnlocked = defaults.bool(forKey: Self.activatedFlag)
        lastCheck = defaults.object(forKey: Self.checkStamp) as? Date ?? .distantPast
        Task { await refreshIfNeeded() }
    }

    /// 服务端校验结果。`nil` 表示网络或服务异常（调用方应保持原状态，不要当成「无效」）。
    private struct Outcome {
        let valid: Bool
        let reason: String?
    }

    private func verify(_ key: String) async -> Outcome? {
        var request = URLRequest(url: Self.verifyURL)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.timeoutInterval = 8
        request.httpBody = try? JSONSerialization.data(withJSONObject: [
            "cardKey": key,
            "deviceId": Self.deviceId
        ])

        struct Reply: Decodable {
            let valid: Bool
            let reason: String?
        }

        guard let (data, response) = try? await URLSession.shared.data(for: request),
              let http = response as? HTTPURLResponse
        else { return nil }

        // 429 限流、5xx 存储异常都算「暂时失败」，不动已有状态
        if http.statusCode == 429 || http.statusCode >= 500 { return nil }
        guard http.statusCode == 200,
              let reply = try? JSONDecoder().decode(Reply.self, from: data)
        else { return nil }

        return Outcome(valid: reply.valid, reason: reply.reason)
    }

    /// 复验已激活的卡密是否仍然有效。
    ///
    /// 只在「已激活 + 到了复验时间」时请求。任何失败都直接返回、保留手上的状态 ——
    /// 断网、服务端抽风、返回体写坏，都不该把已经能用的会员瞬间变成不能用。
    func refreshIfNeeded(force: Bool = false) async {
        guard !isRefreshing else { return }
        if !force, Date().timeIntervalSince(lastCheck) < Self.cacheTTL { return }
        guard let used = UserDefaults.standard.string(forKey: Self.activatedCard), !used.isEmpty else { return }

        isRefreshing = true
        defer { isRefreshing = false }

        // 只有服务端明确回答「无效」才收回；nil（网络失败）一律不动。
        guard let outcome = await verify(used) else { return }

        lastCheck = Date()
        UserDefaults.standard.set(lastCheck, forKey: Self.checkStamp)

        if !outcome.valid {
            lastFailureReason = outcome.reason
            revoke()
        }
    }

    /// 校验卡密；通过则激活永久会员并返回 `true`。
    @discardableResult
    func activate(_ key: String) async -> Bool {
        // 服务端按大写比对，客户端先统一，避免用户输小写被判错
        let trimmed = key.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
        guard !trimmed.isEmpty else { return false }

        guard let outcome = await verify(trimmed) else {
            lastFailureReason = "network"
            return false
        }

        guard outcome.valid else {
            lastFailureReason = outcome.reason ?? "unknown"
            return false
        }

        let defaults = UserDefaults.standard
        isUnlocked = true
        lastFailureReason = nil
        lastCheck = Date()
        defaults.set(true, forKey: Self.activatedFlag)
        defaults.set(trimmed, forKey: Self.activatedCard)
        defaults.set(lastCheck, forKey: Self.checkStamp)
        return true
    }

    private func revoke() {
        let defaults = UserDefaults.standard
        isUnlocked = false
        defaults.set(false, forKey: Self.activatedFlag)
        defaults.removeObject(forKey: Self.activatedCard)
    }

    /// 当前可用卡密：服务端校验模式下客户端不持有名单，只知道自己激活的那一条。
    var allowedKeys: Set<String> {
        guard isUnlocked,
              let used = UserDefaults.standard.string(forKey: Self.activatedCard),
              !used.isEmpty
        else { return [] }
        return [used]
    }

    /// 永久会员：无到期时间。
    var expiresAt: Date? { nil }
}

/// 设备标识：Keychain 里的一个 UUID，卸载重装不会变。
private enum DeviceIdentity {
    private static let service = "com.yuedu.reader.identity"
    private static let account = "device_id"

    static func current() -> String {
        if let existing = read(), !existing.isEmpty { return existing }
        let created = UUID().uuidString
        write(created)
        return created
    }

    private static func baseQuery() -> [String: Any] {
        [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account
        ]
    }

    private static func read() -> String? {
        var query = baseQuery()
        query[kSecReturnData as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne

        var item: CFTypeRef?
        guard SecItemCopyMatching(query as CFDictionary, &item) == errSecSuccess,
              let data = item as? Data,
              let value = String(data: data, encoding: .utf8)
        else { return nil }
        return value
    }

    private static func write(_ value: String) {
        SecItemDelete(baseQuery() as CFDictionary)

        var attributes = baseQuery()
        attributes[kSecValueData as String] = Data(value.utf8)
        // 首次解锁后可读：后台校验也能拿到，且不会因为锁屏失败
        attributes[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlock
        SecItemAdd(attributes as CFDictionary, nil)
    }
}
