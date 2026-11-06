import Foundation
import SwiftUI

/// 出廠自帶的劍來主題（maintainer, 2026-11-06）。
///
/// 它是「外觀主題 › 自訂主題」裡的第一張卡，**不**在啟動時自動鋪開：使用者點它才匯入，
/// 匯入後就是一條普通的自訂主題記錄——可以選中、可以長按改名，跟自己匯入的那條走同一條
/// 路（`YuejingThemeImporter` → `QiThemeImportService.apply`），不另寫一份落地邏輯。
///
/// 素材是 `Resources/jianlai-theme.zip`：原包 17MB，這裡按本 App 真正會讀的東西裁到
/// 2MB——頁面背景、啟動圖、閱讀紙、五個底部圖示、頭像，其餘（詳情背板、空狀態、
/// 設定二級頁背景、章節題簽）本 App 沒有對應的位置，丟掉。
///
/// 主題屬於「尊享會員」權益，跟其他自訂主題一樣：沒開通時卡片帶鎖，選中也會回落到
/// 「默認」。鎖版只鎖「使用」，不鎖「匯入」——所以卡片上的鎖由呼叫方判斷。
@MainActor
enum BuiltInAppearanceTheme {
    /// 卡片上的名字。讀本地化：同一張卡在繁體、日文、韓文下各有各的叫法。
    static var displayName: String { localized("劍來") }

    /// 還沒匯入時卡片用的 id。它不對應任何存下來的記錄，只讓縮圖有個身分。
    static let placeholderID = "builtin_jianlai"

    private static let packName = "jianlai-theme"
    private static let installedIDKey = "yd_builtin_jianlai_theme_id"
    /// 這個包在記錄裡可能叫的名字：`manifest` 的 name，加上它被去重後的樣子。
    private static let packNames: Set<String> = ["剑来", "劍來"]

    /// 匯入後那條自訂主題記錄的 id，沒有就是 nil。
    ///
    /// 記錄被使用者刪掉時 id 會失效，這裡一併當作「沒匯入」，下次點卡片重新匯入。
    static var installedThemeID: String? {
        let defaults = UserDefaults.standard
        let settings = GlobalSettings.shared
        if let id = defaults.string(forKey: installedIDKey),
           settings.customAppearanceThemes.contains(where: { $0.id == id }) {
            return id
        }
        // 舊版啟動時自動鋪過一次、只寫了旗標沒記 id；或者使用者自己匯入過同一個包。
        // 認領那條記錄，免得再匯入一份一模一樣的。`originalExtras` 只有匯入包才有。
        if let adopted = settings.customAppearanceThemes.first(where: {
            packNames.contains($0.name) && $0.originalExtras != nil
        }) {
            defaults.set(adopted.id, forKey: installedIDKey)
            return adopted.id
        }
        return nil
    }

    static var isInstalled: Bool { installedThemeID != nil }

    /// 匯入一次，回傳落地後那條記錄的 id。已經匯入過就直接回傳，不重複寫。
    @discardableResult
    static func install() async -> String? {
        if let id = installedThemeID { return id }

        guard let url = Bundle.main.url(forResource: packName, withExtension: "zip"),
              let data = try? Data(contentsOf: url)
        else {
            AppLogger.error("⟐ built-in jianlai theme: pack missing from bundle")
            return nil
        }

        do {
            let theme = try await YuejingThemeImporter.parse(data)
            let outcome = try await QiThemeImportService.apply(theme)
            guard let id = outcome.theme?.id else {
                AppLogger.error("⟐ built-in jianlai theme: import produced no theme")
                return nil
            }
            UserDefaults.standard.set(id, forKey: installedIDKey)
            return id
        } catch {
            AppLogger.error("⟐ built-in jianlai theme failed", error: error)
            return nil
        }
    }

    /// 卡片縮圖用的調色板，取自這個包的 `manifest`，跟匯入後真正的樣子一致。
    /// 縮圖優先顯示 `assetPreviewName` 那張圖，這裡的顏色只負責外框與文字。
    static func previewPreset(for scheme: ColorScheme) -> AppearanceThemePreset {
        let dark = scheme == .dark
        var preset = AppearanceThemePreset(
            id: installedThemeID ?? placeholderID,
            nameKey: "",
            displayName: displayName,
            background: AppearanceThemePreset.hex(dark ? 0x18181A : 0xF0EBDD),
            text: AppearanceThemePreset.hex(dark ? 0xD6D2C6 : 0x2A2A26),
            bar: AppearanceThemePreset.hex(dark ? 0x242428 : 0xF8F4E8),
            accent: AppearanceThemePreset.hex(dark ? 0xC44B44 : 0x9E2B25),
            dialogue: AppearanceThemePreset.hex(dark ? 0x2E2E33 : 0xE8DFC8),
            previewBackground: AppearanceThemePreset.hex(dark ? 0x242428 : 0xF8F4E8),
            relativePreviewImagePath: nil,
            imagePaths: [],
            requiresPro: true,
            isImagePreset: false,
            isCustom: true
        )
        preset.assetPreviewName = "JianlaiThemeCard"
        preset.darkAssetPreviewName = "JianlaiThemeCardDark"
        return preset
    }
}
