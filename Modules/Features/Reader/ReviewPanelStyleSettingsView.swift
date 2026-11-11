import CoreTransferable
import SwiftUI
import UniformTypeIdentifiers

/// 段评与互动样式：一页两态。
///
/// - 「原生玻璃卡片」：SwiftUI 画的评论卡片，这里每一项参数都真正生效，带即时预览。
/// - 「书源原网页」：旧的孤岛 / Cay 分区 CSS、四套内置模板、汇入汇出，全套保留，
///   但只对 WKWebView 里的书源网页生效（原生卡片不读 CSS）。
///
/// 两态互斥显示，同一时刻用户只看到一套控件，不会摆着一堆点了没反应的东西；
/// 旧样式数据一个不丢，切回原网页模式随时继续用。
struct ReviewPanelStyleSettingsView: View {
    private let store = ReviewPanelStyleStore.shared
    @Bindable private var native = NativeReviewPanelStyleStore.shared
    @Bindable private var settings = GlobalSettings.shared
    @Environment(\.colorScheme) private var colorScheme

    @State private var isImporting = false
    @State private var importMessage: String?
    @State private var editorArea: ReviewPanelCSSArea?
    @State private var templatePendingDeletion: ReviewPanelStyleTemplate?
    @State private var renameDraft: RenameDraft?
    @State private var showGuides = false
    @State private var showFullPreview = false

