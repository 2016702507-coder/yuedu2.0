import SwiftUI

/// 阅读器「书签／重点」清单（Apple Books 风格）。
/// 由底部工具列的书签按钮开启，列出书签与标注（底线/萤光笔），依章节分组。
///
/// 清单本体使用 SwiftUI `List` 搭配 `selection` 绑定（见 `BookmarkSelectionList`），
/// 系统会自动支援 iOS 原生的两指拖曳多选手势。
/// 本档负责 sheet 外框：分页、工具列（checklist↔checkmark 编辑切换、关闭）、
/// 以及原生底部 toolbar 的「已选取 N 个」与删除按钮。
struct ReaderBookmarkListView: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    enum Segment: Hashable {
        case bookmark
        case highlight
    }

    let bookTitle: String
    let bookmarks: [Bookmark]
    /// 标注在所属章节内的页码（1-based）；无法解析时回传 nil。
    let pageNumber: (Bookmark) -> Int?
    /// 章名用目前的目录解析（含繁简转换），不是书签存档时的那一份。
    let chapterTitle: (Int) -> String
    let onSelect: (Bookmark) -> Void
    /// 点章名：跳回这一章的开头。
    let onSelectChapter: (Int) -> Void
    let onDelete: (Bookmark) -> Void
    /// 见 `BookmarkSelectionList.indexesReadText`。
    var indexesReadText: (Bookmark) -> Bool = { _ in true }

    @Binding var isPresented: Bool

    @State private var segment: Segment = .bookmark
    @State private var selection = Set<UUID>()
    @State private var editMode: EditMode = .inactive

    private var bookmarkItems: [Bookmark] {
        bookmarks.filter { $0.kind == .bookmark }
    }

    private var highlightItems: [Bookmark] {
        bookmarks.filter { $0.kind == .underline || $0.kind == .highlight }
    }

    private var currentItems: [Bookmark] {
        segment == .bookmark ? bookmarkItems : highlightItems
    }

    private var isEditing: Bool {
        editMode.isEditing
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                Picker("", selection: $segment) {
                    Text(localized("书签")).tag(Segment.bookmark)
                    Text(localized("重点")).tag(Segment.highlight)
                }
                .pickerStyle(.segmented)
                .labelsHidden()
                .padding(.horizontal, DSSpacing.lg)
                .padding(.vertical, DSSpacing.sm)

                content
            }
            .navigationTitle(bookTitle)
            .toolbarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) { editToggleButton }
                ToolbarItem(placement: .topBarTrailing) { closeButton }
            }
            .toolbar {
                // 原生底部 toolbar：已选取计数 + 删除按钮
                ToolbarItemGroup(placement: .bottomBar) {
                    if isEditing {
                        Text(selectedCountText)
                            .font(DSFont.subheadline)
                            .foregroundStyle(DSColor.textSecondary)

                        Spacer()

                        Button {
                            deleteSelected()
                        } label: {
                            Image(systemName: "trash")
                        }
                        .disabled(selection.isEmpty)
                        .accessibilityLabel(localized("删除"))
                    }
                }
            }
            .background(PageBackgroundView(scope: .settings).ignoresSafeArea())
            .pageBackgroundToolbar(for: .settings)
            .environment(\.editMode, $editMode)
            .onChange(of: segment) {
                selection.removeAll()
            }
            .onChange(of: editMode) {
                // 退出编辑模式时清空选取
                if !editMode.isEditing {
                    selection.removeAll()
                }
            }
        }
    }

    // MARK: - Toolbar

    private var editToggleButton: some View {
        Button {
            withAnimation(reduceMotion ? nil : DSAnimation.standard) {
                if editMode.isEditing {
                    editMode = .inactive
                } else {
                    editMode = .active
                }
            }
        } label: {
            Image(systemName: isEditing ? "xmark" : "checklist")
        }
        .accessibilityLabel(localized(isEditing ? "完成" : "编辑"))
    }

    private var closeButton: some View {
        Button {
            isPresented = false
        } label: {
            Image(systemName: "checkmark")
        }
        .accessibilityLabel(localized("完成"))
    }

    // MARK: - Content

    private var content: some View {
        BookmarkListSection(
            isBookmark: segment == .bookmark,
            items: currentItems,
            pageNumber: pageNumber,
            chapterTitle: chapterTitle,
            onSelect: onSelect,
            onSelectChapter: onSelectChapter,
            onDelete: onDelete,
            indexesReadText: indexesReadText,
            selection: $selection
        )
    }

    // MARK: - Editing helpers

    private var selectedCountText: String {
        let format = segment == .bookmark ? localized("已选取 %d 个书签") : localized("已选取 %d 个重点")
        return String(format: format, selection.count)
    }

    private func deleteSelected() {
        currentItems
            .filter { selection.contains($0.id) }
            .forEach(onDelete)
        selection.removeAll()
    }
}

/// 单一种类（书签 或 重点）的清单内容 ＋ 空状态，供阅读器目录面板的分页与书签面板共用。
/// 不含外框（`NavigationStack`）、分页切换与工具列——那些由容器负责。
struct BookmarkListSection: View {
    let isBookmark: Bool
    let items: [Bookmark]
    /// 标注在所属章节内的页码（1-based）；无法解析时回传 nil。
    let pageNumber: (Bookmark) -> Int?
    let chapterTitle: (Int) -> String
    let onSelect: (Bookmark) -> Void
    let onSelectChapter: (Int) -> Void
    let onDelete: (Bookmark) -> Void
    var indexesReadText: (Bookmark) -> Bool = { _ in true }

    @Binding var selection: Set<UUID>

