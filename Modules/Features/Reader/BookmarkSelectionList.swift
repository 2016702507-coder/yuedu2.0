import SwiftUI

/// 章节分组的书签／重点清单：每章一个 `Section`，章名可点（跳回本章开头），
/// 底下是这章的卡片，每张卡片跳回它自己那一页。
///
/// 用 `List` 搭配 `selection` 绑定，系统就会自带 iOS 原生的两指拖曳多选手势；
/// 卡片外观走 `listRowBackground`，不是自己叠一层 `ScrollView`，所以滑动删除、
/// 编辑模式、VoiceOver 的清单语意都还在。
struct BookmarkSelectionList: View {
    var groups: [ReaderBookmarkChapterGroup]
    @Binding var selection: Set<UUID>
    /// 章名用目前的目录解析，不是书签存档时的那份——换源或目录更新后才不会显示旧章名。
    var chapterTitle: (ReaderBookmarkChapterGroup) -> String
    var primaryText: (Bookmark) -> String
    var icon: (Bookmark) -> String
    var dateText: (Bookmark) -> String
    var pageText: (Bookmark) -> String?
    /// 这条标注的笔记；没有笔记回传 nil。
    var noteText: (Bookmark) -> String? = { _ in nil }
    var onSelect: (Bookmark) -> Void
    var onSelectChapter: (ReaderBookmarkChapterGroup) -> Void
    var onDelete: (Bookmark) -> Void
    /// 这条书签的位置是不是对著这台装置读的文字（`ConvertedTextVersions`）。转换书换了
    /// 转换版本后，另一版的书签照列、变灰、不能跳，编辑模式照样能选取删除。
    var indexesReadText: (Bookmark) -> Bool = { _ in true }

    @Environment(\.editMode) private var editMode

    /// 多选期间整张清单只做一件事：选取。卡片与章名的跳转在这时候收起来，
    /// 否则勾选第三张卡片的手指会把 sheet 关掉、跳走。
    private var isEditing: Bool { editMode?.wrappedValue.isEditing ?? false }

    var body: some View {
        List(selection: $selection) {
            ForEach(groups) { group in
                Section {
                    ForEach(group.items) { bm in
                        BookmarkCardRow(
                            icon: icon(bm),
                            primary: primaryText(bm),
                            date: dateText(bm),
                            page: pageText(bm),
                            note: noteText(bm),
                            indexesReadText: indexesReadText(bm),
                            isEditing: isEditing,
                            onSelect: { onSelect(bm) },
                            onDelete: { onDelete(bm) }
                        )
                        .listRowInsets(EdgeInsets(
                            top: DSSpacing.xs, leading: DSSpacing.lg,
                            bottom: DSSpacing.xs, trailing: DSSpacing.lg
                        ))
                        .listRowSeparator(.hidden)
                        .listRowBackground(
                            RoundedRectangle(cornerRadius: DSRadius.lg, style: .continuous)
                                .fill(DSColor.surface)
                                .padding(.vertical, DSSpacing.xs)
                        )
                        .swipeActions(edge: .trailing) {
                            Button(role: .destructive) {
                                onDelete(bm)
                            } label: {
                                Label(localized("删除"), systemImage: "trash")
                            }
                        }
                    }
                } header: {
                    chapterHeader(group)
                }
            }
        }
        .softScrollEdges()
        .listStyle(.plain)
        .scrollContentBackground(.hidden)
    }

    @ViewBuilder
    private func chapterHeader(_ group: ReaderBookmarkChapterGroup) -> some View {
        let title = Text(chapterTitle(group))
            .font(DSFont.title3)
            .foregroundStyle(DSColor.textPrimary)
            .lineLimit(2)
            .multilineTextAlignment(.leading)
            .frame(maxWidth: .infinity, alignment: .leading)
            .contentShape(Rectangle())

        Group {
            if isEditing {
                title.accessibilityAddTraits(.isHeader)
            } else {
                Button { onSelectChapter(group) } label: { title }
                    .buttonStyle(.plain)
                    .accessibilityAddTraits(.isHeader)
                    .accessibilityHint(localized("点两下跳至本章开头"))
            }
        }
        .textCase(nil)
        .listRowInsets(EdgeInsets(
            top: DSSpacing.lg, leading: DSSpacing.lg,
            bottom: DSSpacing.sm, trailing: DSSpacing.lg
        ))
        .listRowBackground(Color.clear)
    }
}

// MARK: - Row

/// 一张书签卡片：图示＋时间＋页码一行，底下是摘录。右上角「⋯」放删除，
/// 和滑动删除是同一个动作的两个入口（手势不好发现，选单好发现）。
private struct BookmarkCardRow: View {
    let icon: String
    let primary: String
    let date: String
    let page: String?
    let note: String?
    let indexesReadText: Bool
    let isEditing: Bool
    let onSelect: () -> Void
    let onDelete: () -> Void

    private var metaText: String {
        guard let page, !page.isEmpty else { return date }
        return "\(date) · \(String(format: localized("第 %@ 页"), page))"
    }

    private var content: some View {
        VStack(alignment: .leading, spacing: DSSpacing.sm) {
            HStack(spacing: DSSpacing.xs) {
                Image(systemName: icon)
                    .font(DSFont.footnote)
                    .accessibilityHidden(true)
                Text(metaText)
                    .font(DSFont.footnote)
            }
            .foregroundStyle(DSColor.textSecondary)

            Text(primary)
                .font(DSFont.body)
                .foregroundStyle(indexesReadText ? DSColor.textPrimary : DSColor.textSecondary)
                .lineLimit(2)
                .multilineTextAlignment(.leading)

            if !indexesReadText {
                Text(localized("建立在这本书另一版的转换文字上，无法跳转"))
                    .font(DSFont.footnote)
                    .foregroundStyle(DSColor.textSecondary)
            }

            if let note, !note.isEmpty {
                Label(note, systemImage: "note.text")
                    .font(DSFont.footnote)
                    .foregroundStyle(DSColor.textSecondary)
                    .lineLimit(2)
                    .accessibilityLabel(String(format: localized("笔记：%@"), note))
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .contentShape(Rectangle())
    }

    var body: some View {
        HStack(alignment: .top, spacing: DSSpacing.sm) {
            if isEditing {
                content
            } else if !indexesReadText {
                // Nothing to jump to: read as one element, with no 「点两下跳至此页」.
                content.accessibilityElement(children: .combine)
                moreMenu
            } else {
                Button(action: onSelect) { content }
                    .buttonStyle(.borderless)
                    .accessibilityLabel("\(primary)，\(metaText)")
                    .accessibilityHint(localized("点两下跳至此页"))

                moreMenu
            }
        }
        .padding(.vertical, DSSpacing.md)
        .padding(.leading, DSSpacing.md)
        .padding(.trailing, isEditing ? DSSpacing.md : DSSpacing.xs)
    }

    private var moreMenu: some View {
        Menu {
            Button(role: .destructive, action: onDelete) {
                Label(localized("删除"), systemImage: "trash")
            }
        } label: {
            Image(systemName: "ellipsis")
                .font(DSFont.footnote)
                .foregroundStyle(DSColor.textSecondary)
                .frame(width: DSLayout.minimumTapTarget, height: DSLayout.minimumTapTarget)
                .contentShape(Rectangle())
        }
        .buttonStyle(.borderless)
        .accessibilityLabel(localized("更多"))
    }
}
