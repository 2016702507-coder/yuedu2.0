import Foundation
import Observation
import SwiftUI

// MARK: - 显示模式

/// 点开评论时的默认显示模式。
///
/// 这一页设置现在是「一页两态」：
/// - `.native`：SwiftUI 原生玻璃卡片，下面的参数全部真正生效；
/// - `.web`：书源给的原网页，旧的「段评与互动样式」CSS 模板与分区 CSS 只对这一模式生效。
///
/// 两态互斥显示，旧样式数据一个不丢，界面也不会摆着一堆点了没反应的控件。
enum NativeReviewDisplayMode: String, Codable, CaseIterable, Identifiable, Sendable {
    case native
    case web

    var id: String { rawValue }

    var title: String {
        switch self {
        case .native: return localized("原生玻璃卡片")
        case .web: return localized("书源原网页")
        }
    }

    var caption: String {
        switch self {
        case .native:
            return localized("按评论数据直接画卡片，头像、等级、时间·IP、点赞、楼中楼都是原生控件。下面的参数即时生效。")
        case .web:
            return localized("原样显示书源段评页。下面的 CSS 模板与分区 CSS 只作用于网页，不影响原生卡片。")
        }
    }
}

// MARK: - 排版（可由旧 CSS 模板桥接）

/// 卡片的排版参数。桥接只改这几项，**颜色、背景、content 一律不碰**，
/// 保证「统一玻璃、不要白底、不要花里胡哨」的外观不被 CSS 破坏。
struct NativeReviewTypography: Equatable, Sendable {
    var nameSize: CGFloat
    var contentSize: CGFloat
    var metaSize: CGFloat
    var lineSpacing: CGFloat
    var fontFamily: String?
    var letterSpacing: CGFloat?

    func font(size: CGFloat, weight: Font.Weight = .regular) -> Font {
        if let family = fontFamily, !family.isEmpty {
            // 自订字体名交给系统回退；字重由调用处的 .fontWeight 兜底，
            // 不依赖任何特定 iOS 版本的 Font 实例方法。
            return Font.custom(family, size: size)
        }
        return Font.system(size: size, weight: weight)
    }
}

// MARK: - 原生面板样式存储

/// 原生段评面板的可调参数。
///
/// 玻璃浓淡不在这里另存一份：`GlobalSettings.reviewSheetOpacity` 是唯一真值，
/// 设置页直接绑它，和「外观 › 界面效果」的滑杆天然联动，不会出现两个值打架。
@MainActor
@Observable
final class NativeReviewPanelStyleStore {
    static let shared = NativeReviewPanelStyleStore()

    private static let storageKey = "yd_native_review_panel_style"

    /// 只用于落盘；界面绑定走下面那些独立存储属性，`@Bindable` 才拿得到 Binding。
    private struct Storage: Codable {
        var displayMode: NativeReviewDisplayMode
        var cardOpacity: Double
        var cornerRadius: Double
        var avatarSize: Double
        var nameFontSize: Double
        var contentFontSize: Double
        var metaFontSize: Double
        var lineSpacing: Double
        var showsLevel: Bool
        var showsMeta: Bool
        var showsQuote: Bool
        var showsImages: Bool
        var showsLikes: Bool
        var showsVoice: Bool
        var collapsedReplyLimit: Int
        var repliesDefaultExpanded: Bool
        var typographyBridgeEnabled: Bool
        var bridgeTemplateID: String?
    }

    /// init 期间为 true：属性观察器不落盘，避免默认值覆盖已存的设置。
    private var isLoading = true

    var displayMode: NativeReviewDisplayMode = .native { didSet { save() } }
    /// 卡片白底的浓度。0 完全透明，默认 0.03（保持现在的极淡高光）。
    var cardOpacity: Double = 0.03 { didSet { save() } }
    var cornerRadius: Double = 14 { didSet { save() } }
    var avatarSize: Double = 38 { didSet { save() } }
    var nameFontSize: Double = 14 { didSet { save() } }
    var contentFontSize: Double = 15.5 { didSet { save() } }
    var metaFontSize: Double = 12 { didSet { save() } }
    var lineSpacing: Double = 4 { didSet { save() } }

