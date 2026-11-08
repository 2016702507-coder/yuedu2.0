import Foundation
import UIKit

/// 閱境（yuejing）的 `*.theme` / `.zip` 外觀包。
///
/// 這個包的 manifest 跟 QiReader 的不是同一套，所以單獨解析，最後仍然交出
/// `QiThemeImport`，走 `QiThemeImportService.apply` 那一條既有的落地通道——
/// 不為第三個格式再寫一份「寫入設定」的邏輯。
///
/// 範圍是刻意收窄的：只轉這個 App **本來就有位置放**的東西——調色板、頁面背景、
/// 底部圖示、閱讀頁的紙與字色、章節標題。包裡那套自己的頁面結構（頭像、簽名、
/// 統計卡、頁首裝飾、書詳背板）一律丟掉，因為那些不是換皮，是往頁面裡加元件。
enum YuejingThemeImporter {
    /// 與 `QiThemeImporter` 同一個上限：最大的真實包展開約 33MB，幾乎全是一支字型。
    static let maximumExpandedBytes = 100 * 1_024 * 1_024

    // MARK: - Manifest

    private struct Manifest: Decodable {
        struct PaletteEntry: Decodable {
            var backgroundPrimary: String?
            var surfacePrimary: String?
            var surfaceSecondary: String?
            var brandAccent: String?
            var textPrimary: String?
            var textSecondary: String?
            var borderSubtle: String?
            var surfaceEdge: String?
        }

        struct Palette: Decodable {
            var light: PaletteEntry?
            var dark: PaletteEntry?
        }

        struct Artwork: Decodable {
            var path: String?
            var darkPath: String?
            var opacity: Double?
            var darkOpacity: Double?
        }

        struct Artworks: Decodable {
            var launchImage: Artwork?
            var appBackground: Artwork?
            var homeBackground: Artwork?
            var shelfBackground: Artwork?
            var sourcesBackground: Artwork?
            var profileBackground: Artwork?
            var settingsBackground: Artwork?
            var readerPaper: Artwork?
        }

        struct TabIconAsset: Decodable {
            var path: String?
            var darkPath: String?
        }

        struct Shape: Decodable {
            var cardRadius: Double?
            var cardBorderWidth: Double?
            var cardOpacity: Double?
        }

        struct Typography: Decodable {
            var titleFontName: String?
        }

        struct InterfaceStyle: Decodable {
            var artwork: Artworks?
            var tabIconAssets: [String: TabIconAsset]?
            var shape: Shape?
            var typography: Typography?
        }

        struct ReaderPreferences: Decodable {
            var dayPaperColor: String?
            var dayTextColor: String?
            var nightPaperColor: String?
            var nightTextColor: String?
        }

        struct ReadingTheme: Decodable {
            var name: String?
            var preferences: ReaderPreferences?
        }

        struct ChapterHeadingStyle: Decodable {
            var alignment: String?
            var layout: String?
            var size: Double?
            var eyebrowSize: Double?
            var titleSpacing: Double?
            var top: Double?
            var bottom: Double?
            var hidden: Bool?
        }

        struct ChapterHeading: Decodable {
            var name: String?
            var style: ChapterHeadingStyle?
        }

        struct Reader: Decodable {
            var readingTheme: ReadingTheme?
            var chapterHeading: ChapterHeading?
        }

        var format: String?
        var formatVersion: Int?
        var name: String?
        var palette: Palette?
        var ui: InterfaceStyle?
        var reader: Reader?

        private enum CodingKeys: String, CodingKey {
            case format, formatVersion, name, palette, reader
            case ui = "interface"
        }
    }

    // MARK: - Detection

    static func hasYuejingExtension(_ url: URL) -> Bool {
        let ext = url.pathExtension.lowercased()
        return ext == "zip" || ext == "theme"
    }

    // MARK: - Parsing

