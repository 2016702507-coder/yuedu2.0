import Foundation
import Combine
import Security
import CryptoKit

/// 会员档位。`forever` 永久，`month` 自首次激活起 30 天。
enum CardKeyPlan: String {
    case none
    case month
    case forever

    /// 服务端返回的档位字串；认不出来时当永久处理 —— 宁可多给一次，
    /// 也不要因为协议多了一个新值就把已付费用户锁在门外。
    init(serverValue: String?) {
        switch serverValue ?? "" {
        case CardKeyPlan.month.rawValue: self = .month
        case CardKeyPlan.forever.rawValue: self = .forever
        default: self = .forever
        }
    }
}

/// 卡密会员：输入卡密由服务端校验，通过即解锁对应档位的会员。
///
/// **一机一码**：首次激活时把设备标识与服务端绑定，之后只有同一台设备能通过。
///
/// **两档权益**：永久卡（`expiresAt == nil`）与月卡（首次激活 + 30 天，到期时间
/// 由服务端在首次激活时写死，客户端只负责呈现）。到期后本地直接收回，不必等联网；
/// 服务端在校验时也会拒掉同一条已过期的卡密。
///
/// 设备标识存在 Keychain，不是 UserDefaults —— 后者卸载即清空，重装会被当成新设备，
/// 用户明明买了却激活不了。Keychain 在卸载重装后仍然保留。
///
/// 校验走服务端（腾讯云 SCF HTTP 函数）：App 只提交卡密 + 设备号，拿回
/// `{"valid":true,"plan":"month","expiresAt":"..."}`。卡密名单和任何密钥都不在客户端，
/// 抓包或反编译都拿不到别的卡密。
@MainActor
final class CardKeyMembership: ObservableObject {
    static let shared = CardKeyMembership()

    /// 校验接口。换服务端只动这一行。
    private static let verifyURL = URL(string: "https://1304789126-baexqdakfo.ap-shanghai.tencentscf.com")!

    /// 服务端 Ed25519 签名的公钥（base64，32 字节 raw representation）。
    ///
    /// 私钥只在 SCF 的环境变量 `CARDKEY_PRIVATE_KEY_B64` 里，公钥放客户端没有风险
    /// —— 它只能验签，签不出来。
    ///
    /// 换密钥要发版：这串改了之后，旧版客户端验不过新版服务端的签名。
    private static let signingPublicKeyBase64 = "2jEmK/Vpmh6MP4BC//sCR7RJmFfb6IfWrgpZG7aarBM="

    /// 是否强制要求服务端签名。
    ///
    /// **必须是 `true`**：一旦允许「没有 sig 就放行」，改包的人只要把 sig
    /// 字段删掉就能绕过整套验签。服务端已于 2026-11-07 上线签名
    /// （`cardkey` 函数 + 环境变量 `CARDKEY_PRIVATE_KEY_B64`），所以这里收紧。
    ///
    /// 代价：服务端若丢了私钥环境变量，复验会被全部拒绝（已激活用户保持现状、
    /// 不掉会员，但新激活会失败）。重部署后记得检查那条变量还在。
    private static let requiresSignature = true

    /// 响应的保鲜期：签名只证明内容没被改，不证明它是新的。
    /// 这条挡的是「截获一次 `valid=true` 之后反复回放」。
    private static let maxResponseAge: TimeInterval = 1_800

    private static let activatedFlag = "cardkey_membership_activated"
    /// 激活时用的是哪条卡密，复验和收回都靠它。
    private static let activatedCard = "cardkey_membership_key"
    private static let checkStamp = "cardkey_membership_check_stamp"
    private static let planKey = "cardkey_membership_plan"
    /// 到期时间；永久卡不写这个键。
    private static let expiresKey = "cardkey_membership_expires_at"
    /// 最近一次服务端时间，以及拿到它时的本机时间：用来挡「把系统时间往回调」。
    private static let serverAnchorKey = "cardkey_membership_server_anchor"
    private static let localAnchorKey = "cardkey_membership_local_anchor"