    var showsLevel: Bool = true { didSet { save() } }
    var showsMeta: Bool = true { didSet { save() } }
    var showsQuote: Bool = true { didSet { save() } }
    var showsImages: Bool = true { didSet { save() } }
    var showsLikes: Bool = true { didSet { save() } }
    var showsVoice: Bool = true { didSet { save() } }

    var collapsedReplyLimit: Int = 2 { didSet { save() } }
    var repliesDefaultExpanded: Bool = false { didSet { save() } }

    /// 让旧 CSS 模板的字号 / 行距 / 字体也影响原生卡片。默认关。
    var typographyBridgeEnabled: Bool = false { didSet { save() } }
    /// 桥接来源模板。独立于网页模式的「启用自订样式」开关，不会顺手把网页 CSS 打开。
    var bridgeTemplateID: String? { didSet { save() } }

    private init() {
        if let data = UserDefaults.standard.data(forKey: Self.storageKey),
           let saved = try? JSONDecoder().decode(Storage.self, from: data) {
            displayMode = saved.displayMode
            cardOpacity = saved.cardOpacity
            cornerRadius = saved.cornerRadius
            avatarSize = saved.avatarSize
            nameFontSize = saved.nameFontSize
            contentFontSize = saved.contentFontSize
            metaFontSize = saved.metaFontSize
            lineSpacing = saved.lineSpacing
            showsLevel = saved.showsLevel
            showsMeta = saved.showsMeta
            showsQuote = saved.showsQuote
            showsImages = saved.showsImages
            showsLikes = saved.showsLikes
            showsVoice = saved.showsVoice
            collapsedReplyLimit = saved.collapsedReplyLimit
            repliesDefaultExpanded = saved.repliesDefaultExpanded
            typographyBridgeEnabled = saved.typographyBridgeEnabled
            bridgeTemplateID = saved.bridgeTemplateID
        }
        isLoading = false
    }

    private func save() {
        guard !isLoading else { return }
        let snapshot = Storage(
            displayMode: displayMode,
            cardOpacity: Self.clamp(cardOpacity, 0...0.3),
            cornerRadius: Self.clamp(cornerRadius, 0...28),
            avatarSize: Self.clamp(avatarSize, 20...60),
            nameFontSize: Self.clamp(nameFontSize, 10...20),
            contentFontSize: Self.clamp(contentFontSize, 12...22),
            metaFontSize: Self.clamp(metaFontSize, 9...16),
            lineSpacing: Self.clamp(lineSpacing, 0...14),
            showsLevel: showsLevel,
            showsMeta: showsMeta,
            showsQuote: showsQuote,
            showsImages: showsImages,
            showsLikes: showsLikes,
            showsVoice: showsVoice,
            collapsedReplyLimit: max(0, min(collapsedReplyLimit, 10)),
            repliesDefaultExpanded: repliesDefaultExpanded,
            typographyBridgeEnabled: typographyBridgeEnabled,
            bridgeTemplateID: bridgeTemplateID
        )
        guard let data = try? JSONEncoder().encode(snapshot) else { return }
        UserDefaults.standard.set(data, forKey: Self.storageKey)
    }

    private static func clamp(_ value: Double, _ range: ClosedRange<Double>) -> Double {
        min(max(value, range.lowerBound), range.upperBound)
    }

    // MARK: - 桥接

    /// 桥接用的模板：优先用户选的，没选就退回内置首套，但**只在开关打开时**才用。
    var bridgeTemplate: ReviewPanelStyleTemplate? {
        guard typographyBridgeEnabled else { return nil }
        let all = ReviewPanelStyleStore.shared.allTemplates
        if let raw = bridgeTemplateID,
           let id = UUID(uuidString: raw),
           let hit = all.first(where: { $0.id == id }) {
            return hit
        }
        return all.first
    }

