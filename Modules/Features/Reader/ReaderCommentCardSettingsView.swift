import SwiftUI
import UIKit

/// 气泡设置 › 本章说 / 作者说 / 神评论: the template one kind of review card is redrawn from.
struct ReaderCommentCardSettingsView: View {
    @Bindable private var settings = GlobalSettings.shared
    let kind: ReaderCommentCardKind
    /// 汇入样式, handed to the first-level document picker; nil hides it.
    var onOpenImporter: (() -> Void)?
    @State private var editorDraft: CommentCardStyleDraft?
    @State private var stylePendingDeletion: ReaderCommentCardCustomStyle?

    var body: some View {
        Form {
            Section(header: Text(localized("预览")).foregroundStyle(DSColor.textSecondary)) {
                CommentCardTemplatePreview(
                    source: selectedSource,
                    kind: kind,
                    colorHex: selectedStyle?.colorHex(isNight: isNightReading),
                    isNight: isNightReading
                )
            }
            .interfaceSectionSurface()

            Section(header: Text(localized("样式")).foregroundStyle(DSColor.textSecondary)) {
                Picker(localized("样式"), selection: selectionBinding) {
                    Text(localized("玻璃")).tag(UUID?.none)
                    ForEach(styles) { style in
                        Text(style.name).tag(UUID?.some(style.id))
                    }
                }
                .pickerStyle(.inline)
                .labelsHidden()
            }
            .interfaceSectionSurface()

            Section {
                Toggle(localized("优先使用选取的样式"), isOn: prefersSelectedBinding)
                    .foregroundStyle(DSColor.textPrimary)
            } header: {
                Text(localized("显示偏好"))
                    .foregroundStyle(DSColor.textSecondary)
            } footer: {
                Text(localized("开启后以选取的样式重绘卡片；关闭或卡片无法辨识时，显示来源配置提供的样式。"))
                    .dsSectionFooter()
            }
            .interfaceSectionSurface()

            Section(header: Text(localized("管理")).foregroundStyle(DSColor.textSecondary)) {
                Button(action: openNewStyleEditor) {
                    SettingsRowLabel(localized("新建样式"), systemImage: "plus.circle", role: .action)
                }
                if let onOpenImporter {
                    Button(action: onOpenImporter) {
                        SettingsRowLabel(localized("汇入样式"), systemImage: "square.and.arrow.down", role: .action)
                    }
                }
                exportLink
                if let selectedStyle {
                    Button {
                        editorDraft = CommentCardStyleDraft(kind: kind, style: selectedStyle, source: selectedStyle.svg)
                    } label: {
                        SettingsRowLabel(localized("编辑目前样式"), systemImage: "pencil", role: .action)
                    }
                    Button(role: .destructive) {
                        stylePendingDeletion = selectedStyle
                    } label: {
                        SettingsRowLabel(localized("删除目前样式"), systemImage: "trash", role: .destructive)
                    }
                }
            }
            .interfaceSectionSurface()
        }
        .softScrollEdges()
        .navigationTitle(kind.localizedTitle)
        .toolbarTitleDisplayMode(.inline)
        .readerGlassSettingsSurface()
        .navigationDestination(item: $editorDraft) { draft in
            CommentCardStyleEditorView(draft: draft)
        }
        .alert(
            localized("删除目前样式？"),
            isPresented: Binding(
                get: { stylePendingDeletion != nil },
                set: { if !$0 { stylePendingDeletion = nil } }
            ),
            presenting: stylePendingDeletion
        ) { style in
            Button(localized("删除目前样式"), role: .destructive) {
                settings.deleteCommentCardStyle(id: style.id)
                stylePendingDeletion = nil
            }
            Button(localized("取消"), role: .cancel) {}
        } message: { style in
            Text(String(format: localized("「%@」会被永久删除，此操作无法复原。"), style.name))
        }
    }

    // MARK: - Selection

