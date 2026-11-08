import Foundation
import Combine
import Security
import CryptoKit

/// 會員檔位。`forever` 永久，`month` 自首次激活起 30 天。
enum CardKeyPlan: String {
    case none
    case month
    case forever

    /// 服務端返回的檔位字串；認不出來時當永久處理 —— 寧可多給一次，
    /// 也不要因為協議多了一個新值就把已付費用戶鎖在門外。
    init(serverValue: String?) {
        switch serverValue ?? "" {
        case CardKeyPlan.month.rawValue: self = .month
        case CardKeyPlan.forever.rawValue: self = .forever
        default: self = .forever
        }
    }
}

/// 卡密會員：輸入卡密由服務端校驗，通過即解鎖對應檔位的會員。
///
/// **一機一碼**：首次激活時把設備標識與服務端綁定，之後只有同一台設備能通過。
///
/// **兩檔權益**：永久卡（`expiresAt == nil`）與月卡（首次激活 + 30 天，到期時間
/// 由服務端在首次激活時寫死，客戶端只負責呈現）。到期後本地直接收回，不必等聯網；
/// 服務端在校驗時也會拒掉同一條已過期的卡密。
///
/// 設備標識存在 Keychain，不是 UserDefaults —— 後者卸載即清空，重裝會被當成新設備，
/// 用戶明明買了卻激活不了。Keychain 在卸載重裝後仍然保留。
///
/// 校驗走服務端（騰訊雲 SCF HTTP 函數）：App 只提交卡密 + 設備號，拿回
/// `{"valid":true,"plan":"month","expiresAt":"..."}`。卡密名單和任何密鑰都不在客戶端，
/// 抓包或反編譯都拿不到別的卡密。
@MainActor
final class CardKeyMembership: ObservableObject {
    static let shared = CardKeyMembership()

    /// 校驗接口。換服務端只動這一行。
    private static let verifyURL = URL(string: "https://1304789126-baexqdakfo.ap-shanghai.tencentscf.com")!

    /// 服務端 Ed25519 簽名的公鑰（base64，32 字節 raw representation）。
    ///
    /// 私鑰只在 SCF 的環境變量 `CARDKEY_PRIVATE_KEY_B64` 裡，公鑰放客戶端沒有風險
    /// —— 它只能驗籤，簽不出來。
    ///
    /// 換密鑰要發版：這串改了之後，舊版客戶端驗不過新版服務端的簽名。
    private static let signingPublicKeyBase64 = "2jEmK/Vpmh6MP4BC//sCR7RJmFfb6IfWrgpZG7aarBM="

    /// 是否強制要求服務端簽名。
    ///
    /// **必須是 `true`**：一旦允許「沒有 sig 就放行」，改包的人只要把 sig
    /// 字段刪掉就能繞過整套驗籤。服務端已於 2026-11-07 上線簽名
    /// （`cardkey` 函數 + 環境變量 `CARDKEY_PRIVATE_KEY_B64`），所以這裡收緊。
    ///
    /// 代價：服務端若丟了私鑰環境變量，複驗會被全部拒絕（已激活用戶保持現狀、
    /// 不掉會員，但新激活會失敗）。重部署後記得檢查那條變量還在。
    private static let requiresSignature = true

    /// 響應的保鮮期：簽名只證明內容沒被改，不證明它是新的。
    /// 這條擋的是「截獲一次 `valid=true` 之後反覆回放」。
    private static let maxResponseAge: TimeInterval = 1_800

    private static let activatedFlag = "cardkey_membership_activated"
    /// 激活時用的是哪條卡密，複驗和收回都靠它。
    private static let activatedCard = "cardkey_membership_key"
    private static let checkStamp = "cardkey_membership_check_stamp"
    private static let planKey = "cardkey_membership_plan"
    /// 到期時間；永久卡不寫這個鍵。
    private static let expiresKey = "cardkey_membership_expires_at"
    /// 最近一次服務端時間，以及拿到它時的本機時間：用來擋「把系統時間往回調」。
    private static let serverAnchorKey = "cardkey_membership_server_anchor"
    private static let localAnchorKey = "cardkey_membership_local_anchor"

    /// 已激活用戶的複驗間隔：一小時內重複啟動不重複請求。
    private static let cacheTTL: TimeInterval = 3_600

