import CoreTransferable
import SwiftUI
import UniformTypeIdentifiers

/// 段评与互动样式：单独一个原生设置页，自订段评网页、评论、热评、本章说 / 作者说的 CSS。
///
/// 样式分区与内置示例取自「孤岛 / Cay」：每个区域一份 CSS，可存多套、随时切换、
/// 汇入汇出。CSS 经 `ReviewPanelCSSBridge` 降级后注入段评网页（WKWebView）。
struct ReviewPanelStyleSettingsView: View {
    private let store = ReviewPanelStyleStore.shared

    @State private var isImporting = false
    @State private var importMessage: String?
    @State private var editorArea: ReviewPanelCSSArea?
    @State private var templatePendingDeletion: ReviewPanelStyleTemplate?
    @State private var renameDraft: RenameDraft?
    @State private var showGuides = false

    var body: some View {
        Form {
            Section {
                Toggle(localized("启用自订段评样式"), isOn: enabledBinding)
                    .foregroundStyle(DSColor.textPrimary)
            } header: {
                Text(localized("样式开关"))
                    .foregroundStyle(DSColor.textSecondary)
            } footer: {
                Text(localized("开启后，所有点开评论弹出的面板（段评、本章说、热评、作者说等）都会套用这套孤岛样式；关闭则恢复书源网页原本的外观。"))
                    .dsSectionFooter()
            }
            .interfaceSectionSurface()

            Section {
                ForEach(store.allTemplates) { template in
                    templateRow(template)
                }
            } header: {
                Text(localized("样式模板"))
                    .foregroundStyle(DSColor.textSecondary)
            } footer: {
                Text(localized("内置模板取自孤岛的四套示例，只读；复制一份即可自由修改。"))
                    .dsSectionFooter()
            }
            .interfaceSectionSurface()

            Section {
                ForEach(ReviewPanelCSSArea.allCases) { area in
                    Button {
                        editorArea = area
                    } label: {
                        HStack(spacing: DSSpacing.sm) {
                            Image(systemName: area.systemImage)
                                .foregroundStyle(DSColor.accent)
                                .frame(width: 24)
                            VStack(alignment: .leading, spacing: 2) {
                                Text(area.title)
                                    .foregroundStyle(DSColor.textPrimary)
                                Text(currentTemplate?.css(for: area).trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false
                                     ? String(format: localized("已设置 %d 行"), lineCount(of: area))
                                     : localized("未设置"))
                                    .font(DSFont.caption)
                                    .foregroundStyle(DSColor.textSecondary)
                            }
                            Spacer()
                            Image(systemName: "chevron.right")
                                .font(DSFont.caption)
                                .foregroundStyle(DSColor.textTertiary)
                        }
                    }
                }
            } header: {
                Text(localized("分区 CSS"))
                    .foregroundStyle(DSColor.textSecondary)
            } footer: {
                Text(localized("四个区域各自编辑、合成一份样式，套用到所有点开评论弹出的面板；后写的样式覆盖先写的。"))
                    .dsSectionFooter()
            }
            .interfaceSectionSurface()

            Section {
                Button {
                    store.makeBlankTemplate()
                } label: {
                    SettingsRowLabel(localized("新建空白样式"), systemImage: "plus.circle", role: .action)
                }
                Button {
                    isImporting = true
                } label: {
                    SettingsRowLabel(localized("汇入样式"), systemImage: "square.and.arrow.down", role: .action)
                }
                exportLink
                Button {
                    showGuides = true
                } label: {
                    SettingsRowLabel(localized("CSS 说明"), systemImage: "book.pages", role: .action)
                }
            } header: {
                Text(localized("管理"))
                    .foregroundStyle(DSColor.textSecondary)
            } footer: {
                Text(localized("汇入支持本 App 汇出的 .json 样式包，也可直接汇入一份纯 CSS 文本（当作评论列表样式）。"))
                    .dsSectionFooter()
            }
            .interfaceSectionSurface()
        }
        .softScrollEdges()
        .navigationTitle(localized("段评与互动样式"))
        .toolbarTitleDisplayMode(.inline)
        .readerGlassSettingsSurface()
        .navigationDestination(item: $editorArea) { area in
            ReviewPanelCSSEditorView(
                area: area,
                initialText: currentTemplate?.css(for: area) ?? ""
            )
        }
        .navigationDestination(isPresented: $showGuides) {
            ReviewPanelCSSGuideView()
        }
        .copiedFileImporter(
            isPresented: $isImporting,
            allowedContentTypes: [.json, .plainText, .data]
        ) { result in
            switch result {
            case .success(let url):
                do {
                    let data = try Data(contentsOf: url)
                    let name = url.deletingPathExtension().lastPathComponent
                    let template = try store.importData(data, fileName: name)
                    importMessage = String(format: localized("已汇入「%@」"), template.name)
                } catch {
                    importMessage = error.localizedDescription
                }
            case .failure(let error):
                importMessage = error.localizedDescription
            }
        }
        .alert(
            localized("汇入样式"),
            isPresented: Binding(
                get: { importMessage != nil },
                set: { if !$0 { importMessage = nil } }
            )
        ) {
            Button(localized("确定"), role: .cancel) {}
        } message: {
            Text(importMessage ?? "")
        }
        .alert(
            localized("删除样式？"),
            isPresented: Binding(
                get: { templatePendingDeletion != nil },
                set: { if !$0 { templatePendingDeletion = nil } }
            ),
            presenting: templatePendingDeletion
        ) { template in
            Button(localized("删除样式"), role: .destructive) {
                store.delete(id: template.id)
                templatePendingDeletion = nil
            }
            Button(localized("取消"), role: .cancel) {}
        } message: { template in
            Text(String(format: localized("「%@」会被永久删除，此操作无法复原。"), template.name))
        }
        .sheet(item: $renameDraft) { draft in
            RenameTemplateView(draft: draft)
        }
    }

