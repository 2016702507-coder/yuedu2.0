import Foundation

/// 书签卡片上那段摘录的整理。
enum ReaderBookmarkExcerpt {
    /// The excerpt as text to read. A stored excerpt keeps the U+FFFC of each picture it
    /// spans, character for character with the book (`PictureOffsetMigration` reads it so);
    /// a picture has no text to show.
    static func plain(_ excerpt: String) -> String {
        excerpt.replacingOccurrences(of: "\u{FFFC}", with: "")
    }

    /// 去掉摘录开头重复的章名。
    ///
    /// 章首那一页的内文第一行就是排进版面的章节标题（`plainText(forPage:)` 取的是
    /// 排版后的文字，标题也在里面），而卡片正上方的分组标题已经写著同一个章名——
    /// 不处理的话，整张卡片的两行就只是把标题再抄一次，看不出这一页讲什么。
    ///
    /// 比对时忽略空白：版面里的标题用全形空格分隔，目录里的同一个标题用半形，
    /// 直接 `hasPrefix` 对不上。
    static func body(of excerpt: String, chapterTitle: String) -> String {
        let trimmedExcerpt = plain(excerpt).trimmingCharacters(in: .whitespacesAndNewlines)
        let title = chapterTitle.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !title.isEmpty, !trimmedExcerpt.isEmpty else { return trimmedExcerpt }

        var excerptIndex = trimmedExcerpt.startIndex
        var titleIndex = title.startIndex
        while titleIndex < title.endIndex {
            if title[titleIndex].isWhitespace {
                titleIndex = title.index(after: titleIndex)
                continue
            }
            guard excerptIndex < trimmedExcerpt.endIndex else { return trimmedExcerpt }
            if trimmedExcerpt[excerptIndex].isWhitespace {
                excerptIndex = trimmedExcerpt.index(after: excerptIndex)
                continue
            }
            guard trimmedExcerpt[excerptIndex] == title[titleIndex] else { return trimmedExcerpt }
            excerptIndex = trimmedExcerpt.index(after: excerptIndex)
            titleIndex = title.index(after: titleIndex)
        }

        let rest = trimmedExcerpt[excerptIndex...].trimmingCharacters(in: .whitespacesAndNewlines)
        // 整段摘录就只有章名（标题自己占满一页的封面页）：留著章名，空白卡片更难认。
        return rest.isEmpty ? trimmedExcerpt : rest
    }
}
