import SwiftUI

/// 段落笔记的编辑页。
///
/// 导览列走原生 chrome（inline 标题＋trailing 的删除／完成），内容区依序是
/// 时间、被标注的原文引用、输入区——开启即聚焦，键盘直接弹出。
///
/// `isEditable == false` 是「Pro 过期但这段本来就有笔记」的情况：内容照样读得到，
/// 只是不能改，底下换成一条续订入口。
struct ReaderNoteEditorView: View {
    /// 被标注的原文。
    let excerpt: String
    /// 这条笔记的时间（新笔记为当下）。
    let date: Date
    /// 已有笔记时才显示删除钮。
    let showsDelete: Bool
    /// Pro 生效时才可编辑。
    let isEditable: Bool
    let onSave: (String) -> Void
    let onDelete: () -> Void
    let onUpgrade: () -> Void
    let onClose: () -> Void

    @State private var text: String
    @FocusState private var isFocused: Bool

    init(
        excerpt: String,
        note: String,
        date: Date,
        showsDelete: Bool,
        isEditable: Bool,
        onSave: @escaping (String) -> Void,
        onDelete: @escaping () -> Void,
        onUpgrade: @escaping () -> Void,
        onClose: @escaping () -> Void
    ) {
        self.excerpt = ReaderBookmarkExcerpt.plain(excerpt)
        self.date = date
        self.showsDelete = showsDelete
        self.isEditable = isEditable
        self.onSave = onSave
        self.onDelete = onDelete
        self.onUpgrade = onUpgrade
        self.onClose = onClose
        _text = State(initialValue: note)
    }

    private static let timeFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateStyle = .none
        f.timeStyle = .short
        return f
    }()

    private var timeText: String {
        Self.timeFormatter.string(from: date)
    }

    var body: some View {
        NavigationStack {
            VStack(alignment: .leading, spacing: DSSpacing.lg) {
                Text(timeText)
                    .font(DSFont.subheadline)
                    .foregroundStyle(DSColor.textSecondary)

                excerptQuote

                if isEditable {
                    editor
                } else {
                    readOnlyNote
                }
            }
            .padding(.horizontal, DSSpacing.lg)
            .padding(.top, DSSpacing.md)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
            .background(DSColor.background.ignoresSafeArea())
            .navigationTitle(localized("笔记"))
            .toolbarTitleDisplayMode(.inline)
            .toolbar { toolbarContent }
        }
        .onAppear {
            guard isEditable else { return }
            isFocused = true
        }
    }

    @ToolbarContentBuilder
    private var toolbarContent: some ToolbarContent {
        if isEditable {
            ToolbarItemGroup(placement: .topBarTrailing) {
                if showsDelete {
                    Button(role: .destructive) {
                        onDelete()
                    } label: {
                        Image(systemName: "trash")
                    }
                    .accessibilityLabel(localized("删除笔记"))
                }

                Button {
                    onSave(text)
                } label: {
                    Image(systemName: "checkmark")
                }
                .accessibilityLabel(localized("完成"))
            }
        } else {
            // 唯读时没有东西可存，所以是「关闭」而不是「完成」，放 leading。
            ToolbarItem(placement: .topBarLeading) {
                Button {
                    onClose()
                } label: {
                    Image(systemName: "xmark")
                }
                .accessibilityLabel(localized("关闭"))
            }
        }
    }

    // MARK: - 唯读（Pro 过期）

    private var readOnlyNote: some View {
        VStack(alignment: .leading, spacing: DSSpacing.lg) {
            Text(text)
                .font(DSFont.body)
                .foregroundStyle(DSColor.textPrimary)
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: .infinity, alignment: .leading)
                .textSelection(.enabled)

            Button {
                onUpgrade()
            } label: {
                Label(localized("订阅 Pro 继续编辑笔记"), systemImage: "lock.fill")
                    .font(DSFont.subheadline)
                    .frame(maxWidth: .infinity, minHeight: DSLayout.minimumTapTarget)
            }
            .buttonStyle(.onAccentProminent)

            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
    }

    // MARK: - 原文引用

    /// 灰线用 `overlay` 挂在文字上，不是并排放进 HStack：`Capsule` 没有固有高度，
    /// 并排时会被撑到整个可用高度（输入区有多高它就有多长）。挂成 overlay 之后
    /// 它的尺寸就等于这段引用文字的实际高度。
    private var excerptQuote: some View {
        Text(excerpt)
            .font(DSFont.subheadline)
            .foregroundStyle(DSColor.textPrimary)
            .fixedSize(horizontal: false, vertical: true)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.leading, DSSpacing.md + DSLayout.readerNoteQuoteBarWidth)
            .overlay(alignment: .leading) {
                Capsule()
                    .fill(DSColor.border)
                    .frame(width: DSLayout.readerNoteQuoteBarWidth)
                    .accessibilityHidden(true)
            }
            .accessibilityElement(children: .combine)
            .accessibilityLabel(localized("标注的原文"))
            .accessibilityValue(excerpt)
    }

    // MARK: - 输入区

    /// 用 `TextEditor` 而不是多行 `TextField`：输入区要占满剩下的整个版面，
    /// 点空白处也要能回到键盘——`TextField` 的可点区只有文字本身那几行高。
    private var editor: some View {
        TextEditor(text: $text)
            .font(DSFont.body)
            .scrollContentBackground(.hidden)
            .focused($isFocused)
            // TextEditor 内建有一圈文字容器内距，扣掉后左缘才和上面的引用文字对齐。
            .padding(.leading, -DSSpacing.xs)
            .overlay(alignment: .topLeading) {
                if text.isEmpty {
                    Text(localized("新增笔记…"))
                        .font(DSFont.body)
                        .foregroundStyle(DSColor.textSecondary)
                        .padding(.top, DSSpacing.sm)
                        .allowsHitTesting(false)
                        .accessibilityHidden(true)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
            .accessibilityLabel(localized("笔记内容"))
    }
}

#Preview("新笔记") {
    Color.clear
        .sheet(isPresented: .constant(true)) {
            ReaderNoteEditorView(
                excerpt: "那现在到底是什么状况？我的脑中忽然变得一片混乱。如果能再重看一次《灭活法》，我就能更确定了。",
                note: "",
                date: Date(),
                showsDelete: false,
                isEditable: true,
                onSave: { _ in },
                onDelete: {},
                onUpgrade: {},
                onClose: {}
            )
        }
}

#Preview("已有笔记") {
    Color.clear
        .sheet(isPresented: .constant(true)) {
            ReaderNoteEditorView(
                excerpt: "那现在到底是什么状况？我的脑中忽然变得一片混乱。",
                note: "这里的伏笔对应第三章的实验记录。",
                date: Date(),
                showsDelete: true,
                isEditable: true,
                onSave: { _ in },
                onDelete: {},
                onUpgrade: {},
                onClose: {}
            )
        }
}

#Preview("Pro 过期唯读") {
    Color.clear
        .sheet(isPresented: .constant(true)) {
            ReaderNoteEditorView(
                excerpt: "那现在到底是什么状况？我的脑中忽然变得一片混乱。",
                note: "这里的伏笔对应第三章的实验记录。",
                date: Date(),
                showsDelete: false,
                isEditable: false,
                onSave: { _ in },
                onDelete: {},
                onUpgrade: {},
                onClose: {}
            )
        }
}