    static func parse(_ archiveData: Data) async throws -> QiThemeImport {
        guard archiveData.count <= maximumExpandedBytes else {
            throw QiThemeImportError.expandedDataTooLarge(archiveData.count)
        }

        let staging = FileManager.default.temporaryDirectory
            .appendingPathComponent("yuejing-import-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: staging) }
        try FileManager.default.createDirectory(at: staging, withIntermediateDirectories: true)

        let archiveURL = staging.appendingPathComponent("source.zip", isDirectory: false)
        try archiveData.write(to: archiveURL, options: .atomic)

        let contentRoot = staging.appendingPathComponent("contents", isDirectory: true)
        let paths = try await QiThemeImporter.extractArchive(at: archiveURL, into: contentRoot)

        // 這個包沒有 QiReader 那層 UUID 目錄，manifest 就在根的下一層（也可能就在根）。
        guard let manifestPath = paths
            .filter({ $0.lowercased().hasSuffix("manifest.json") })
            .min(by: { $0.split(separator: "/").count < $1.split(separator: "/").count }),
              let manifestData = try? Data(contentsOf: contentRoot.appendingPathComponent(manifestPath)),
              let manifest = try? JSONDecoder().decode(Manifest.self, from: manifestData),
              manifest.format == "yuejing.theme"
        else {
            throw QiThemeImportError.notAYuejingTheme
        }

        let manifestDirectory = (manifestPath as NSString).deletingLastPathComponent
        let packRoot = manifestDirectory.isEmpty
            ? contentRoot
            : contentRoot.appendingPathComponent(manifestDirectory, isDirectory: true)

        return translate(manifest, root: packRoot)
    }

    // MARK: - Translation

    private static func translate(_ manifest: Manifest, root: URL) -> QiThemeImport {
        var notes: [String] = []
        let rawName = manifest.name?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let name = rawName.isEmpty ? localized("阅境外观包") : rawName

        let light = manifest.palette?.light
        let dark = manifest.palette?.dark

        // ── 亮色 ──
        let lightBackground = rgb(light?.backgroundPrimary) ?? 0xF0EBDD
        let lightSurface = rgb(light?.surfacePrimary) ?? lightBackground
        let lightSecondarySurface = rgb(light?.surfaceSecondary) ?? mix(lightSurface, lightBackground, 0.5)
        let lightText = rgb(light?.textPrimary) ?? 0x2A2A26
        let lightTextSecondary = rgb(light?.textSecondary) ?? mix(lightText, lightBackground, 0.45)
        let lightTextTertiary = mix(lightTextSecondary, lightBackground, 0.45)
        let lightAccent = rgb(light?.brandAccent) ?? 0x9E2B25
        let lightBar = rgb(light?.surfaceEdge) ?? lightSurface
        let lightBorder = rgb(light?.borderSubtle) ?? mix(lightSurface, lightText, 0.12)

        // ── 暗色 ──
        let darkBackground = rgb(dark?.backgroundPrimary) ?? 0x18181A
        let darkSurface = rgb(dark?.surfacePrimary) ?? 0x242428
        let darkText = rgb(dark?.textPrimary) ?? 0xD6D2C6
        let darkTextSecondary = rgb(dark?.textSecondary) ?? mix(darkText, darkBackground, 0.42)
        let darkTextTertiary = mix(darkTextSecondary, darkBackground, 0.42)
        let darkAccent = rgb(dark?.brandAccent) ?? 0xC44B44
        let darkBar = rgb(dark?.surfaceEdge) ?? darkSurface
        let darkBorder = rgb(dark?.borderSubtle) ?? mix(darkSurface, darkText, 0.16)

        // ── 頁面背景 ──
        // 只鋪這個 App 真正有的頁面。「我的」用 profile 的圖，因為本 App 的我的頁就是
        // 設定頁；settings 那張是更深一層的設定二級頁，不用。
        let art = manifest.ui?.artwork
        let scopeSources: [(AppearancePageBackgroundScope, Manifest.Artwork?, Double)] = [
            (.global, art?.homeBackground, 0.62),
            (.bookshelf, art?.shelfBackground, 0.58),
            (.explore, art?.sourcesBackground, 0.55),
            (.settings, art?.profileBackground, 0.45),
            (.search, art?.appBackground, 0.45),
        ]

        var backgrounds: [String: AppearanceThemeExportFile.PageBackgroundPayload] = [:]
        for (scope, artwork, opacity) in scopeSources {
            guard let payload = backgroundPayload(
                artwork,
                root: root,
                lightColor: lightBackground,
                darkColor: darkBackground,
                lightOpacity: opacity
            ) else { continue }
            backgrounds[scope.rawValue] = payload
        }

        // ── 底部圖示 ──
        var tabIcons: [QiThemeImport.TabIconImport] = []
        var darkTabIcons: [QiThemeImport.TabIconImport] = []
        for (label, asset) in manifest.ui?.tabIconAssets ?? [:] {
            guard let tab = tabID(for: label) else {
                notes.append(String(format: localized("图示「%@」在本 App 没有对应的分页，已略过。"), label))
                continue
            }
            if let image = imageFile(asset.path, root: root) {
                tabIcons.append(QiThemeImport.TabIconImport(tabID: tab, image: image))
            }
            if let image = imageFile(asset.darkPath, root: root) {
                darkTabIcons.append(QiThemeImport.TabIconImport(tabID: tab, image: image))
            }
        }

        // ── 卡片：只取「填色 + 描邊」，圓角與陰影由 App 自己的元件決定 ──
        let shape = manifest.ui?.shape
        let borderWidth = min(max(shape?.cardBorderWidth ?? 0.8, 0), 4)
        let fillOpacity = min(max(shape?.cardOpacity ?? 0.96, 0.3), 1)
        let cardBackground = AppearanceCardBackground(
            isEnabled: true,
            light: AppearanceCardBackgroundLayer(
                fillHex: lightSurface,
                fillOpacity: fillOpacity,
                borderHex: lightBorder,
                borderWidth: borderWidth
            ),
            dark: AppearanceCardBackgroundLayer(
                fillHex: darkSurface,
                fillOpacity: fillOpacity,
                borderHex: darkBorder,
                borderWidth: borderWidth
            )
        )

        // ── 閱讀頁：紙與字色 ──
        let preferences = manifest.reader?.readingTheme?.preferences
        let dayPaper = rgb(preferences?.dayPaperColor) ?? lightBackground
        let dayText = rgb(preferences?.dayTextColor) ?? lightText
        let nightPaper = rgb(preferences?.nightPaperColor) ?? darkBackground
        let nightText = rgb(preferences?.nightTextColor) ?? darkText
        let paper = art?.readerPaper.flatMap { imageFile($0.path, root: root) }
        let darkPaper = art?.readerPaper.flatMap { imageFile($0.darkPath, root: root) }

        // ── 章節標題 ──
        var titleStyle = ChapterTitleStyle.default
        if let style = manifest.reader?.chapterHeading?.style {
            titleStyle.visible = !(style.hidden ?? false)
            titleStyle.size = CGFloat(style.size ?? 28)
            titleStyle.topSpacing = CGFloat(style.top ?? 12)
            titleStyle.bottomSpacing = CGFloat(style.bottom ?? 28)
            titleStyle.alignment = chapterTitleAlignment(style.alignment)
            // 「stacked」= 章號一行、章名一行，正是這套主題的排法。
            titleStyle.splitEnabled = (style.layout ?? "stacked") == "stacked"
            titleStyle.numberRelativeSize = 0.55
            titleStyle.weight = .bold
            titleStyle.followsBodyFont = true
        }

        // ── 字型：包裡沒有字型檔，只能提示 ──
        // 不查系統是否已安裝這支字型：`UIFont(name:size:)` 在少數系統版本上要求主執行緒，
        // 而這裡是解析階段。有沒有裝，使用者一導入就看得出來。
        if let fontName = manifest.ui?.typography?.titleFontName, !fontName.isEmpty {
            notes.append(String(format: localized("主题指定了字型「%@」，但外观包里没有附字型档，已沿用目前的字型。"), fontName))
        }

        let themeFile = AppearanceThemeExportFile(
            format: AppearanceThemeExportFile.formatIdentifier,
            version: 1,
            name: name,
            backgroundHex: lightBackground,
            textHex: lightText,
            barHex: lightBar,
            accentHex: lightAccent,
            dialogueHex: lightSecondarySurface,
            pageBackgrounds: backgrounds.isEmpty ? nil : backgrounds,
            darkBackgroundHex: darkBackground,
            darkTextHex: darkText,
            darkBarHex: darkBar,
            darkAccentHex: darkAccent,
            darkDialogueHex: darkSurface,
            textPrimaryHex: lightText,
            textSecondaryHex: lightTextSecondary,
            textTertiaryHex: lightTextTertiary,
            darkTextPrimaryHex: darkText,
            darkTextSecondaryHex: darkTextSecondary,
            darkTextTertiaryHex: darkTextTertiary
        )

        var result = QiThemeImport(name: name, themeFile: themeFile)
        result.pageBackgrounds = backgrounds
        result.tabIcons = tabIcons
        result.darkTabIcons = darkTabIcons
        result.tabIconSize = 26
        result.hidesTabLabels = false
        result.launchImage = art?.launchImage.flatMap { imageFile($0.path, root: root) }
        result.darkLaunchImage = art?.launchImage.flatMap { imageFile($0.darkPath, root: root) }
        result.launchEnabled = result.launchImage != nil
        // 卡片半透明是為了讓頁面背景透得上來；這是 App 本來就有的外觀開關，不是新元件。
        result.effects.frostedGlass = true
        result.effects.glassTransparency = 0.35
        result.bookshelf.coverCornerRadius = min(max(shape?.cardRadius ?? 10, 0), 20)
        result.chapterTitleStyle = titleStyle
        result.readerBackground = paper
        result.darkReaderBackground = darkPaper
        result.readerBackgroundColorHex = paper == nil ? dayPaper : nil
        result.readerTextColorHex = paper == nil ? nil : dayText
        result.darkReaderBackgroundColorHex = darkPaper == nil ? nightPaper : nil
        result.darkReaderTextColorHex = darkPaper == nil ? nil : nightText
        result.cardBackground = cardBackground
        result.notes = notes
        return result
    }

    // MARK: - Pieces

    /// 包裡的分頁名稱 → 本 App 的 `RootTabItem` raw value。用字串而不是引用型別，
    /// 因為這個檔案在 Core 模組裡，看不到 app target 的 `RootTabItem`。
    private static func tabID(for label: String) -> String? {
        switch label {
        case "首页", "首页": return "library"
        case "书架", "书架": return "bookshelf"
        case "书源", "书源": return "explore"
        case "我的", "设置", "设置": return "settings"
        case "搜索", "搜寻": return "search"
        default: return nil
        }
    }

    private static func chapterTitleAlignment(_ raw: String?) -> ChapterTitleAlignment {
        switch raw {
        case "center": return .center
        case "right": return .right
        default: return .left
        }
    }

    private static func imageFile(_ path: String?, root: URL) -> QiThemeImport.ImageFile? {
        guard let path, !path.isEmpty else { return nil }
        let url = root.appendingPathComponent(path)
        guard let data = try? Data(contentsOf: url) else { return nil }
        return QiThemeImport.ImageFile(data: data, fileName: (path as NSString).lastPathComponent)
    }

    private static func backgroundPayload(
        _ artwork: Manifest.Artwork?,
        root: URL,
        lightColor: UInt32,
        darkColor: UInt32,
        lightOpacity: Double
    ) -> AppearanceThemeExportFile.PageBackgroundPayload? {
        guard let artwork else { return nil }
        let light = imageFile(artwork.path, root: root)
        let dark = imageFile(artwork.darkPath, root: root)
        guard light != nil || dark != nil else { return nil }

        var payload = AppearanceThemeExportFile.PageBackgroundPayload()
        payload.lightPrimaryHex = lightColor
        payload.lightSecondaryHex = lightColor
        payload.darkPrimaryHex = darkColor
        payload.darkSecondaryHex = darkColor
        if let light {
            let ext = (light.fileName as NSString).pathExtension
            payload.lightImage = AppearanceThemeExportFile.ImagePayload(
                fileExtension: ext.isEmpty ? "jpg" : ext,
                base64: light.data.base64EncodedString()
            )
            payload.lightImageOpacity = lightOpacity
        }
        if let dark {
            let ext = (dark.fileName as NSString).pathExtension
            payload.darkImage = AppearanceThemeExportFile.ImagePayload(
                fileExtension: ext.isEmpty ? "jpg" : ext,
                base64: dark.data.base64EncodedString()
            )
            payload.darkImageOpacity = max(lightOpacity, 0.55)
        }
        return payload
    }

    // MARK: - Colour

    /// `#F0EBDD` / `#9E2B2544` / `F0EBDD` → `0xF0EBDD`.
    private static func rgb(_ raw: String?) -> UInt32? {
        guard var text = raw?.trimmingCharacters(in: .whitespacesAndNewlines), !text.isEmpty else {
            return nil
        }
        if text.hasPrefix("#") { text.removeFirst() }
        guard text.count >= 6 else { return nil }
        return UInt32(text.prefix(6), radix: 16)
    }

    /// 把 `from` 往 `to` 混 `amount`（0 = 全 from，1 = 全 to）。
    private static func mix(_ from: UInt32, _ to: UInt32, _ amount: Double) -> UInt32 {
        let t = min(max(amount, 0), 1)
        func channel(_ value: UInt32, _ shift: UInt32) -> Double {
            Double((value >> shift) & 0xFF)
        }
        func blended(_ shift: UInt32) -> UInt32 {
            let value = channel(from, shift) * (1 - t) + channel(to, shift) * t
            return UInt32(min(max(value.rounded(), 0), 255)) << shift
        }
        return blended(16) | blended(8) | blended(0)
    }
}