    var body: some View {
        if items.isEmpty {
            if isBookmark {
                ContentUnavailableView {
                    UnavailableLabel(localized("没有书签"), systemImage: "bookmark")
                } description: {
                    Text(localized("在想记住的那一页向下滑动，或点一下右上角的书签按钮。")).font(DSFont.unavailableDescription).foregroundStyle(DSColor.textSecondary)
                }
            } else {
                ContentUnavailableView {
                    UnavailableLabel(localized("没有重点"), systemImage: "highlighter")
                } description: {
                    Text(localized("在阅读时选取文字，加入底线或萤光笔即可在此查看。")).font(DSFont.unavailableDescription).foregroundStyle(DSColor.textSecondary)
                }
            }
        } else {
            BookmarkSelectionList(
                groups: ReaderBookmarkChapterGroup.group(items),
                selection: $selection,
                chapterTitle: resolvedChapterTitle,
                primaryText: { bm in
                    // 章首那一页的摘录开头就是排进版面的章名，而它正上方的分组标题
                    // 已经写著同一句；重复两次等于这张卡片没说出这一页讲什么。
                    let body = ReaderBookmarkExcerpt.body(
                        of: bm.excerpt,
                        chapterTitle: resolvedChapterTitle(
                            ReaderBookmarkChapterGroup(chapterIndex: bm.chapterIndex, items: [bm])
                        )
                    )
                    // 只有插图的那一页没有文字可摘。
                    return body.isEmpty ? bm.chapterTitle : body
                },
                icon: { bm in
                    switch bm.kind {
                    case .bookmark: return "bookmark"
                    case .underline: return "underline"
                    case .highlight: return "highlighter"
                    }
                },
                dateText: { Self.relativeDate($0.date) },
                pageText: { pageNumber($0).map { String($0) } },
                noteText: { bm in
                    let note = bm.note.trimmingCharacters(in: .whitespacesAndNewlines)
                    return note.isEmpty ? nil : note
                },
                onSelect: onSelect,
                onSelectChapter: { onSelectChapter($0.chapterIndex) },
                onDelete: onDelete,
                indexesReadText: indexesReadText
            )
        }
    }

    /// 章名优先用目前的目录；解析不出来（章节已被移除、离线书换源）就退回书签
    /// 存档时的章名，总比一个空标题好。
    private func resolvedChapterTitle(_ group: ReaderBookmarkChapterGroup) -> String {
        let resolved = chapterTitle(group.chapterIndex)
        return resolved.isEmpty ? (group.items.first?.chapterTitle ?? "") : resolved
    }

    private static let relativeFormatter: RelativeDateTimeFormatter = {
        let f = RelativeDateTimeFormatter()
        f.dateTimeStyle = .named
        f.unitsStyle = .full
        return f
    }()

    private static func relativeDate(_ date: Date) -> String {
        relativeFormatter.localizedString(for: date, relativeTo: Date())
    }
}

#Preview("有资料") {
    ReaderBookmarkListView(
        bookTitle: "剑来",
        bookmarks: [
            Bookmark(
                chapterIndex: 118,
                chapterTitle: "第 119 章 观剑大会",
                position: CoreTextReadingPosition(spineIndex: 118, charOffset: 0),
                excerpt: "他能在「一表人才」之外特地强调一句「天赋上佳」，那便说明这个年轻人的天赋不是一般的好。",
                date: Date().addingTimeInterval(-60)
            ),
            Bookmark(
                chapterIndex: 118,
                chapterTitle: "第 119 章 观剑大会",
                position: CoreTextReadingPosition(spineIndex: 118, charOffset: 1240),
                excerpt: "陆欢得了许可，立刻便像一只得了赦令的小猫，轻手轻脚地跨过门槛，小碎步溜到沈回身边站好。",
                date: Date().addingTimeInterval(-90)
            ),
            Bookmark(
                chapterIndex: 119,
                chapterTitle: "第 120 章 剑气长城",
                position: CoreTextReadingPosition(spineIndex: 119, charOffset: 640),
                excerpt: "城头上的风，吹了千年。",
                date: Calendar.current.date(byAdding: .day, value: -1, to: Date()) ?? Date()
            ),
        ],
        pageNumber: { _ in 3 },
        chapterTitle: { index in index == 118 ? "第 119 章 观剑大会" : "第 120 章 剑气长城" },
        onSelect: { _ in },
        onSelectChapter: { _ in },
        onDelete: { _ in },
        isPresented: .constant(true)
    )
}

#Preview("另一版转换文字的书签") {
    let current = Bookmark(
        chapterIndex: 2, chapterTitle: "第三章",
        position: CoreTextReadingPosition(spineIndex: 2, charOffset: 0),
        excerpt: "这一条对著目前的文字，点了会跳过去。", date: Date().addingTimeInterval(-60), textVersion: 2
    )
    let older = Bookmark(
        chapterIndex: 2, chapterTitle: "第三章",
        position: CoreTextReadingPosition(spineIndex: 2, charOffset: 480),
        excerpt: "这一条建立在上一版转换的文字上。", date: Date().addingTimeInterval(-3600), textVersion: 1
    )
    ReaderBookmarkListView(
        bookTitle: "转换书",
        bookmarks: [current, older],
        pageNumber: { _ in 3 },
        chapterTitle: { _ in "第三章" },
        onSelect: { _ in },
        onSelectChapter: { _ in },
        onDelete: { _ in },
        indexesReadText: { $0.textVersion == 2 },
        isPresented: .constant(true)
    )
}

#Preview("空状态") {
    ReaderBookmarkListView(
        bookTitle: "剑来",
        bookmarks: [],
        pageNumber: { _ in nil },
        chapterTitle: { _ in "" },
        onSelect: { _ in },
        onSelectChapter: { _ in },
        onDelete: { _ in },
        isPresented: .constant(true)
    )
}
