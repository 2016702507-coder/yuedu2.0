import Foundation
import Observation

/// 段评与互动样式：把「孤岛 / Cay」那套按区域自订 CSS 的做法搬进阅读器。
///
/// Cay 的段评、本章说、作者说、热评是原生列表，配一套自研 CSS 引擎；阅读器的
/// 段评面板是书源网页（WKWebView），本章说 / 作者说 / 神评论卡片是 SVG 模板。
/// 这里不复制它的引擎，而是保留它的**区域划分与语义选择器**（.user / .text /
/// .quote / .label / .note …）、内置示例样式和多套模板切换；写好的 CSS 经
/// `ReviewPanelCSSBridge` 降级成浏览器 CSS 后注入段评网页。
enum ReviewPanelCSSArea: String, Codable, CaseIterable, Identifiable, Sendable {
    /// 段评面板整体：底色、字级、字体、行距、卡片间距、圆角、面板高度。
    case panel
    /// 点开段评后的评论列表：原文、头像、用户名、正文、时间、点赞、地点。
    case comment
    /// 段落后的热评 / 神评论卡片与标签。
    case hot
    /// 章末本章说与作者的话卡片。
    case chapterNote

    var id: String { rawValue }

    var title: String {
        switch self {
        case .panel: return "段评面板"
        case .comment: return "评论列表"
        case .hot: return "热评 / 神评论"
        case .chapterNote: return "本章说 / 作者说"
        }
    }

    var systemImage: String {
        switch self {
        case .panel: return "rectangle.bottomthird.inset.filled"
        case .comment: return "bubble.left.and.bubble.right"
        case .hot: return "flame"
        case .chapterNote: return "text.bubble"
        }
    }

    var summary: String {
        switch self {
        case .panel: return "面板底色、透明度、字级字体、行距、卡片间距与圆角。"
        case .comment: return "被评论原文、头像、用户名、正文、时间、点赞与地点。"
        case .hot: return "热评卡片、标签文字、用户名与行数限制。"
        case .chapterNote: return "本章说标题、评论预览、作者的话标签与正文。"
        }
    }

    /// Cay 各区域「填入示例」的原味 CSS（从 Cay 0.2.2 内置示例扒出，未改动）。
    /// 供编辑页「填入孤岛示例」使用；注入时会由适配层降级成浏览器 CSS。
    var cayExample: String {
        switch self {
        case .panel:
            return """
            /* 段评面板整体 */
            font-size: 15px;
            color: #393B45;
            background: rgba(250, 248, 243, 0.92);
            border-radius: 16px;
            padding: 10px 14px;
            line-height: 1.6;
            @dark {
                color: #D6D3D8;
                background: rgba(32, 31, 34, 0.92);
            }
            """
        case .comment:
            return """
            /* 评论：纸色卡片与蓝色用户名 */
            background: #F2F2F2;
            border-radius: 10px;
            padding: 10px;
            .text { font-size: 14px; color: #555555; }
            .user { color: #3A7BD5; font-weight: 600; }
            .time { font-size: 11px; opacity: 0.7; }
            .quote { background: rgba(0, 0, 0, 0.05); border-radius: 10px; }
            @dark {
                background: #27221D;
                color: #C8BAA5;
                .user { color: #C99C63; }
            }
            """
        case .hot:
            return """
            /* 热评：橙色神评标签 + 玻璃卡片 */
            font-size: 15px;
            color: #8A5A2B;
            background: glass;
            border-radius: 12px;
            padding: 8px 12px;
            line-clamp: 3;
            .label {
                content: "神评";
                background: #F5A623;
                color: white;
                padding: 0 6px;
                border-radius: 6px;
            }
            .user { color: #B07A3B; font-weight: bold; }
            """
        case .chapterNote:
            return """
            /* 本章说 / 作者说：纸色卡片与作者的话 */
            background: #F3EAD6;
            border: 0.5px #D8C9A8;
            border-radius: 16px;
            padding: 14px;
            .header { content: "本章热议"; font-size: 16px; color: #8A5A2B; }
            .more { color: #B07A3B; }
            .user { color: #9C8F78; }
            .text { font-size: 14px; line-height: 1.5; line-clamp: 2; }
            .note { background: glass; }
            .note-label { content: "作者有话说"; }
            @dark {
                background: #27221D;
                color: #C8BAA5;
                .header { color: #C99C63; }
            }
            """
        }
    }
}

/// 一套段评样式：四个区域各一份 CSS 文本。内置模板不可编辑，可复制后修改。
struct ReviewPanelStyleTemplate: Codable, Equatable, Identifiable, Sendable {
    var id: UUID
    var name: String
    var isBuiltin: Bool
    var css: [ReviewPanelCSSArea: String]
    var updatedAt: Date?