    /// 已激活用户的复验间隔：10 分钟内重复启动不重复请求。
    /// 后台改完会员后，最迟约 10 分钟就会拉到新档位（配合下面的前台定时复验）。
    private static let cacheTTL: TimeInterval = 600

    /// 重装恢复**失败**后的重试间隔（多半是断网）。
    ///
    /// 不能跟著 `cacheTTL` 走：10 分钟是「已激活后多久复验一次」的节律，
    /// 而断网重装的人联网后应该一分钟内就接回来，不该等满 10 分钟。
    private static let restoreRetryDelay: TimeInterval = 60

    /// 本机设备标识，进程内只读一次。
    private static let deviceId = CardKeyDeviceIdentity.current()

    /// 是否已有可用的会员（未激活或已到期都为 false）。
    @Published private(set) var isUnlocked: Bool

    /// 目前生效的档位，未激活为 `.none`。
    @Published private(set) var plan: CardKeyPlan

    /// 到期时间；永久卡为 nil。
    @Published private(set) var expiresAt: Date?

    /// 最近一次失败原因，UI 用它区分「卡密错」「已在别的设备激活」「已过期」。
    @Published private(set) var lastFailureReason: String? = nil

    /// 会员状态被动改变（到期、远端吊销）时回调，`SubscriptionStore` 用它重算权益。
    /// 用回调而不是通知中心：调用方是 @MainActor，闭包直接在该上下文跑。
    var onStateChanged: (@MainActor () -> Void)?

    private var lastCheck: Date = .distantPast
    /// 上次用 Keychain 卡密尝试恢复的时间（内存即可，重启后立刻可重试）。
    private var lastRestoreAttempt: Date = .distantPast
    private var isRefreshing = false
    private var expiryTimer: Timer?
    /// 前台周期性复验：后台改完会员后，最迟约 10 分钟就能拉到新档位，
    /// 不必等用户手动重开或切后台。Timer 在后台会被系统挂起，回到前台
    /// 由 `refreshIfNeeded()` 兜底。
    private var recheckTimer: Timer?

    private init() {
        let defaults = UserDefaults.standard
        let storedPlan = CardKeyPlan(rawValue: defaults.string(forKey: Self.planKey) ?? "") ?? .none
        let storedExpiry = defaults.object(forKey: Self.expiresKey) as? Date
        plan = storedPlan
        expiresAt = storedExpiry
        isUnlocked = defaults.bool(forKey: Self.activatedFlag) && !Self.hasExpired(storedExpiry)
        lastCheck = defaults.object(forKey: Self.checkStamp) as? Date ?? .distantPast

        if isUnlocked, plan == .none {
            // 旧版本只有永久卡，升级上来的机器没有档位记录，按永久接住
            plan = .forever
            defaults.set(CardKeyPlan.forever.rawValue, forKey: Self.planKey)
        }
        if !isUnlocked, defaults.bool(forKey: Self.activatedFlag) {
            // 关机期间到期的月卡：启动即收回，不闪一下会员界面。
            revoke(reason: "expired")
        }
        scheduleExpiryTimer()

        // 存量用户：1.2 以前的卡密只写在 UserDefaults，补一份进 Keychain ——
        // 否则「重装自动恢复」只对 1.3 之后新激活的人生效。
        if let legacyKey = defaults.string(forKey: Self.activatedCard),
           !legacyKey.isEmpty,
           CardKeyStore.read() == nil {
            CardKeyStore.write(legacyKey)
        }

        // 重装：UserDefaults 被清空，但 Keychain 里的卡密还在（设备标识就在那儿，
        // 所以服务端仍认得这台机器）。下面的 `refreshIfNeeded` 会用它把会员接回来。
        Task { await refreshIfNeeded() }
        startRecheckTimer()
    }