    /// 重裝恢復**失敗**後的重試間隔（多半是斷網）。
    ///
    /// 不能跟著 `cacheTTL` 走：一小時是「已激活後多久複驗一次」的節律，
    /// 而斷網重裝的人聯網後應該一分鐘內就接回來，不該等一小時。
    private static let restoreRetryDelay: TimeInterval = 60

    /// 本機設備標識，進程內只讀一次。
    private static let deviceId = CardKeyDeviceIdentity.current()

    /// 是否已有可用的會員（未激活或已到期都為 false）。
    @Published private(set) var isUnlocked: Bool

    /// 目前生效的檔位，未激活為 `.none`。
    @Published private(set) var plan: CardKeyPlan

    /// 到期時間；永久卡為 nil。
    @Published private(set) var expiresAt: Date?

    /// 最近一次失敗原因，UI 用它區分「卡密錯」「已在別的設備激活」「已過期」。
    @Published private(set) var lastFailureReason: String? = nil

    /// 會員狀態被動改變（到期、遠端吊銷）時回調，`SubscriptionStore` 用它重算權益。
    /// 用回調而不是通知中心：調用方是 @MainActor，閉包直接在該上下文跑。
    var onStateChanged: (@MainActor () -> Void)?

    private var lastCheck: Date = .distantPast
    /// 上次用 Keychain 卡密嘗試恢復的時間（內存即可，重啟後立刻可重試）。
    private var lastRestoreAttempt: Date = .distantPast
    private var isRefreshing = false
    private var expiryTimer: Timer?

    private init() {
        let defaults = UserDefaults.standard
        let storedPlan = CardKeyPlan(rawValue: defaults.string(forKey: Self.planKey) ?? "") ?? .none
        let storedExpiry = defaults.object(forKey: Self.expiresKey) as? Date
        plan = storedPlan
        expiresAt = storedExpiry
        isUnlocked = defaults.bool(forKey: Self.activatedFlag) && !Self.hasExpired(storedExpiry)
        lastCheck = defaults.object(forKey: Self.checkStamp) as? Date ?? .distantPast

        if isUnlocked, plan == .none {
            // 舊版本只有永久卡，升級上來的機器沒有檔位記錄，按永久接住
            plan = .forever
            defaults.set(CardKeyPlan.forever.rawValue, forKey: Self.planKey)
        }
        if !isUnlocked, defaults.bool(forKey: Self.activatedFlag) {
            // 關機期間到期的月卡：啟動即收回，不閃一下會員界面。
            revoke(reason: "expired")
        }
        scheduleExpiryTimer()

        // 存量用戶：1.2 以前的卡密只寫在 UserDefaults，補一份進 Keychain ——
        // 否則「重裝自動恢復」只對 1.3 之後新激活的人生效。
        if let legacyKey = defaults.string(forKey: Self.activatedCard),
           !legacyKey.isEmpty,
           CardKeyStore.read() == nil {
            CardKeyStore.write(legacyKey)
        }

        // 重裝：UserDefaults 被清空，但 Keychain 裡的卡密還在（設備標識就在那兒，
        // 所以服務端仍認得這台機器）。下面的 `refreshIfNeeded` 會用它把會員接回來。
        Task { await refreshIfNeeded() }
    }

