import Foundation
import Combine

/// 卡密会员：输入卡密由服务端校验，通过即解锁永久会员。激活状态存 UserDefaults，跨启动保留。
/// 到期时间为永久（`expiresAt == nil` 表示永不过期）。
///
/// 校验走服务端（腾讯云 SCF HTTP 函数）：
/// App 只提交卡密、拿回 `{"valid": true|false}`，**名单和密钥都不下发**。
/// 相比之前从 Gitee 拉签名名单的做法，这样即使有人抓包或反编译，也只能看到一个
/// 校验接口，拿不到其他卡密；要封谁，服务端改一行数据即可，不用发版。
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

    /// 是否已通过卡密激活永久会员。
    @Published private(set) var isUnlocked: Bool

    private var lastCheck: Date = .distantPast
    private var isRefreshing = false

    private init() {
        let defaults = UserDefaults.standard
        isUnlocked = defaults.bool(forKey: Self.activatedFlag)
        lastCheck = defaults.object(forKey: Self.checkStamp) as? Date ?? .distantPast
        Task { await refreshIfNeeded() }
    }

    /// 向服务端校验一条卡密。
    ///
    /// 返回 `nil` 表示网络或服务异常（调用方应保持原状态，不要当成「无效」）。
    private func verify(_ key: String) async -> Bool? {
        var request = URLRequest(url: Self.verifyURL)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.timeoutInterval = 8
        request.httpBody = try? JSONSerialization.data(withJSONObject: ["cardKey": key])

        struct Reply: Decodable { let valid: Bool }

        guard let (data, response) = try? await URLSession.shared.data(for: request),
              let http = response as? HTTPURLResponse,
              http.statusCode == 200,
              let reply = try? JSONDecoder().decode(Reply.self, from: data)
        else { return nil }

        return reply.valid
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
        guard let valid = await verify(used) else { return }

        lastCheck = Date()
        UserDefaults.standard.set(lastCheck, forKey: Self.checkStamp)

        if !valid { revoke() }
    }

    /// 校验卡密；通过则激活永久会员并返回 `true`。
    @discardableResult
    func activate(_ key: String) async -> Bool {
        let trimmed = key.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return false }
        guard let valid = await verify(trimmed), valid else { return false }

        let defaults = UserDefaults.standard
        isUnlocked = true
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