    /// 重装或清空资料后，用 Keychain 里的卡密把会员接回来。
    ///
    /// 只有在服务端**明确**回答有效时才恢复；网络失败一律保持现状，下次启动再试 ——
    /// 断网不该让老用户看到「未激活」。服务端明确拒绝（过期、吊销、已绑别的设备）
    /// 则把 Keychain 那条清掉，免得每次启动都白问一次。
    private func restoreFromKeychain(_ key: String) async {
        guard !isUnlocked else { return }
        // 刚试过就别再问：回前台、多个视图的 onAppear 都会走到 refreshIfNeeded，
        // 而服务端挂掉时这里是每次都会失败的。失败只挡一小会儿，成功才进入
        // `cacheTTL` 那 10 分钟的复验节律 —— 写 lastCheck 是「复验成功」的语义，
        // 失败不该占用它。
        if Date().timeIntervalSince(lastRestoreAttempt) < Self.restoreRetryDelay { return }
        lastRestoreAttempt = Date()

        guard let outcome = await verify(key) else { return }
        guard outcome.valid else {
            CardKeyStore.clear()
            return
        }

        let defaults = UserDefaults.standard
        defaults.set(true, forKey: Self.activatedFlag)
        defaults.set(key, forKey: Self.activatedCard)
        lastCheck = Date()
        defaults.set(lastCheck, forKey: Self.checkStamp)
        lastFailureReason = nil
        apply(outcome)
        onStateChanged?()
    }

    // MARK: - 到期判定

    /// 目前时间，取「本机时间」与「服务端时间推算值」中较晚的一个。
    ///
    /// 把系统时间往回调可以骗过单纯的 `Date()`；用上次校验拿到的服务端时间加上
    /// 从那时起流逝的本机时长，回调时间就得不到好处。长时间离线时两者一致，
    /// 这一层挡不住 —— 离线场景本来就没有可用的可信时钟。
    private static func effectiveNow() -> Date {
        let defaults = UserDefaults.standard
        guard let server = defaults.object(forKey: serverAnchorKey) as? Date,
              let local = defaults.object(forKey: localAnchorKey) as? Date
        else { return Date() }
        let projected = server.addingTimeInterval(max(0, Date().timeIntervalSince(local)))
        return max(Date(), projected)
    }

    private static func hasExpired(_ date: Date?) -> Bool {
        guard let date else { return false }
        return effectiveNow() >= date
    }

    /// 剩余天数（向上取整）。永久卡返回 nil，已过期返回 0。
    var remainingDays: Int? {
        guard let expiresAt, plan == .month else { return nil }
        let seconds = expiresAt.timeIntervalSince(Self.effectiveNow())
        guard seconds > 0 else { return 0 }
        return Int(ceil(seconds / 86_400))
    }

    // MARK: - 校验

    /// 服务端校验结果。`nil` 表示网络或服务异常（调用方应保持原状态，不要当成「无效」）。
    private struct Outcome {
        let valid: Bool
        let reason: String?
        let plan: CardKeyPlan?
        let expiresAt: Date?
        let serverNow: Date?
    }

    /// 服务端返回体。`expiresAt` / `serverNow` 保留原始字符串 ——
    /// 验签要用它们原样拼进 payload，解析成 `Date` 会丢掉毫秒精度。
    private struct VerifyReply: Decodable {
        let valid: Bool
        let reason: String?
        let plan: String?
        let expiresAt: String?
        let serverNow: String?
        /// 服务端 Ed25519 签名（base64）。过渡期允许缺失，见 `requiresSignature`。
        let sig: String?
    }

    private static func parseDate(_ text: String?) -> Date? {
        guard let text, !text.isEmpty else { return nil }
        let formatter = ISO8601DateFormatter()
        // 服务端用 toISOString()，带毫秒；`.iso8601` 解码策略不认毫秒，这里手动两试。
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let date = formatter.date(from: text) { return date }
        formatter.formatOptions = [.withInternetDateTime]
        return formatter.date(from: text)
    }

