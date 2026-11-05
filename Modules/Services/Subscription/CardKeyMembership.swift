import Foundation
import Combine
import CryptoKit

/// 卡密会员：输入统一卡密即解锁永久会员。激活状态存 UserDefaults，跨启动保留。
/// 到期时间为永久（`expiresAt == nil` 表示永不过期）。
///
/// 名单**只**来自远端（maintainer, 2026-11-05：不要内置兜底）：
/// `https://gitee.com/Zi23333363/yuedu-keys/raw/master/cardkeys.json`
///
/// JSON 带 HMAC-SHA256 签名，App 用内置密钥验签。这样即使有人把域名指向自己的
/// 名单、或者直接改文件内容，签名对不上就整份丢弃，继续用上一次成功拉到的名单。
/// 注意：密钥编译在二进制里，反编译能拿到 —— 它挡的是「换地址伪造名单」这类
/// 低成本手段，不是专业逆向。真要防到那一步只能上服务端。
@MainActor
final class CardKeyMembership: ObservableObject {
    static let shared = CardKeyMembership()

    /// 远端名单。换仓库只动这一行。
    private static let remoteURL = URL(string: "https://gitee.com/Zi23333363/yuedu-keys/raw/master/cardkeys.json")!

    /// 验签密钥，32 字节。改名单必须同时改签名，否则整份作废。
    private static let signingKeyHex = "5d9e4f97ce0442a054daebafe4b0f94885f116998ff07dff57781642c48f722f"

    private static let activatedFlag = "cardkey_membership_activated"
    /// 激活时用的是哪条卡密，只有它被写进远端 `revoked` 才会收回会员。
    private static let activatedCard = "cardkey_membership_key"
    private static let cacheKeys = "cardkey_remote_keys"
    private static let cacheRevoked = "cardkey_remote_revoked"
    private static let cacheStamp = "cardkey_remote_stamp"
    /// 远端名单的本地有效期：10 分钟内重复启动不重复请求。
    private static let cacheTTL: TimeInterval = 600

    /// 是否已通过卡密激活永久会员。
    @Published private(set) var isUnlocked: Bool

    private var remoteKeys: Set<String> = []
    private var revokedKeys: Set<String> = []
    private var lastFetch: Date = .distantPast
    private var isRefreshing = false

    private init() {
        let defaults = UserDefaults.standard
        isUnlocked = defaults.bool(forKey: Self.activatedFlag)
        remoteKeys = Set(defaults.stringArray(forKey: Self.cacheKeys) ?? [])
        revokedKeys = Set(defaults.stringArray(forKey: Self.cacheRevoked) ?? [])
        lastFetch = defaults.object(forKey: Self.cacheStamp) as? Date ?? .distantPast
        Task { await refreshIfNeeded() }
    }

    /// 当前可用卡密：远端名单 − 已吊销。
    var allowedKeys: Set<String> {
        remoteKeys.subtracting(revokedKeys)
    }

    /// 拉远端名单并验签。`force` 为 true 时忽略 10 分钟缓存。
    ///
    /// 任何一步失败都直接返回，保留手上的旧名单 —— 断网、Gitee 抽风、JSON 写坏、
    /// 签名对不上，都不该把已经能用的卡密瞬间变成不能用。
    func refreshIfNeeded(force: Bool = false) async {
        guard !isRefreshing else { return }
        if !force, Date().timeIntervalSince(lastFetch) < Self.cacheTTL { return }

        isRefreshing = true
        defer { isRefreshing = false }

        var request = URLRequest(url: Self.remoteURL)
        request.timeoutInterval = 8
        request.cachePolicy = .reloadIgnoringLocalCacheData

        guard let (data, response) = try? await URLSession.shared.data(for: request),
              let http = response as? HTTPURLResponse,
              http.statusCode == 200
        else { return }

        struct Payload: Decodable {
            let version: Int?
            let keys: [String]?
            let revoked: [String]?
            let sig: String?
        }
        guard let payload = try? JSONDecoder().decode(Payload.self, from: data) else { return }

        let keys = Set((payload.keys ?? [])
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty })
        let revoked = Set((payload.revoked ?? [])
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty })
        let version = payload.version ?? 1

        // 先验签，再采信内容。顺序不能反：没验过的名单一律当作没拉到。
        guard let signature = payload.sig,
              Self.isValidSignature(
                signature,
                for: Self.canonical(version: version, keys: keys, revoked: revoked)
              )
        else { return }

        // 空名单几乎一定是远端写坏了。宁可保留旧名单，也不能让所有人激活失败。
        guard !keys.isEmpty else { return }

        remoteKeys = keys
        revokedKeys = revoked
        lastFetch = Date()
        persistCache()
        enforceRevocation()
    }

    /// 参与签名的规范串：键排序后拼接，必须和签名脚本逐字一致。
    private static func canonical(version: Int, keys: Set<String>, revoked: Set<String>) -> String {
        "v\(version)|\(keys.sorted().joined(separator: ","))|\(revoked.sorted().joined(separator: ","))"
    }

    /// 定长比较，避免逐字符短路泄漏签名前缀。
    private static func isValidSignature(_ signature: String, for message: String) -> Bool {
        guard let keyData = Data(hexString: signingKeyHex) else { return false }
        let mac = HMAC<SHA256>.authenticationCode(
            for: Data(message.utf8),
            using: SymmetricKey(data: keyData)
        )
        let expected = mac.map { String(format: "%02x", $0) }.joined()
        let lhs = Array(expected.utf8)
        let rhs = Array(signature.lowercased().utf8)
        guard lhs.count == rhs.count else { return false }

        var difference: UInt8 = 0
        for index in 0..<lhs.count {
            difference |= lhs[index] ^ rhs[index]
        }
        return difference == 0
    }

    private func persistCache() {
        let defaults = UserDefaults.standard
        defaults.set(Array(remoteKeys), forKey: Self.cacheKeys)
        defaults.set(Array(revokedKeys), forKey: Self.cacheRevoked)
        defaults.set(lastFetch, forKey: Self.cacheStamp)
    }

    /// 收回会员只认 `revoked`：单纯从 `keys` 里删一条，不影响已经激活的人。
    private func enforceRevocation() {
        guard isUnlocked,
              let used = UserDefaults.standard.string(forKey: Self.activatedCard),
              revokedKeys.contains(used)
        else { return }

        let defaults = UserDefaults.standard
        isUnlocked = false
        defaults.set(false, forKey: Self.activatedFlag)
        defaults.removeObject(forKey: Self.activatedCard)
    }

    /// 校验卡密；正确则激活永久会员并返回 `true`。
    @discardableResult
    func activate(_ key: String) -> Bool {
        let trimmed = key.trimmingCharacters(in: .whitespacesAndNewlines)
        guard allowedKeys.contains(trimmed) else { return false }

        let defaults = UserDefaults.standard
        isUnlocked = true
        defaults.set(true, forKey: Self.activatedFlag)
        defaults.set(trimmed, forKey: Self.activatedCard)
        return true
    }

    /// 永久会员：无到期时间。
    var expiresAt: Date? { nil }
}

private extension Data {
    /// 把 64 位 hex 还原成 32 字节密钥。
    init?(hexString: String) {
        let hex = hexString.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !hex.isEmpty, hex.count % 2 == 0 else { return nil }

        var data = Data(capacity: hex.count / 2)
        var index = hex.startIndex
        while index < hex.endIndex {
            let next = hex.index(index, offsetBy: 2)
            guard let byte = UInt8(hex[index..<next], radix: 16) else { return nil }
            data.append(byte)
            index = next
        }
        self = data
    }
}
