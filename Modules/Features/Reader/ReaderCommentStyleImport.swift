import CoreTransferable
import Foundation
import UniformTypeIdentifiers

/// Reads a 段评气泡 style or a card template file into 气泡设置's library and wears it — the
/// one route behind every 汇入样式 on those pages, run by `readerStyleImportPresentation`.
@MainActor
enum ReaderCommentStyleImporter {
    enum Target: Equatable, Sendable {
        case bubble
        case card(ReaderCommentCardKind)
    }

    struct Failure: LocalizedError {
        let message: String
        var errorDescription: String? { message }
    }

    static let contentTypes: [UTType] = [.svg, .json, .plainText, .data]

    static func importFile(at url: URL, into target: Target) throws -> String {
        let data = try Data(contentsOf: url)
        let fileName = url.deletingPathExtension().lastPathComponent
            .trimmingCharacters(in: .whitespacesAndNewlines)
        switch target {
        case .bubble:
            return try importBubble(data, fileName: fileName)
        case .card(let kind):
            return try importCard(data, fileName: fileName, kind: kind)
        }
    }

    // MARK: - 段评气泡

    /// A `bubble.json` keeps its colours and size; a bare SVG is taken as it is.
    static func importBubble(_ data: Data, fileName: String) throws -> String {
        let settings = GlobalSettings.shared
        if let style = ReaderCommentBubbleCustomStyle.fromBubblePackage(data) {
            if let message = bubbleValidationMessage(for: style.svg) { throw Failure(message: message) }
            settings.upsertCommentBubbleCustomStyle(style)
            if let scale = style.sizeScale {
                settings.commentBubbleScale = GlobalSettings.sanitizedCommentBubbleScale(scale)
            }
            settings.commentBubbleFollowsSourceSVG = false
            return localized("已套用自订段评气泡 SVG。")
        }
        guard let svg = String(data: data, encoding: .utf8) else {
            throw Failure(message: localized("档案不是可读取的 SVG。"))
        }
        let trimmed = svg.trimmingCharacters(in: .whitespacesAndNewlines)
        if let message = bubbleValidationMessage(for: trimmed) { throw Failure(message: message) }
        settings.upsertCommentBubbleCustomStyle(
            ReaderCommentBubbleCustomStyle(name: fileName.isEmpty ? localized("自订 SVG") : fileName, svg: trimmed)
        )
        settings.commentBubbleFollowsSourceSVG = false
        return localized("已套用自订段评气泡 SVG。")
    }

    /// Why `svg` cannot be a 段评 bubble, or nil when it can.
    static func bubbleValidationMessage(for svg: String) -> String? {
        if svg.utf8.count > CommentBubbleSVGRecognizer.maximumUserTemplateSVGByteCount {
            return String(
                format: localized("SVG 档案过大，请使用小于 %d KB 的气泡样式。"),
                CommentBubbleSVGRecognizer.maximumUserTemplateSVGByteCount / 1024
            )
        }
        guard svg.lowercased().contains("<svg") else {
            return localized("档案不是可读取的 SVG。")
        }
        guard CommentBubbleSVGRecognizer.recognizeUserTemplate(svg) != nil else {
            return localized("这个 SVG 没有可绘制的内容，无法作为段评气泡。")
        }
        return nil
    }

    // MARK: - Cards

    /// A package names its own kind and lands there, wherever it was imported from; a bare
    /// SVG becomes a template of `kind`.
    static func importCard(_ data: Data, fileName: String, kind: ReaderCommentCardKind) throws -> String {
        let style: ReaderCommentCardCustomStyle
        if let package = ReaderCommentCardPackageFile.decode(data) {
            style = package.makeStyle()
        } else {
            guard let svg = String(data: data, encoding: .utf8) else {
                throw Failure(message: localized("档案不是可读取的 SVG。"))
            }
            style = ReaderCommentCardCustomStyle(
                kind: kind,
                name: fileName.isEmpty ? localized("自订模板") : fileName,
                svg: svg.trimmingCharacters(in: .whitespacesAndNewlines)
            )
        }
        do {
            _ = try ReviewCardTemplate(source: style.svg)
        } catch {
            throw Failure(message: error.localizedDescription)
        }
        GlobalSettings.shared.upsertCommentCardStyle(style)
        return appliedMessage(for: style.kind)
    }

    static func appliedMessage(for kind: ReaderCommentCardKind) -> String {
        switch kind {
        case .chapterSay: return localized("已套用自订本章说模板。")
        case .authorSay: return localized("已套用自订作者说模板。")
        case .hotComment: return localized("已套用自订神评论模板。")
        }
    }
}

// MARK: - Export

/// 汇出目前样式 as a bare `.svg`: the built-in styles, and custom ones with nothing else to carry.
///
/// `ShareLink` rather than `.fileExporter`, as a direct Form row, for the reason recorded in
/// `Technotes/iOS17MenuModalPresentation.md`.
struct CommentStyleSVGExport: Transferable {
    let filename: String
    let svg: String

    init(name: String, svg: String) {
        filename = ReaderStyleExportFilename.make(name, pathExtension: "svg")
        self.svg = svg
    }

    static var transferRepresentation: some TransferRepresentation {
        FileRepresentation(exportedContentType: .svg) { payload in
            let url = FileManager.default.temporaryDirectory.appendingPathComponent(payload.filename)
            try Data(payload.svg.utf8).write(to: url, options: .atomic)
            return SentTransferredFile(url)
        }
    }
}

/// 汇出目前样式 as JSON: a 段评 bubble's `bubble.json`, or a card template's package — the
/// forms that keep colours a bare `.svg` would lose.
struct CommentStyleJSONExport: Transferable {
    let filename: String
    let data: Data

    init(bubble style: ReaderCommentBubbleCustomStyle) throws {
        filename = ReaderStyleExportFilename.make(style.name, pathExtension: "json")
        data = try Self.encoder.encode(BubblePackageFile(style: style))
    }

    init(card style: ReaderCommentCardCustomStyle) throws {
        filename = ReaderStyleExportFilename.make(style.name, pathExtension: "json")
        data = try Self.encoder.encode(ReaderCommentCardPackageFile(style: style))
    }

    private static var encoder: JSONEncoder {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        return encoder
    }

    static var transferRepresentation: some TransferRepresentation {
        FileRepresentation(exportedContentType: .json) { payload in
            let url = FileManager.default.temporaryDirectory.appendingPathComponent(payload.filename)
            try payload.data.write(to: url, options: .atomic)
            return SentTransferredFile(url)
        }
    }
}