    init(
        id: UUID = UUID(),
        name: String,
        isBuiltin: Bool = false,
        css: [ReviewPanelCSSArea: String] = [:],
        updatedAt: Date? = nil
    ) {
        self.id = id
        self.name = name
        self.isBuiltin = isBuiltin
        self.css = css
        self.updatedAt = updatedAt
    }

    func css(for area: ReviewPanelCSSArea) -> String {
        css[area] ?? ""
    }

    /// 该模板是否有任何非空 CSS。
    var isEmpty: Bool {
        ReviewPanelCSSArea.allCases.allSatisfy { css(for: $0).trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
    }

    /// 导入 / 导出用的 JSON 包格式。
    struct PackageFile: Codable {
        static let formatIdentifier = "yuedu.reviewPanelStyle"
        var format: String
        var version: Int
        var name: String
        var panel: String
        var comment: String
        var hot: String
        var chapterNote: String

        init(_ template: ReviewPanelStyleTemplate) {
            format = Self.formatIdentifier
            version = 1
            name = template.name
            panel = template.css(for: .panel)
            comment = template.css(for: .comment)
            hot = template.css(for: .hot)
            chapterNote = template.css(for: .chapterNote)
        }

        func makeTemplate(id: UUID = UUID()) -> ReviewPanelStyleTemplate {
            ReviewPanelStyleTemplate(
                id: id,
                name: name,
                isBuiltin: false,
                css: [
                    .panel: panel,
                    .comment: comment,
                    .hot: hot,
                    .chapterNote: chapterNote
                ]
            )
        }

        static func decode(_ data: Data) -> PackageFile? {
            guard let package = try? JSONDecoder().decode(Self.self, from: data),
                  package.format == formatIdentifier else { return nil }
            return package
        }
    }
}

enum ReviewPanelStyleLibrary {
    /// 内置模板：CSS 直接取自 Cay 0.2.2 的四段「填入示例」，按区域组合。
    /// 全部用 Cay 的语义选择器书写，注入时由 `ReviewPanelCSSBridge` 降级。
    static let builtins: [ReviewPanelStyleTemplate] = [
        ReviewPanelStyleTemplate(
            id: UUID(uuidString: "A1000000-0000-0000-0000-000000000001")!,
            name: "孤岛 · 神评橙",
            isBuiltin: true,
            css: [
                .panel: """
                font-size: 15px;
                color: #393B45;
                background: rgba(250, 248, 243, 0.94);
                border-radius: 16px;
                padding: 8px 12px;
                @dark { color: #D6D3D8; background: rgba(32, 31, 34, 0.94); }
                """,
                .comment: """
                background: #F2F2F2;
                border-radius: 10px;
                padding: 10px;
                .text { font-size: 14px; color: #555555; }
                .user { color: #3A7BD5; font-weight: 600; }
                .time { font-size: 11px; opacity: 0.7; }
                .quote { background: rgba(0, 0, 0, 0.05); border-radius: 10px; }
                @dark { background: #27221D; color: #C8BAA5; .user { color: #C99C63; } }
                """,
                .hot: ReviewPanelCSSArea.hot.cayExample,
                .chapterNote: ""
            ]
        ),
        ReviewPanelStyleTemplate(
            id: UUID(uuidString: "A1000000-0000-0000-0000-000000000002")!,
            name: "孤岛 · 纸色本章说",
            isBuiltin: true,
            css: [
                .panel: """
                font-size: 15px;
                color: #8A5A2B;
                background: rgba(243, 234, 214, 0.94);
                border-radius: 16px;
                padding: 8px 12px;
                @dark { color: #C8BAA5; background: rgba(39, 34, 29, 0.94); }
                """,
                .comment: ReviewPanelCSSArea.comment.cayExample,
                .hot: """
                background: #F0E4CA;
                border: 1px solid #D7C5A4;
                border-radius: 10px;
                padding: 8px 12px;
                line-clamp: 3;
                .label { content: "书友说"; background: #AD7440; color: white; }
                .user { color: #7B5835; font-weight: bold; }
                @dark { background: #27221D; color: #C8BAA5; .user { color: #C99C63; } }
                """,
                .chapterNote: ReviewPanelCSSArea.chapterNote.cayExample
            ]
        ),
        ReviewPanelStyleTemplate(
            id: UUID(uuidString: "A1000000-0000-0000-0000-000000000003")!,
            name: "孤岛 · 清爽评论",
            isBuiltin: true,
            css: [
                .panel: """
                font-size: 15px;
                color: #393B45;
                background: rgba(255, 255, 255, 0.92);
                border-radius: 14px;
                padding: 8px 12px;
                @dark { color: #D6D3D8; background: rgba(28, 28, 30, 0.92); }
                """,
                .comment: """
                .quote { background: #88888818; padding: 12px; line-clamp: 4; }
                .avatar { width: 30px; border-radius: 6px; }
                .user { font-weight: 600; color: #3A7BD5; }
                .likes-icon { display: none; }
                .location { opacity: 0.5; }
                .text { line-clamp: 8; font-size: 14px; }
                .time { font-size: 11px; opacity: 0.7; }
                """,
                .hot: """
                font-size: 15px;
                background: glass;
                border-radius: 14px;
                line-clamp: 3;
                .label { content: "神评"; background: #F5A623; color: white; padding: 0 6px; border-radius: 6px; }
                .user { color: #B07A3B; font-weight: bold; }
                """,
                .chapterNote: """
                .header { content: "本章热议"; font-size: 16px; color: #8A5A2B; }
                .more { color: #B07A3B; }
                .user { color: #9C8F78; }
                .text { font-size: 14px; line-height: 1.5; line-clamp: 2; }
                .note { background: glass; }
                .note-label { content: "作者有话说"; }
                """
            ]
        ),
        ReviewPanelStyleTemplate(
            id: UUID(uuidString: "A1000000-0000-0000-0000-000000000004")!,
            name: "简洁留白",
            isBuiltin: true,
            css: [
                .panel: """
                font-size: 15px;
                color: #4A4A4A;
                background: transparent;
                .card { border: none; border-bottom: 0.5px solid rgba(128, 128, 128, 0.25); border-radius: 0; }
                @dark { color: #C9C9CE; }
                """,
                .comment: """
                .avatar { display: none; }
                .likes-icon, .reply-icon { display: none; }
                .location { display: none; }
                .quote { background: rgba(128, 128, 128, 0.10); border-radius: 8px; padding: 8px 10px; }
                .text { font-size: 14px; line-height: 1.6; }
                .time { font-size: 11px; opacity: 0.6; }
                .user { font-weight: 600; }
                """,
                .hot: """
                background: transparent;
                border: none;
                border-top: 0.5px solid rgba(128, 128, 128, 0.25);
                border-radius: 0;
                .label { content: "精选"; background: transparent; color: #B07A3B; }
                .user { color: #B07A3B; }
                """,
                .chapterNote: """
                background: transparent;
                border: none;
                border-top: 0.5px solid rgba(128, 128, 128, 0.25);
                .header { content: "本章说"; color: #8A5A2B; }
                .note-label { content: "作者说"; }
                """
            ]
        )
    ]