    private func verify(_ key: String) async -> Outcome? {
        // 请求与验签必须用同一个设备号，取一次钉住。
        let deviceId = Self.deviceId
        var request = URLRequest(url: Self.verifyURL)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.timeoutInterval = 8
        request.httpBody = try? JSONSerialization.data(withJSONObject: [
            "cardKey": key,
            "deviceId": deviceId
        ])

        guard let (data, response) = try? await URLSession.shared.data(for: request),
              let http = response as? HTTPURLResponse
        else { return nil }

        // 429 限流、5xx 存储异常都算「暂时失败」，不动已有状态
        if http.statusCode == 429 || http.statusCode >= 500 { return nil }
        guard http.statusCode == 200,
              let reply = try? JSONDecoder().decode(VerifyReply.self, from: data)
        else { return nil }

        // 签名不对就当「不可信响应」，返回 nil（调用方保持原状态）。
        // 这里**不能** revoke：否则任何人返回一段垃圾都能把付费用户踢下线。
        guard Self.signatureIsValid(reply, cardKey: key, deviceId: deviceId) else {
            return nil
        }

        // 保鲜期：挡「截一次 valid=true 反复回放」。服务端缺席时，过渡期放行。
        if let serverNow = Self.parseDate(reply.serverNow) {
            guard abs(serverNow.timeIntervalSinceNow) <= Self.maxResponseAge else { return nil }
        } else if Self.requiresSignature {
            return nil
        }

        return Outcome(
            valid: reply.valid,
            reason: reply.reason,
            plan: reply.plan.map { CardKeyPlan(serverValue: $0) },
            expiresAt: Self.parseDate(reply.expiresAt),
            serverNow: Self.parseDate(reply.serverNow)
        )
    }

    // MARK: - 响应验签

    /// 重建服务端签过的那串内容。
    ///
    /// 顺序、分隔符、空值写法三方（SCF、这里、测试脚本）必须一字不差。
    /// 特别注意 `expiresAt` / `serverNow` 用的是**原始字符串**而不是解析后的
    /// `Date` —— 一旦格式化再签，毫秒位一变就对不上。
    private static func signedPayload(
        valid: Bool,
        plan: String?,
        expiresAt: String?,
        cardKey: String,
        deviceId: String,
        serverNow: String?
    ) -> Data {
        let fields = [
            "v1",
            valid ? "true" : "false",
            plan ?? "",
            expiresAt ?? "",
            cardKey,
            deviceId,
            serverNow ?? "",
        ]
        return Data(fields.joined(separator: "\n").utf8)
    }

    /// 公钥是否已填。没填时整段验签跳过 —— 宁可这版没有防护，
    /// 也不能因为忘了填公钥让所有人激活失败。
    private static var hasSigningKey: Bool {
        guard let data = Data(base64Encoded: signingPublicKeyBase64) else { return false }
        return data.count == 32
    }

    /// 验签。返回 false 表示响应不可信，调用方应按「暂时失败」处理。
    private static func signatureIsValid(
        _ reply: VerifyReply,
        cardKey: String,
        deviceId: String
    ) -> Bool {
        guard hasSigningKey else { return true }

        // 过渡期：服务端还没加签时放行；一旦带了 sig，就必须验过。
        guard let sigBase64 = reply.sig, !sigBase64.isEmpty else {
            return !requiresSignature
        }
        guard let sig = Data(base64Encoded: sigBase64),
              let pubData = Data(base64Encoded: signingPublicKeyBase64),
              let pub = try? Curve25519.Signing.PublicKey(rawRepresentation: pubData)
        else { return false }

        let payload = signedPayload(
            valid: reply.valid,
            plan: reply.plan,
            expiresAt: reply.expiresAt,
            cardKey: cardKey,
            deviceId: deviceId,
            serverNow: reply.serverNow
        )
        return pub.isValidSignature(sig, for: payload)
    }