    private var styles: [ReaderCommentCardCustomStyle] {
        settings.commentCardStyles(of: kind)
    }

    /// The custom template picked for this kind; nil is 玻璃, as is a pick deleted since.
    private var selectedStyle: ReaderCommentCardCustomStyle? {
        guard let id = settings.commentCardChoices[kind].selectedStyleID else { return nil }
        return styles.first { $0.id == id }
    }

    private var selectedSource: String {
        selectedStyle?.svg ?? ReviewCardTemplate.builtinSource(for: kind)
    }

    /// The preview is drawn on the reading theme, as the card would be.
    private var isNightReading: Bool {
        ReaderTheme.loadPersisted() == .night
    }

    private var selectionBinding: Binding<UUID?> {
        Binding(
            get: { selectedStyle?.id },
            set: { settings.selectCommentCardStyle(id: $0, for: kind) }
        )
    }

    private var prefersSelectedBinding: Binding<Bool> {
        Binding(
            get: { settings.commentCardChoices[kind].prefersSelectedStyle },
            set: { settings.setCommentCardPrefersSelectedStyle($0, for: kind) }
        )
    }

    // MARK: - Export

    /// A template with its own colours travels as a package, which keeps them and its kind;
    /// anything else as the SVG.
    @ViewBuilder
    private var exportLink: some View {
        let label = SettingsRowLabel(localized("汇出当前样式"), systemImage: "square.and.arrow.up", role: .action)
        if let style = selectedStyle, style.dayColor != nil || style.nightColor != nil,
           let payload = Self.packageExport(style) {
            ShareLink(item: payload, preview: SharePreview(style.name)) { label }
        } else {
            let name = selectedStyle?.name ?? localized("玻璃")
            ShareLink(item: CommentStyleSVGExport(name: name, svg: selectedSource), preview: SharePreview(name)) {
                label
            }
        }
    }

    private static func packageExport(_ style: ReaderCommentCardCustomStyle) -> CommentStyleJSONExport? {
        do {
            return try CommentStyleJSONExport(card: style)
        } catch {
            AppLogger.error("comment card package export not encoded", error: error)
            return nil
        }
    }

    // MARK: - Editor

    /// A new template starts from the one picked now, so 玻璃 can be adjusted rather than
    /// rewritten.
    private func openNewStyleEditor() {
        editorDraft = CommentCardStyleDraft(kind: kind, style: nil, source: selectedSource)
    }
}

struct CommentCardStyleDraft: Identifiable, Hashable {
    let id = UUID()
    let kind: ReaderCommentCardKind
    /// The template being edited; nil makes a new one.
    let style: ReaderCommentCardCustomStyle?
    /// What the SVG field starts with.
    let source: String

    static func == (lhs: Self, rhs: Self) -> Bool { lhs.id == rhs.id }
    func hash(into hasher: inout Hasher) { hasher.combine(id) }
}

/// 新建样式 / 编辑样式 for a card template: its name, SVG and `${color}`, with the sample card
/// drawn by day and by night. Leaving without 储存 keeps the template as it was.
struct CommentCardStyleEditorView: View {
    @Environment(\.dismiss) private var dismiss
    @Bindable private var settings = GlobalSettings.shared
    let draft: CommentCardStyleDraft

    @State private var name: String
    @State private var svg: String
    @State private var dayColor: String?
    @State private var nightColor: String?
    @State private var validationMessage: String?

    init(draft: CommentCardStyleDraft) {
        self.draft = draft
        _name = State(initialValue: draft.style?.name ?? "")
        _svg = State(initialValue: draft.source)
        _dayColor = State(initialValue: draft.style?.dayColor)
        _nightColor = State(initialValue: draft.style?.nightColor)
    }