    static func decode(_ data: Data) -> [ReviewPanelStyleTemplate] {
        guard let items = try? JSONDecoder().decode([ReviewPanelStyleTemplate].self, from: data) else { return [] }
        var seen = Set<UUID>()
        return items.filter { seen.insert($0.id).inserted }
    }

    static func upserting(_ template: ReviewPanelStyleTemplate, into templates: [ReviewPanelStyleTemplate]) -> [ReviewPanelStyleTemplate] {
        var stamped = template
        stamped.isBuiltin = false
        stamped.updatedAt = Date()
        guard let index = templates.firstIndex(where: { $0.id == stamped.id }) else {
            return templates + [stamped]
        }
        var updated = templates
        updated[index] = stamped
        return updated
    }

    static func deleting(id: UUID, from templates: [ReviewPanelStyleTemplate]) -> [ReviewPanelStyleTemplate] {
        templates.filter { $0.id != id }
    }
}

/// 段评样式的存储与当前选择。独立于 `GlobalSettings`，避免动到它的 iCloud 合并时钟；
/// 模板库与选择都存本机 UserDefaults，随段评面板打开时读取。
/// 主线程隔离：UI 状态只从 SwiftUI 视图读写，也让 `static let shared` 在
/// Swift 6 严格并发下成为 actor-isolated 而非 non-Sendable 的全局可变状态。
@MainActor
@Observable
final class ReviewPanelStyleStore {
    static let shared = ReviewPanelStyleStore()

    private static let templatesKey = "yd_review_panel_style_templates"
    private static let selectedKey = "yd_review_panel_style_selected"
    private static let enabledKey = "yd_review_panel_style_enabled"

    /// init 期间为 true：属性观察器不落盘，避免用默认值覆盖已存的用户样式。
    private var isLoading = true

    var customTemplates: [ReviewPanelStyleTemplate] {
        didSet { save() }
    }
    /// nil 表示未选模板；内置模板的 id 也存这里。
    var selectedTemplateID: UUID? {
        didSet { save() }
    }
    var isEnabled: Bool {
        didSet { save() }
    }

    var allTemplates: [ReviewPanelStyleTemplate] {
        ReviewPanelStyleLibrary.builtins + customTemplates
    }

