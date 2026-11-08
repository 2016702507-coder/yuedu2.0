import Foundation

/// 把一本**已下载**的书写成单一 TXT，交给系统分享面板存到「档案」或传出去。
///
/// 只输出这台装置真的存下来的章节：`ChapterCacheRepository` 的章节包是阅读管线
/// 的唯一来源，缺章就跳过并回报数量。不为了凑满目录去连网——汇出的内容必须跟
/// 离线打开时看到的一致，否则使用者会拿到一本封面完整、内文有洞的书。
///
/// 输入先在主执行绪摊平成 `Input`（`Sendable`），写档在 detached task 里做：
/// 一本三千章的书是几十 MB 的字串拼接，留在主执行绪会让汇出按钮按下后画面卡住。
enum BookTXTExportFile {

    /// 汇出需要的全部资料。刻意不带 `ReadingBook`——它是可变的 UI 状态，
    /// 跨执行绪传会踩到这个专案的严格并发检查。
    struct Input: Sendable {
        var bookId: UUID
        var title: String
        var author: String
        var chapters: [Chapter]

        struct Chapter: Sendable {
            var index: Int
            var title: String
        }
    }

    struct Result: Sendable {
        var url: URL
        var exportedChapters: Int
        var skippedChapters: Int
    }

    enum ExportError: LocalizedError {
        case nothingDownloaded

        var errorDescription: String? {
            switch self {
            case .nothingDownloaded:
                return localized("这本书还没有已下载的章节。")
            }
        }
    }

    static func write(_ input: Input, named name: String) async throws -> Result {
        try await Task.detached(priority: .userInitiated) {
            try Self.writeSync(input, named: name)
        }.value
    }

    private static func writeSync(_ input: Input, named name: String) throws -> Result {
        let repository = ChapterCacheRepository()
        let author = input.author.trimmingCharacters(in: .whitespacesAndNewlines)

        var text = ""
        text.reserveCapacity(1 << 20)
        text += input.title.trimmingCharacters(in: .whitespacesAndNewlines)
        text += "\n"
        if !author.isEmpty {
            text += String(format: localized("作者：%@"), author) + "\n"
        }
        text += "\n"

        var exported = 0
        var skipped = 0
        for chapter in input.chapters.sorted(by: { $0.index < $1.index }) {
            guard
                let package = repository.loadChapterPackageSync(
                    bookId: input.bookId,
                    chapterIndex: chapter.index
                ), package.state == .cached
            else {
                skipped += 1
                continue
            }
            // 目录不一定还在记忆体里（`BookStore` 的纪录刻意不带章节表），
            // 这时用快取包自己记下的目录标题，标题才不会退化成「第 N 章」。
            let heading = chapter.title.trimmingCharacters(in: .whitespacesAndNewlines)
            let resolved = !heading.isEmpty
                ? heading
                : (package.tocTitle?.trimmingCharacters(in: .whitespacesAndNewlines) ?? "")
            text += resolved.isEmpty ? String(format: localized("第 %d 章"), chapter.index + 1) : resolved
            text += "\n\n"
            text += package.content.trimmingCharacters(in: .whitespacesAndNewlines)
            text += "\n\n"
            exported += 1
        }

        guard exported > 0 else { throw ExportError.nothingDownloaded }

        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent(safeFilename(name) + ".txt")
        try text.write(to: url, atomically: true, encoding: .utf8)
        return Result(url: url, exportedChapters: exported, skippedChapters: skipped)
    }

    /// 「档案」App 与各类云盘对 `/`、`:` 这几个字元都不客气，书名里带标点很常见。
    private static func safeFilename(_ raw: String) -> String {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        let base = trimmed.isEmpty ? localized("未命名书籍") : trimmed
        let illegal = CharacterSet(charactersIn: "/\\:*?\"<>|\n\r\t")
        return base.components(separatedBy: illegal).joined(separator: " ")
    }
}