    var body: some View {
        Form {
            Section(header: Text(localized("样式名称")).foregroundStyle(DSColor.textSecondary)) {
                TextField(localized("样式名称"), text: $name)
            }
            .interfaceSectionSurface()

            Section(header: Text(localized("预览")).foregroundStyle(DSColor.textSecondary)) {
                CommentCardTemplatePreview(source: svg, kind: draft.kind, colorHex: dayColor, isNight: false)
                CommentCardTemplatePreview(source: svg, kind: draft.kind, colorHex: nightColor, isNight: true)
            }
            .interfaceSectionSurface()

            Section {
                TextEditor(text: $svg)
                    .font(DSFont.monospaced())
                    .frame(minHeight: DSLayout.readerSVGEditorHeight)
                    .accessibilityLabel(localized("SVG 模板"))
                Button {
                    if let pasted = UIPasteboard.general.string { svg = pasted }
                } label: {
                    SettingsRowLabel(localized("从剪贴簿贴上 SVG"), systemImage: "doc.on.clipboard", role: .action)
                }
            } header: {
                Text(localized("SVG 模板")).foregroundStyle(DSColor.textSecondary)
            } footer: {
                Text(localized("可用 ${title}、${count}、${num}、${user}、${likes}、${content}、${color} 与 ${accent}（阅读背景的强调色）；带 data-yd-repeat 的元素会为每则评论重复一次，带 data-yd-glass 的元素会画成系统玻璃。"))
                    .dsSectionFooter()
            }
            .interfaceSectionSurface()

            Section {
                OptionalHexColorRows(
                    toggleTitle: localized("自订白天颜色"),
                    pickerTitle: localized("白天颜色"),
                    hex: $dayColor,
                    initialColor: ReaderTheme.white.uiTextColor
                )
                OptionalHexColorRows(
                    toggleTitle: localized("自订夜间颜色"),
                    pickerTitle: localized("夜间颜色"),
                    hex: $nightColor,
                    initialColor: ReaderTheme.night.uiTextColor
                )
            } header: {
                Text(localized("颜色")).foregroundStyle(DSColor.textSecondary)
            } footer: {
                Text(localized("未设置时 ${color} 跟随阅读文字颜色。"))
                    .dsSectionFooter()
            }
            .interfaceSectionSurface()
        }
        .softScrollEdges()
        .navigationTitle(localized(draft.style == nil ? "新建样式" : "编辑样式"))
        .toolbarTitleDisplayMode(.inline)
        .readerGlassSettingsSurface()
        .toolbar {
            ToolbarItem(placement: .confirmationAction) {
                Button(action: save) {
                    Image(systemName: "checkmark")
                }
                .disabled(svg.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                .accessibilityLabel(localized("储存"))
            }
        }
        .alert(
            localized("无法储存样式"),
            isPresented: Binding(
                get: { validationMessage != nil },
                set: { if !$0 { validationMessage = nil } }
            )
        ) {
            Button(localized("确定"), role: .cancel) {}
        } message: {
            Text(validationMessage ?? "")
        }
    }

    private func save() {
        let source = svg.trimmingCharacters(in: .whitespacesAndNewlines)
        do {
            _ = try ReviewCardTemplate(source: source)
        } catch {
            validationMessage = error.localizedDescription
            return
        }
        let trimmedName = name.trimmingCharacters(in: .whitespacesAndNewlines)
        settings.upsertCommentCardStyle(ReaderCommentCardCustomStyle(
            id: draft.style?.id ?? UUID(),
            kind: draft.kind,
            name: trimmedName.isEmpty ? localized("自订模板") : trimmedName,
            svg: source,
            updatedAt: draft.style?.updatedAt,
            dayColor: dayColor,
            nightColor: nightColor
        ))
        dismiss()
    }
}

#Preview("本章说") {
    NavigationStack {
        ReaderCommentCardSettingsView(kind: .chapterSay, onOpenImporter: {})
    }
}

#Preview("Card editor") {
    NavigationStack {
        CommentCardStyleEditorView(draft: CommentCardStyleDraft(
            kind: .hotComment,
            style: nil,
            source: ReviewCardTemplate.builtinSource(for: .hotComment)
        ))
    }
}