    var body: some View {
        Form {
            modeSection

            if native.displayMode == .native {
                nativePreviewSection
                nativeAppearanceSection
                nativeTypographySection
                nativeContentSection
                nativeRepliesSection
                bridgeSection
            } else {
                webNoticeSection
                webEnabledSection
                webTemplatesSection
                webCSSSection
                webManageSection
            }
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
        .sheet(isPresented: $showFullPreview) {
            // 不要 NavigationStack / 导航栏：导航栏自带一层不透明底，
            // 顶部会立刻变成一条白边，玻璃感就断了。下拉即可关闭。
            NativeReviewPanelView(
                title: localized("段评"),
                paragraphLabel: localized("第 109 段"),
                comments: ReviewPanelSampleData.paragraphComments
            )
            .presentationDetents([.large])
            .presentationDragIndicator(.visible)
            .presentationBackground(.ultraThinMaterial)
        }
    }

    // MARK: - 显示模式

    private var modeSection: some View {
        Section {
            Picker(localized("显示模式"), selection: $native.displayMode) {
                ForEach(NativeReviewDisplayMode.allCases) { mode in
                    Text(mode.title).tag(mode)
                }
            }
            .pickerStyle(.segmented)
        } header: {
            Text(localized("显示模式"))
                .foregroundStyle(DSColor.textSecondary)
        } footer: {
            Text(native.displayMode.caption).dsSectionFooter()
        }
        .interfaceSectionSurface()
    }

    // MARK: - 原生玻璃卡片：真正生效的参数

    private var nativePreviewSection: some View {
        Section {
            NativeReviewPanelView(
                title: localized("段评"),
                paragraphLabel: localized("第 109 段"),
                comments: ReviewPanelSampleData.paragraphComments
            )
            .frame(height: 300)
            // 预览里也铺同一层底色：拖「玻璃浓淡」时能立刻看到明暗变化，
            // 不至于变成一个看不出效果的滑杆。真实面板还要再叠 ultraThinMaterial。
            .background {
                Rectangle().fill(
                    ParagraphReviewVeil.color(
                        for: colorScheme,
                        opacity: settings.reviewSheetOpacity
                    )
                )
            }
            .allowsHitTesting(false)
            .listRowInsets(EdgeInsets())
            .listRowBackground(Color.clear)

            Button {
                showFullPreview = true
            } label: {
                SettingsRowLabel(
                    localized("全屏预览"),
                    systemImage: "arrow.up.left.and.arrow.down.right",
                    role: .action
                )
            }
        } header: {
            Text(localized("效果预览"))
                .foregroundStyle(DSColor.textSecondary)
        } footer: {
            Text(localized("预览随下面的参数即时变化；全屏预览可上下滚动看完整评论。"))
                .dsSectionFooter()
        }
        .interfaceSectionSurface()
    }

    private var nativeAppearanceSection: some View {
        Section {
            sliderRow(
                title: localized("玻璃浓淡"),
                value: $settings.reviewSheetOpacity,
                range: GlobalSettings.reviewSheetOpacityRange,
                step: 0.05
            )
            sliderRow(title: localized("卡片不透明度"), value: $native.cardOpacity, range: 0...0.25, step: 0.01)
            sliderRow(title: localized("卡片圆角"), value: $native.cornerRadius, range: 0...28, step: 1)
            sliderRow(title: localized("头像大小"), value: $native.avatarSize, range: 20...60, step: 2)
        } header: {
            Text(localized("面板外观"))
                .foregroundStyle(DSColor.textSecondary)
        } footer: {
            Text(localized("玻璃浓淡与「外观 › 界面效果」里的是同一个值，两边改动会同步。"))
                .dsSectionFooter()
        }
        .interfaceSectionSurface()
    }

    private var nativeTypographySection: some View {
        Section {
            sliderRow(title: localized("正文字号"), value: $native.contentFontSize, range: 12...22, step: 0.5)
            sliderRow(title: localized("昵称字号"), value: $native.nameFontSize, range: 10...20, step: 0.5)
            sliderRow(title: localized("时间 / 信息字号"), value: $native.metaFontSize, range: 9...16, step: 0.5)
            sliderRow(title: localized("正文行距"), value: $native.lineSpacing, range: 0...14, step: 1)
        } header: {
            Text(localized("文字"))
                .foregroundStyle(DSColor.textSecondary)
        } footer: {
            Text(localized("桥接开启时，所选样式模板的字号 / 行距 / 字体会覆盖这里的数值。"))
                .dsSectionFooter()
        }
        .interfaceSectionSurface()
    }

    private var nativeContentSection: some View {
        Section {
            Toggle(localized("显示等级头衔"), isOn: $native.showsLevel)
            Toggle(localized("显示时间 · IP"), isOn: $native.showsMeta)
            Toggle(localized("显示段落原文引用"), isOn: $native.showsQuote)
            Toggle(localized("显示配图"), isOn: $native.showsImages)
            Toggle(localized("显示点赞数"), isOn: $native.showsLikes)
            Toggle(localized("显示语音评论"), isOn: $native.showsVoice)
        } header: {
            Text(localized("显示内容"))
                .foregroundStyle(DSColor.textSecondary)
        } footer: {
            Text(localized("书源没给这项数据时本来就不显示；关掉只是把它藏起来，不影响抓取。"))
                .dsSectionFooter()
        }
        .interfaceSectionSurface()
    }

    private var nativeRepliesSection: some View {
        Section {
            Stepper(value: $native.collapsedReplyLimit, in: 0...10) {
                Text(String(format: localized("折叠时显示 %d 条回复"), native.collapsedReplyLimit))
                    .font(DSFont.body)
                    .foregroundStyle(DSColor.textPrimary)
            }
            Toggle(localized("默认展开楼中楼"), isOn: $native.repliesDefaultExpanded)
        } header: {
            Text(localized("楼中楼"))
                .foregroundStyle(DSColor.textSecondary)
        } footer: {
            Text(localized("超过这个条数会显示「展开其余 N 条回复」；只有一层回复也能点开再收回。"))
                .dsSectionFooter()
        }
        .interfaceSectionSurface()
    }

    private var bridgeSection: some View {
        Section {
            Toggle(localized("让样式模板也影响卡片字号"), isOn: $native.typographyBridgeEnabled)
            if native.typographyBridgeEnabled {
                Picker(localized("桥接来源"), selection: Binding(
                    get: { native.bridgeTemplateID ?? "" },
                    set: { native.bridgeTemplateID = $0.isEmpty ? nil : $0 }
                )) {
                    Text(localized("跟随当前模板")).tag("")
                    ForEach(store.allTemplates) { template in
                        Text(template.name).tag(template.id.uuidString)
                    }
                }
            }
        } header: {
            Text(localized("样式模板桥接"))
                .foregroundStyle(DSColor.textSecondary)
        } footer: {
            Text(localized("只取模板里的字号、行距、字体、字距；颜色、背景、标签文字一律不映射，统一玻璃外观不会被 CSS 破坏。默认关闭，旧模板一项都不用改。"))
                .dsSectionFooter()
        }
        .interfaceSectionSurface()
    }

    @ViewBuilder
    private func sliderRow(
        title: String,
        value: Binding<Double>,
        range: ClosedRange<Double>,
        step: Double
    ) -> some View {
        VStack(alignment: .leading, spacing: DSSpacing.sm) {
            HStack {
                Text(title)
                    .font(DSFont.body)
                    .foregroundStyle(DSColor.textPrimary)
                Spacer(minLength: DSSpacing.md)
                Text(String(format: "%.2f", value.wrappedValue))
                    .font(DSFont.body.monospacedDigit())
                    .foregroundStyle(DSColor.textSecondary)
            }
            Slider(value: value, in: range, step: step)
                .accessibilityLabel(title)
        }
    }

    // MARK: - 书源原网页：旧的 CSS 全套，原封保留

    private var webNoticeSection: some View {
        Section {
            Text(localized("下面这套 CSS 只作用于「书源原网页」：原生玻璃卡片是 SwiftUI 画的，不读 CSS。想调卡片请切回上面的「原生玻璃卡片」。"))
                .font(DSFont.footnote)
                .foregroundStyle(DSColor.textSecondary)
        } header: {
            Text(localized("仅对原网页生效"))
                .foregroundStyle(DSColor.textSecondary)
        }
        .interfaceSectionSurface()
    }

    private var webEnabledSection: some View {
        Section {
            Toggle(localized("启用自订网页样式"), isOn: enabledBinding)
                .foregroundStyle(DSColor.textPrimary)
        } header: {
            Text(localized("样式开关"))
                .foregroundStyle(DSColor.textSecondary)
        } footer: {
            Text(localized("开启后把所选模板的 CSS 注入段评网页，用于调整网页的字号、行距与颜色；关闭则恢复书源网页原本的外观。原生玻璃卡片不受影响。"))
                .dsSectionFooter()
        }
        .interfaceSectionSurface()
    }

    private var webTemplatesSection: some View {
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
    }

    private var webCSSSection: some View {
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
            Text(localized("四个区域各自编辑、合成一份样式，套用到书源原网页；后写的样式覆盖先写的。"))
                .dsSectionFooter()
        }
        .interfaceSectionSurface()
    }

    private var webManageSection: some View {
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