    var selectedTemplate: ReviewPanelStyleTemplate? {
        guard isEnabled else { return nil }
        // 选中的模板若已被删除，回退到内置首套：所有点开评论的面板始终有样式可套。
        if let hit = allTemplates.first(where: { $0.id == selectedTemplateID }) {
            return hit
        }
        return ReviewPanelStyleLibrary.builtins.first
    }

    private init() {
        let defaults = UserDefaults.standard
        if let data = defaults.data(forKey: Self.templatesKey) {
            customTemplates = ReviewPanelStyleLibrary.decode(data)
        } else {
            customTemplates = []
        }
        selectedTemplateID = defaults.string(forKey: Self.selectedKey).flatMap { UUID(uuidString: $0) }
        // 首次启动即套用孤岛样式：所有点开评论后弹出的网页面板共用一个视图，
        // 这里默认启用并选中内置首套，装包后无需手动开开关。用户一旦手动改过就尊重存档。
        let neverConfigured = defaults.object(forKey: Self.enabledKey) == nil
            && defaults.object(forKey: Self.selectedKey) == nil
        isEnabled = defaults.object(forKey: Self.enabledKey) as? Bool ?? true
        if neverConfigured, selectedTemplateID == nil {
            selectedTemplateID = ReviewPanelStyleLibrary.builtins.first?.id
        }
        isLoading = false
    }

    private func save() {
        guard !isLoading else { return }
        let defaults = UserDefaults.standard
        do {
            defaults.set(try JSONEncoder().encode(customTemplates), forKey: Self.templatesKey)
        } catch {
            defaults.removeObject(forKey: Self.templatesKey)
        }
        defaults.set(selectedTemplateID?.uuidString, forKey: Self.selectedKey)
        defaults.set(isEnabled, forKey: Self.enabledKey)
    }

    // MARK: - 操作

    func select(id: UUID?) {
        selectedTemplateID = id
        isEnabled = true
    }

    func upsert(_ template: ReviewPanelStyleTemplate) {
        customTemplates = ReviewPanelStyleLibrary.upserting(template, into: customTemplates)
        select(id: template.id)
    }

    func delete(id: UUID) {
        customTemplates = ReviewPanelStyleLibrary.deleting(id: id, from: customTemplates)
        if selectedTemplateID == id { selectedTemplateID = nil }
    }

    /// 复制一份（内置或自定义）成可编辑的自定义模板。
    func duplicate(_ template: ReviewPanelStyleTemplate) {
        var copy = template
        copy.id = UUID()
        copy.isBuiltin = false
        copy.name = template.name + " 副本"
        copy.updatedAt = Date()
        customTemplates = ReviewPanelStyleLibrary.upserting(copy, into: customTemplates)
        select(id: copy.id)
    }

    func rename(id: UUID, name: String) {
        guard let index = customTemplates.firstIndex(where: { $0.id == id }) else { return }
        var updated = customTemplates
        updated[index].name = name
        customTemplates = updated
    }

    func setCSS(_ text: String, for area: ReviewPanelCSSArea, on templateID: UUID) {
        guard let index = customTemplates.firstIndex(where: { $0.id == templateID }) else { return }
        var updated = customTemplates
        updated[index].css[area] = text
        updated[index].updatedAt = Date()
        customTemplates = updated
    }

    func makeBlankTemplate() {
        let template = ReviewPanelStyleTemplate(name: "我的样式")
        customTemplates = ReviewPanelStyleLibrary.upserting(template, into: customTemplates)
        select(id: template.id)
    }

    /// 汇入 JSON 包；也接受一整份纯 CSS 文本（当作评论列表样式）。
    @discardableResult
    func importData(_ data: Data, fileName: String) throws -> ReviewPanelStyleTemplate {
        if let package = ReviewPanelStyleTemplate.PackageFile.decode(data) {
            let template = package.makeTemplate()
            upsert(template)
            return template
        }
        guard let css = String(data: data, encoding: .utf8) else {
            throw ImportFailure(message: "档案不是可读取的 CSS 样式。")
        }
        var template = ReviewPanelStyleTemplate(name: fileName.isEmpty ? "汇入样式" : fileName)
        template.css[.comment] = css
        upsert(template)
        return template
    }

    struct ImportFailure: LocalizedError {
        let message: String
        var errorDescription: String? { message }
    }

    /// 当前启用模板四个区域的 CSS（未启用时为空）。
    func activeCSS() -> [ReviewPanelCSSArea: String] {
        guard let template = selectedTemplate else { return [:] }
        var result: [ReviewPanelCSSArea: String] = [:]
        for area in ReviewPanelCSSArea.allCases {
            result[area] = template.css(for: area)
        }
        return result
    }
}
