import SwiftUI
import UIKit

/// 单个区域的 CSS 编辑页。写法沿用「孤岛 / Cay」的语义选择器，注入时自动降级成
/// 浏览器 CSS；也能直接写标准浏览器 CSS（选择器原样保留）。
struct ReviewPanelCSSEditorView: View {
    @Environment(\.dismiss) private var dismiss
    private let store = ReviewPanelStyleStore.shared
    let area: ReviewPanelCSSArea
    let initialText: String

    @State private var text: String
    @State private var validationMessage: String?
    @State private var confirmFillExample = false

    init(area: ReviewPanelCSSArea, initialText: String) {
        self.area = area
        self.initialText = initialText
        _text = State(initialValue: initialText)
    }

    private var currentTemplate: ReviewPanelStyleTemplate? {
        store.allTemplates.first { $0.id == store.selectedTemplateID }
    }

    private var isReadOnly: Bool {
        currentTemplate?.isBuiltin ?? false
    }

    var body: some View {
        Form {
            if isReadOnly {
                Section {
                    Text(localized("内置模板只读。复制一份后即可自由编辑。"))
                        .font(DSFont.caption)
                        .foregroundStyle(DSColor.textSecondary)
                    Button {
                        if let template = currentTemplate {
                            store.duplicate(template)
                            text = template.css(for: area)
                        }
                    } label: {
                        SettingsRowLabel(localized("复制并编辑"), systemImage: "plus.square.on.square", role: .action)
                    }
                }
                .interfaceSectionSurface()
            }

            Section {
                TextEditor(text: $text)
                    .font(DSFont.monospaced())
                    .frame(minHeight: DSLayout.readerSVGEditorHeight * 1.6)
                    .accessibilityLabel(area.title)
                    .disabled(isReadOnly)
                Text(String(format: localized("%d 行 · %d 字符"), lineCount, text.count))
                    .font(DSFont.caption)
                    .foregroundStyle(DSColor.textTertiary)
            } header: {
                Text(area.title)
                    .foregroundStyle(DSColor.textSecondary)
            } footer: {
                Text(area.summary)
                    .dsSectionFooter()
            }
            .interfaceSectionSurface()

            if !unsupportedHits.isEmpty {
                Section {
                    ForEach(unsupportedHits, id: \.self) { hit in
                        Label(
                            String(format: localized("「%@」是孤岛专有语法，注入时会被忽略"), hit),
                            systemImage: "exclamationmark.triangle"
                        )
                        .font(DSFont.caption)
                        .foregroundStyle(DSColor.warning)
                    }
                } header: {
                    Text(localized("语法提示"))
                        .foregroundStyle(DSColor.textSecondary)
                }
                .interfaceSectionSurface()
            }

            Section {
                Button {
                    if text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                        text = area.cayExample
                    } else {
                        confirmFillExample = true
                    }
                } label: {
                    SettingsRowLabel(localized("填入孤岛示例"), systemImage: "doc.text", role: .action)
                }
                Button {
                    if let pasted = UIPasteboard.general.string { text = pasted }
                } label: {
                    SettingsRowLabel(localized("从剪贴板贴上"), systemImage: "doc.on.clipboard", role: .action)
                }
                Button(role: .destructive) {
                    text = ""
                } label: {
                    SettingsRowLabel(localized("清空 CSS"), systemImage: "trash", role: .destructive)
                }
            } header: {
                Text(localized("编辑"))
                    .foregroundStyle(DSColor.textSecondary)
            } footer: {
                Text(localized("填入示例会替换整个编辑框；清空该区域的 CSS 可恢复这一区的默认外观。"))
                    .dsSectionFooter()
            }
            .interfaceSectionSurface()

            Section {
                VStack(alignment: .leading, spacing: DSSpacing.xs) {
                    Text(localized("可用选择器"))
                        .font(DSFont.caption)
                        .foregroundStyle(DSColor.textSecondary)
                    Text(area.selectorHint)
                        .font(.system(size: 12, design: .monospaced))
                        .foregroundStyle(DSColor.textPrimary)
                        .textSelection(.enabled)
                }
            } footer: {
                Text(localized("整体直接写声明（如 color: #333;）即可；@dark / @light 分别设定夜间与白天，content 可改标签文字。详见「CSS 说明」。"))
                    .dsSectionFooter()
            }
            .interfaceSectionSurface()
        }
        .softScrollEdges()
        .navigationTitle(area.title)
        .toolbarTitleDisplayMode(.inline)
        .readerGlassSettingsSurface()
        .toolbar {
            ToolbarItem(placement: .confirmationAction) {
                Button(localized("储存")) { save() }
                    .disabled(isReadOnly)
            }
        }
        .alert(
            localized("填入孤岛示例？"),
            isPresented: $confirmFillExample
        ) {
            Button(localized("取消"), role: .cancel) {}
            Button(localized("替换")) { text = area.cayExample }
        } message: {
            Text(localized("会替换整个编辑框的现有内容，且无法自动恢复。"))
        }
        .alert(
            localized("无法储存"),
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

    private var lineCount: Int {
        text.split(separator: "\n").filter { !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }.count
    }

    private var unsupportedHits: [String] {
        let markers = ["{{", "@js", ":regex(", "-cay-bubble", "::match(", "url(asset:", "@if", ":js("]
        return markers.filter { text.contains($0) }
    }

    private func save() {
        guard let template = currentTemplate, !template.isBuiltin else {
            validationMessage = localized("内置模板只读，请先复制并编辑。")
            return
        }
        if text.utf8.count > 60 * 1024 {
            validationMessage = localized("CSS 内容过大，请精简后再储存。")
            return
        }
        store.setCSS(text, for: area, on: template.id)
        dismiss()
    }
}

private extension ReviewPanelCSSArea {
    var selectorHint: String {
        switch self {
        case .panel:
            return "整体声明：font-size / color / background / border-radius / padding / line-height\n.card（评论卡片）\n@dark { … } / @light { … }"
        case .comment:
            return ".quote .avatar .user .badge .author\n.likes .likes-icon .likes-value .reply-to\n.text .time .timestamp .location\n.reply-count .reply-icon .reply-count-value .card"
        case .hot:
            return ".label（标签文字用 content 改）\n.user（写了才显示用户名）\n整体：background / border / border-radius / line-clamp"
        case .chapterNote:
            return ".header .count .more .header-row\n.user .likes .text .avatar\n.note .note-label .note-author .note-text .note-avatar"
        }
    }
}

#Preview {
    NavigationStack {
        ReviewPanelCSSEditorView(area: .comment, initialText: "")
    }
}