    /// 复验已激活的卡密是否仍然有效。
    ///
    /// 只在「已激活 + 到了复验时间」时请求。任何失败都直接返回、保留手上的状态 ——
    /// 断网、服务端抽风、返回体写坏，都不该把已经能用的会员瞬间变成不能用。
    func refreshIfNeeded(force: Bool = false) async {
        // 未激活但有 Keychain 卡密：重装后的第一次联网。接回来再走正常流程 ——
        // 放在这里，App 回到前台时也会重试，断网重装的人不必再重启一次。
        if !isUnlocked {
            if let storedKey = CardKeyStore.read() {
                await restoreFromKeychain(storedKey)
            }
            return
        }

        // 本地到期不需要等网络：先把已经过期的收回。
        if Self.hasExpired(expiresAt) {
            revoke(reason: "expired")
            return
        }

        guard !isRefreshing else { return }
        if !force, Date().timeIntervalSince(lastCheck) < Self.cacheTTL { return }
        guard let used = UserDefaults.standard.string(forKey: Self.activatedCard), !used.isEmpty else { return }

        isRefreshing = true
        defer { isRefreshing = false }

        // 只有服务端明确回答「无效」才收回；nil（网络失败）一律不动。
        guard let outcome = await verify(used) else { return }

        lastCheck = Date()
        UserDefaults.standard.set(lastCheck, forKey: Self.checkStamp)

        if outcome.valid {
            apply(outcome)
        } else {
            lastFailureReason = outcome.reason
            revoke(reason: outcome.reason ?? "unknown")
        }
    }

    /// 校验卡密；通过则按服务端返回的档位激活并返回 `true`。
    @discardableResult
    func activate(_ key: String) async -> Bool {
        // 服务端按大写比对，客户端先统一，避免用户输小写被判错
        let trimmed = key.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
        guard !trimmed.isEmpty else { return false }

        // 已是永久会员就不用再验了：让月卡覆盖上去等于把永久降级，
        // 而且会白白消耗掉这条卡密的绑定名额。
        guard plan != .forever || !isUnlocked else {
            lastFailureReason = "already_forever"
            return false
        }

        guard let outcome = await verify(trimmed) else {
            lastFailureReason = "network"
            return false
        }

        guard outcome.valid else {
            lastFailureReason = outcome.reason ?? "unknown"
            return false
        }

        let defaults = UserDefaults.standard
        defaults.set(true, forKey: Self.activatedFlag)
        defaults.set(trimmed, forKey: Self.activatedCard)
        // 卡密另存一份进 Keychain：UserDefaults 卸载即清，重装后靠它自动恢复。
        CardKeyStore.write(trimmed)
        lastCheck = Date()
        defaults.set(lastCheck, forKey: Self.checkStamp)
        lastFailureReason = nil
        apply(outcome)
        // apply 会在「服务端给的到期时间已过」时直接收回，这里以最终状态为准
        return isUnlocked
    }

    /// 把服务端结果落到本机：档位、到期时间、时间锚点。
    private func apply(_ outcome: Outcome) {
        // 服务端没带档位时按永久处理，不要留著 `.none` 让 UI 显示成「未激活」
        plan = outcome.plan ?? (plan == .none ? .forever : plan)
        expiresAt = outcome.expiresAt

        let defaults = UserDefaults.standard
        defaults.set(plan.rawValue, forKey: Self.planKey)
        if let date = expiresAt {
            defaults.set(date, forKey: Self.expiresKey)
        } else {
            defaults.removeObject(forKey: Self.expiresKey)
        }
        if let server = outcome.serverNow {
            defaults.set(server, forKey: Self.serverAnchorKey)
            defaults.set(Date(), forKey: Self.localAnchorKey)
        }

        if Self.hasExpired(expiresAt) {
            revoke(reason: "expired")
            return
        }
        isUnlocked = true
        scheduleExpiryTimer()
    }

    private func revoke(reason: String?) {
        let defaults = UserDefaults.standard
        isUnlocked = false
        plan = .none
        expiresAt = nil
        expiryTimer?.invalidate()
        expiryTimer = nil

        defaults.set(false, forKey: Self.activatedFlag)
        defaults.removeObject(forKey: Self.activatedCard)
        defaults.removeObject(forKey: Self.expiresKey)
        defaults.set(CardKeyPlan.none.rawValue, forKey: Self.planKey)
        // 明确失效（过期、吊销）才清 Keychain 那份；否则重装后会把死卡密又捡回来。
        CardKeyStore.clear()

        if let reason { lastFailureReason = reason }
        onStateChanged?()
    }

