import Foundation

/// 书签清单的一章：章节标题一条，底下是这章的书签，依书中顺序排列。
///
/// 一页一个书签之后，一章可以有很多条，平舖成一列会让同一个章名重复十几次。
/// 分组让章名只出现一次，并且成为「跳回本章开头」的入口——章内每一条书签
/// 各自跳回自己那一页。
struct ReaderBookmarkChapterGroup: Identifiable, Equatable {
    let chapterIndex: Int
    let items: [Bookmark]

    var id: Int { chapterIndex }

    /// 依章节分组。章与章之间、章内各条之间都照书中位置排序，和阅读顺序一致。
    static func group(_ bookmarks: [Bookmark]) -> [ReaderBookmarkChapterGroup] {
        Dictionary(grouping: bookmarks.sortedByStablePosition(), by: \.chapterIndex)
            .map { ReaderBookmarkChapterGroup(chapterIndex: $0.key, items: $0.value) }
            .sorted { lhs, rhs in
                guard let left = lhs.items.first, let right = rhs.items.first else {
                    return lhs.chapterIndex < rhs.chapterIndex
                }
                return Bookmark.stablePositionSort(left, right)
            }
    }
}