    /// 当前生效的排版。桥接关闭时就是用户自己拖的四个数值。
    func typography() -> NativeReviewTypography {
        var result = NativeReviewTypography(
            nameSize: CGFloat(nameFontSize),
            contentSize: CGFloat(contentFontSize),
            metaSize: CGFloat(metaFontSize),
            lineSpacing: CGFloat(lineSpacing),
            fontFamily: nil,
            letterSpacing: nil
        )
        guard typographyBridgeEnabled, let template = bridgeTemplate else { return result }

        // 面板整体字号优先，其次评论正文；热评 / 本章说放最后兜底。
        let css = [ReviewPanelCSSArea.panel, .comment, .chapterNote, .hot]
            .map { template.css(for: $0) }
            .joined(separator: "\n")

        if let size = Self.firstNumber(for: "font-size", in: css) {
            let content = CGFloat(min(max(size, 12), 22))
            result.contentSize = content
            result.nameSize = CGFloat(min(max(content - 1.5, 10), 20))
            result.metaSize = CGFloat(min(max(content - 3.5, 9), 16))
        }
        if let leading = Self.firstNumber(for: "line-height", in: css) {
            // 纯数字当倍数（1.6），带 px 的当绝对行高；都折成行距点数。
            let points = leading <= 3
                ? (leading - 1) * Double(result.contentSize)
                : leading - Double(result.contentSize)
            result.lineSpacing = CGFloat(min(max(points, 0), 12))
        }
        if let family = Self.firstFontFamily(in: css) { result.fontFamily = family }
        if let tracking = Self.firstNumber(for: "letter-spacing", in: css) {
            result.letterSpacing = CGFloat(min(max(tracking, -1), 3))
        }
        return result
    }

    /// 去掉注释与 @dark / @light 条件块：夜间分支里的字号不该盖掉主字号。
    private static func readableCSS(_ raw: String) -> String {
        var out = raw
        if let comments = try? NSRegularExpression(pattern: #"/\*[\s\S]*?\*/"#, options: []) {
            out = comments.stringByReplacingMatches(
                in: out, range: NSRange(out.startIndex..., in: out), withTemplate: ""
            )
        }
        if let blocks = try? NSRegularExpression(
            pattern: #"@(?:dark|light)\s*\{[^{}]*\}"#, options: [.caseInsensitive]
        ) {
            out = blocks.stringByReplacingMatches(
                in: out, range: NSRange(out.startIndex..., in: out), withTemplate: ""
            )
        }
        return out
    }

    private static func firstNumber(for property: String, in css: String) -> Double? {
        let clean = readableCSS(css)
        let pattern = #"(?:^|[;{\s])\#(NSRegularExpression.escapedPattern(for: property))\s*:\s*(-?[0-9]+(?:\.[0-9]+)?)"#
        guard let re = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive]),
              let match = re.firstMatch(in: clean, range: NSRange(clean.startIndex..., in: clean)),
              match.numberOfRanges > 1,
              let range = Range(match.range(at: 1), in: clean) else { return nil }
        return Double(String(clean[range]))
    }

    private static func firstFontFamily(in css: String) -> String? {
        let clean = readableCSS(css)
        guard let re = try? NSRegularExpression(
            pattern: #"font-family\s*:\s*([^;}]+)"#, options: [.caseInsensitive]
        ),
        let match = re.firstMatch(in: clean, range: NSRange(clean.startIndex..., in: clean)),
        match.numberOfRanges > 1,
        let range = Range(match.range(at: 1), in: clean) else { return nil }

        let first = clean[range].split(separator: ",").first.map(String.init) ?? ""
        var name = first
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .trimmingCharacters(in: CharacterSet(charactersIn: "\"'"))
            .trimmingCharacters(in: .whitespacesAndNewlines)
        switch name.lowercased() {
        case "serif": name = "Songti SC"
        case "monospace": name = "Menlo"
        case "rounded": name = ""
        default: break
        }
        guard !name.isEmpty, name.count <= 40 else { return nil }
        let allowed = CharacterSet.alphanumerics.union(CharacterSet(charactersIn: " -_."))
        guard name.unicodeScalars.allSatisfy({ allowed.contains($0) }) else { return nil }
        return name
    }
}