    /// 每 10 分钟向服务端复验一次，让后台改完的档位自动反映到本机。
    /// 写法沿用 `scheduleExpiryTimer`：Timer 挂在主 RunLoop，后台自动挂起。
    /// 用 `force: true` 是为了避开与 `cacheTTL` 等长的节流边界（否则可能
    /// 差几毫秒被跳过、变成 20 分钟才刷一次）。
    private func startRecheckTimer() {
        recheckTimer?.invalidate()
        recheckTimer = Timer.scheduledTimer(withTimeInterval: Self.cacheTTL, repeats: true) { [weak self] _ in
            Task { @MainActor in
                guard let self else { return }
                await self.refreshIfNeeded(force: true)
            }
        }
    }

    /// 到期那一刻把会员收回，不用等用户重启 App。
    ///
    /// 只排一次：到点触发后 `recompute` 走 `revoke`，计时器自然清掉。
    /// 后台期间 Timer 会被挂起，回到前台时 `refreshIfNeeded` 兜底。
    private func scheduleExpiryTimer() {
        expiryTimer?.invalidate()
        guard isUnlocked, let expiresAt, plan == .month else {
            expiryTimer = nil
            return
        }
        let delay = expiresAt.timeIntervalSince(Self.effectiveNow())
        guard delay > 0 else {
            Task { @MainActor in self.revoke(reason: "expired") }
            return
        }
        // 上限 60 秒：本机时钟小幅回拨时能及早重算
        // 上限一小时：后台 Timer 会被挂起，回到前台后重新校准一次就够
        expiryTimer = Timer.scheduledTimer(withTimeInterval: min(delay, 3600), repeats: false) { [weak self] _ in
            Task { @MainActor in
                guard let self else { return }
                if Self.hasExpired(self.expiresAt) {
                    self.revoke(reason: "expired")
                } else {
                    self.scheduleExpiryTimer()
                }
            }
        }
    }

    /// 目前可用卡密：服务端校验模式下客户端不持有名单，只知道自己激活的那一条。
    var activeCardKey: String? {
        guard isUnlocked else { return nil }
        return UserDefaults.standard.string(forKey: Self.activatedCard)
    }

    /// 这台装置在卡密后台的身份（Keychain 里的 UUID，重装不变）。
    /// 显示在「关于」里，供换机、清空 Keychain 这类自动恢复接不回来的情况人工补绑。
    var deviceCode: String { Self.deviceId }
}

/// 卡密明文：与设备标识一样存 Keychain，卸载重装仍在。
///
/// 这是「重装后自动恢复会员」的依据。之前它只存在 `UserDefaults`，卸载即清，
/// 而 `refreshIfNeeded` 又以「已激活」为前提 —— 两者一叠，重装后必得重输卡密。
/// 没有打开 `kSecAttrSynchronizable`：这条卡密绑的是本机设备号，跟著 iCloud
/// Keychain 跑到另一台装置上没有意义，也换不来恢复。
private enum CardKeyStore {
    private static let service = "com.yuedu.reader.cardkey"
    private static let account = "activated_key"

    private static func baseQuery() -> [String: Any] {
        [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account
        ]
    }

    static func read() -> String? {
        var query = baseQuery()
        query[kSecReturnData as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne

        var item: CFTypeRef?
        guard SecItemCopyMatching(query as CFDictionary, &item) == errSecSuccess,
              let data = item as? Data,
              let value = String(data: data, encoding: .utf8),
              !value.isEmpty
        else { return nil }
        return value
    }

    static func write(_ value: String) {
        SecItemDelete(baseQuery() as CFDictionary)

        var attributes = baseQuery()
        attributes[kSecValueData as String] = Data(value.utf8)
        // 与设备标识一致：首次解锁后可读，后台校验也拿得到
        attributes[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlock
        SecItemAdd(attributes as CFDictionary, nil)
    }

    static func clear() {
        SecItemDelete(baseQuery() as CFDictionary)
    }
}

/// 设备标识：Keychain 里的一个 UUID，卸载重装不会变。
private enum CardKeyDeviceIdentity {
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