    /// 重裝或清空資料後，用 Keychain 裡的卡密把會員接回來。
    ///
    /// 只有在服務端**明確**回答有效時才恢復；網絡失敗一律保持現狀，下次啟動再試 ——
    /// 斷網不該讓老用戶看到「未激活」。服務端明確拒絕（過期、吊銷、已綁別的設備）
    /// 則把 Keychain 那條清掉，免得每次啟動都白問一次。
    private func restoreFromKeychain(_ key: String) async {
        guard !isUnlocked else { return }
        // 剛試過就別再問：回前台、多個視圖的 onAppear 都會走到 refreshIfNeeded，
        // 而服務端掛掉時這裡是每次都會失敗的。失敗只擋一小會兒，成功才進入
        // `cacheTTL` 那一小時的複驗節律 —— 寫 lastCheck 是「複驗成功」的語義，
        // 失敗不該佔用它。
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

    /// 目前時間，取「本機時間」與「服務端時間推算值」中較晚的一個。
    ///
    /// 把系統時間往回調可以騙過單純的 `Date()`；用上次校驗拿到的服務端時間加上
    /// 從那時起流逝的本機時長，回調時間就得不到好處。長時間離線時兩者一致，
    /// 這一層擋不住 —— 離線場景本來就沒有可用的可信時鐘。
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

    /// 剩餘天數（向上取整）。永久卡返回 nil，已過期返回 0。
    var remainingDays: Int? {
        guard let expiresAt, plan == .month else { return nil }
        let seconds = expiresAt.timeIntervalSince(Self.effectiveNow())
        guard seconds > 0 else { return 0 }
        return Int(ceil(seconds / 86_400))
    }

    // MARK: - 校驗

    /// 服務端校驗結果。`nil` 表示網絡或服務異常（調用方應保持原狀態，不要當成「無效」）。
    private struct Outcome {
        let valid: Bool
        let reason: String?
        let plan: CardKeyPlan?
        let expiresAt: Date?
        let serverNow: Date?
    }

    /// 服務端返回體。`expiresAt` / `serverNow` 保留原始字符串 ——
    /// 驗籤要用它們原樣拼進 payload，解析成 `Date` 會丟掉毫秒精度。
    private struct VerifyReply: Decodable {
        let valid: Bool
        let reason: String?
        let plan: String?
        let expiresAt: String?
        let serverNow: String?
        /// 服務端 Ed25519 簽名（base64）。過渡期允許缺失，見 `requiresSignature`。
        let sig: String?
    }

    private static func parseDate(_ text: String?) -> Date? {
        guard let text, !text.isEmpty else { return nil }
        let formatter = ISO8601DateFormatter()
        // 服務端用 toISOString()，帶毫秒；`.iso8601` 解碼策略不認毫秒，這裡手動兩試。
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let date = formatter.date(from: text) { return date }
        formatter.formatOptions = [.withInternetDateTime]
        return formatter.date(from: text)
    }

    private func verify(_ key: String) async -> Outcome? {
        // 請求與驗籤必須用同一個設備號，取一次釘住。
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

        // 429 限流、5xx 存儲異常都算「暫時失敗」，不動已有狀態
        if http.statusCode == 429 || http.statusCode >= 500 { return nil }
        guard http.statusCode == 200,
              let reply = try? JSONDecoder().decode(VerifyReply.self, from: data)
        else { return nil }

        // 簽名不對就當「不可信響應」，返回 nil（調用方保持原狀態）。
        // 這裡**不能** revoke：否則任何人返回一段垃圾都能把付費用戶踢下線。
        guard Self.signatureIsValid(reply, cardKey: key, deviceId: deviceId) else {
            return nil
        }

        // 保鮮期：擋「截一次 valid=true 反覆回放」。服務端缺席時，過渡期放行。
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

    // MARK: - 響應驗籤

    /// 重建服務端簽過的那串內容。
    ///
    /// 順序、分隔符、空值寫法三方（SCF、這裡、測試腳本）必須一字不差。
    /// 特別注意 `expiresAt` / `serverNow` 用的是**原始字符串**而不是解析後的
    /// `Date` —— 一旦格式化再簽，毫秒位一變就對不上。
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

    /// 公鑰是否已填。沒填時整段驗籤跳過 —— 寧可這版沒有防護，
    /// 也不能因為忘了填公鑰讓所有人激活失敗。
    private static var hasSigningKey: Bool {
        guard let data = Data(base64Encoded: signingPublicKeyBase64) else { return false }
        return data.count == 32
    }

    /// 驗籤。返回 false 表示響應不可信，調用方應按「暫時失敗」處理。
    private static func signatureIsValid(
        _ reply: VerifyReply,
        cardKey: String,
        deviceId: String
    ) -> Bool {
        guard hasSigningKey else { return true }

        // 過渡期：服務端還沒加簽時放行；一旦帶了 sig，就必須驗過。
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

    /// 複驗已激活的卡密是否仍然有效。
    ///
    /// 只在「已激活 + 到了複驗時間」時請求。任何失敗都直接返回、保留手上的狀態 ——
    /// 斷網、服務端抽風、返回體寫壞，都不該把已經能用的會員瞬間變成不能用。
    func refreshIfNeeded(force: Bool = false) async {
        // 未激活但有 Keychain 卡密：重裝後的第一次聯網。接回來再走正常流程 ——
        // 放在這裡，App 回到前台時也會重試，斷網重裝的人不必再重啟一次。
        if !isUnlocked {
            if let storedKey = CardKeyStore.read() {
                await restoreFromKeychain(storedKey)
            }
            return
        }

        // 本地到期不需要等網絡：先把已經過期的收回。
        if Self.hasExpired(expiresAt) {
            revoke(reason: "expired")
            return
        }

        guard !isRefreshing else { return }
        if !force, Date().timeIntervalSince(lastCheck) < Self.cacheTTL { return }
        guard let used = UserDefaults.standard.string(forKey: Self.activatedCard), !used.isEmpty else { return }

        isRefreshing = true
        defer { isRefreshing = false }

        // 只有服務端明確回答「無效」才收回；nil（網絡失敗）一律不動。
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

    /// 校驗卡密；通過則按服務端返回的檔位激活並返回 `true`。
    @discardableResult
    func activate(_ key: String) async -> Bool {
        // 服務端按大寫比對，客戶端先統一，避免用戶輸小寫被判錯
        let trimmed = key.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
        guard !trimmed.isEmpty else { return false }

        // 已是永久會員就不用再驗了：讓月卡覆蓋上去等於把永久降級，
        // 而且會白白消耗掉這條卡密的綁定名額。
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
        // 卡密另存一份進 Keychain：UserDefaults 卸載即清，重裝後靠它自動恢復。
        CardKeyStore.write(trimmed)
        lastCheck = Date()
        defaults.set(lastCheck, forKey: Self.checkStamp)
        lastFailureReason = nil
        apply(outcome)
        // apply 會在「服務端給的到期時間已過」時直接收回，這裡以最終狀態為準
        return isUnlocked
    }

    /// 把服務端結果落到本機：檔位、到期時間、時間錨點。
    private func apply(_ outcome: Outcome) {
        // 服務端沒帶檔位時按永久處理，不要留著 `.none` 讓 UI 顯示成「未激活」
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
        // 明確失效（過期、吊銷）才清 Keychain 那份；否則重裝後會把死卡密又撿回來。
        CardKeyStore.clear()

        if let reason { lastFailureReason = reason }
        onStateChanged?()
    }

    /// 到期那一刻把會員收回，不用等用戶重啟 App。
    ///
    /// 只排一次：到點觸發後 `recompute` 走 `revoke`，計時器自然清掉。
    /// 後台期間 Timer 會被掛起，回到前台時 `refreshIfNeeded` 兜底。
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
        // 上限 60 秒：本機時鐘小幅回撥時能及早重算
        // 上限一小時：後台 Timer 會被掛起，回到前台後重新校準一次就夠
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

    /// 目前可用卡密：服務端校驗模式下客戶端不持有名單，只知道自己激活的那一條。
    var activeCardKey: String? {
        guard isUnlocked else { return nil }
        return UserDefaults.standard.string(forKey: Self.activatedCard)
    }

    /// 這台裝置在卡密後台的身份（Keychain 裡的 UUID，重裝不變）。
    /// 顯示在「關於」裡，供換機、清空 Keychain 這類自動恢復接不回來的情況人工補綁。
    var deviceCode: String { Self.deviceId }
}

/// 卡密明文：與設備標識一樣存 Keychain，卸載重裝仍在。
///
/// 這是「重裝後自動恢復會員」的依據。之前它只存在 `UserDefaults`，卸載即清，
/// 而 `refreshIfNeeded` 又以「已激活」為前提 —— 兩者一疊，重裝後必得重輸卡密。
/// 沒有打開 `kSecAttrSynchronizable`：這條卡密綁的是本機設備號，跟著 iCloud
/// Keychain 跑到另一台裝置上沒有意義，也換不來恢復。
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
        // 與設備標識一致：首次解鎖後可讀，後台校驗也拿得到
        attributes[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlock
        SecItemAdd(attributes as CFDictionary, nil)
    }

    static func clear() {
        SecItemDelete(baseQuery() as CFDictionary)
    }
}

/// 設備標識：Keychain 裡的一個 UUID，卸載重裝不會變。
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
        // 首次解鎖後可讀：後台校驗也能拿到，且不會因為鎖屏失敗
        attributes[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlock
        SecItemAdd(attributes as CFDictionary, nil)
    }
}
