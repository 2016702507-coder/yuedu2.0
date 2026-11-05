import Foundation

/// 把一本**已下載**的書寫成單一 TXT，交給系統分享面板存到「檔案」或傳出去。
///
/// 只輸出這台裝置真的存下來的章節：`ChapterCacheRepository` 的章節包是閱讀管線
/// 的唯一來源，缺章就跳過並回報數量。不為了湊滿目錄去連網——匯出的內容必須跟
/// 離線打開時看到的一致，否則使用者會拿到一本封面完整、內文有洞的書。
///
/// 輸入先在主執行緒攤平成 `Input`（`Sendable`），寫檔在 detached task 裡做：
/// 一本三千章的書是幾十 MB 的字串拼接，留在主執行緒會讓匯出按鈕按下後畫面卡住。
enum BookTXTExportFile {

    /// 匯出需要的全部資料。刻意不帶 `ReadingBook`——它是可變的 UI 狀態，
    /// 跨執行緒傳會踩到這個專案的嚴格併發檢查。
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
                return localized("這本書還沒有已下載的章節。")
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
            // 目錄不一定還在記憶體裡（`BookStore` 的紀錄刻意不帶章節表），
            // 這時用快取包自己記下的目錄標題，標題才不會退化成「第 N 章」。
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

    /// 「檔案」App 與各類雲盤對 `/`、`:` 這幾個字元都不客氣，書名裡帶標點很常見。
    private static func safeFilename(_ raw: String) -> String {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        let base = trimmed.isEmpty ? localized("未命名書籍") : trimmed
        let illegal = CharacterSet(charactersIn: "/\\:*?\"<>|\n\r\t")
        return base.components(separatedBy: illegal).joined(separator: " ")
    }
}