    // MARK: - 模板行

    @ViewBuilder
    private func templateRow(_ template: ReviewPanelStyleTemplate) -> some View {
        let selected = store.selectedTemplateID == template.id && store.isEnabled
        Button {
            store.select(id: template.id)
        } label: {
            HStack(spacing: DSSpacing.sm) {
                Image(systemName: selected ? "checkmark.circle.fill" : "circle")
                    .foregroundStyle(selected ? DSColor.accent : DSColor.textTertiary)
                VStack(alignment: .leading, spacing: 2) {
                    Text(template.name)
                        .foregroundStyle(DSColor.textPrimary)
                    Text(template.isBuiltin ? localized("内置 · 只读") : localized("自订"))
                        .font(DSFont.caption)
                        .foregroundStyle(DSColor.textSecondary)
                }
                Spacer()
            }
        }
        .swipeActions(edge: .trailing, allowsFullSwipe: false) {
            Button {
                store.duplicate(template)
            } label: {
                Label(localized("复制"), systemImage: "plus.square.on.square")
            }
            .tint(DSColor.accent)
            if !template.isBuiltin {
                Button {
                    renameDraft = RenameDraft(id: template.id, name: template.name)
                } label: {
                    Label(localized("重命名"), systemImage: "pencil")
                }
                Button(role: .destructive) {
                    templatePendingDeletion = template
                } label: {
                    Label(localized("删除"), systemImage: "trash")
                }
            }
        }
        .contextMenu {
            Button {
                store.duplicate(template)
            } label: {
                Label(localized("复制并编辑"), systemImage: "plus.square.on.square")
            }
            if !template.isBuiltin {
                Button {
                    renameDraft = RenameDraft(id: template.id, name: template.name)
                } label: {
                    Label(localized("重命名"), systemImage: "pencil")
                }
            }
        }
    }

    // MARK: - 汇出

    @ViewBuilder
    private var exportLink: some View {
        let label = SettingsRowLabel(localized("汇出当前样式"), systemImage: "square.and.arrow.up", role: .action)
        if let template = currentTemplate,
           let payload = try? ReviewPanelStyleExport(template: template) {
            ShareLink(item: payload, preview: SharePreview(template.name)) { label }
        } else {
            label.opacity(0.5)
        }
    }

    private var currentTemplate: ReviewPanelStyleTemplate? {
        store.allTemplates.first { $0.id == store.selectedTemplateID }
    }

    private func lineCount(of area: ReviewPanelCSSArea) -> Int {
        currentTemplate?.css(for: area)
            .split(separator: "\n")
            .filter { !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
            .count ?? 0
    }

    private var enabledBinding: Binding<Bool> {
        Binding(
            get: { store.isEnabled },
            set: { store.isEnabled = $0 }
        )
    }
}

// MARK: - 重命名

struct RenameDraft: Identifiable {
    let id: UUID
    let name: String
}

struct RenameTemplateView: View {
    @Environment(\.dismiss) private var dismiss
    private let store = ReviewPanelStyleStore.shared
    let draft: RenameDraft
    @State private var name: String

    init(draft: RenameDraft) {
        self.draft = draft
        _name = State(initialValue: draft.name)
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField(localized("样式名称"), text: $name)
                }
                .interfaceSectionSurface()
            }
            .navigationTitle(localized("重命名"))
            .toolbarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(localized("取消")) { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button(localized("储存")) {
                        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
                        if !trimmed.isEmpty { store.rename(id: draft.id, name: trimmed) }
                        dismiss()
                    }
                }
            }
        }
    }
}

// MARK: - 汇出文件

struct ReviewPanelStyleExport: Transferable {
    let filename: String
    let data: Data

    init(template: ReviewPanelStyleTemplate) throws {
        filename = ReaderStyleExportFilename.make(template.name, pathExtension: "json")
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        data = try encoder.encode(ReviewPanelStyleTemplate.PackageFile(template))
    }

    static var transferRepresentation: some TransferRepresentation {
        FileRepresentation(exportedContentType: .json) { payload in
            let url = FileManager.default.temporaryDirectory.appendingPathComponent(payload.filename)
            try payload.data.write(to: url, options: .atomic)
            return SentTransferredFile(url)
        }
    }
}

#Preview {
    NavigationStack {
        ReviewPanelStyleSettingsView()
    }
}
