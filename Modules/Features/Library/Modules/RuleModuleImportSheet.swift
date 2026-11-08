import SwiftUI

/// 新增模组 and 检查更新's sheet (Phase 6e): the module is shown — who wrote it, its lists, the
/// sites it will send requests to — or the reason it was refused, before anything is written.
struct RuleModuleImportSheet: View {
    @ObservedObject var model: RuleModuleImportModel
    let title: String
    /// Only 从网址 asks for an address; a file or the clipboard is read as the sheet opens.
    var asksForAddress = false
    @Environment(\.dismiss) private var dismiss
    @FocusState private var addressFocused: Bool

    var body: some View {
        NavigationStack {
            Form {
                if asksForAddress { addressSection }
                content
            }
            .softScrollEdges()
            .navigationTitle(title)
            .toolbarTitleDisplayMode(.inline)
            .themedAppSurface(for: .settings)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button { dismiss() } label: { Image(systemName: "xmark").accessibilityHidden(true) }
                        .accessibilityLabel(localized("关闭"))
                        .accessibilityIdentifier("module.import.close")
                }
                if let commitTitle {
                    ToolbarItem(placement: .confirmationAction) {
                        Button { Task { await model.commit() } } label: { Image(systemName: "checkmark").accessibilityHidden(true) }
                            .accessibilityLabel(commitTitle)
                            .accessibilityIdentifier("module.import.commit")
                    }
                }
            }
            .onChange(of: model.phase) { _, phase in
                switch phase {
                case .done, .subscribed: dismiss()
                default: break
                }
            }
            .onAppear { if asksForAddress && model.address.isEmpty { addressFocused = true } }
        }
    }

    /// The checkmark's name: what confirming writes.
    private var commitTitle: String? {
        switch model.phase {
        case .preview(let preview): localized(preview.replacing == nil ? "新增模组" : "更新模组")
        case .repository: localized("订阅模组仓库")
        default: nil
        }
    }

    private var addressSection: some View {
        Section {
            TextField("https://example.com/module.json", text: $model.address)
                .keyboardType(.URL)
                .textContentType(.URL)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
                .submitLabel(.go)
                .focused($addressFocused)
                .onSubmit { Task { await model.fetch() } }
                .accessibilityLabel(localized("模组网址"))
                .accessibilityIdentifier("module.import.address")
            Button {
                addressFocused = false
                Task { await model.fetch() }
            } label: {
                SettingsRowLabel(localized("读取"), systemImage: "arrow.down.circle", role: .action)
            }
            .disabled(model.address.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || model.isLoading)
            .accessibilityIdentifier("module.import.load")
        } header: {
            Text(localized("模组网址")).foregroundStyle(DSColor.textSecondary)
        }
        .interfaceSectionSurface()
    }

    @ViewBuilder
    private var content: some View {
        switch model.phase {
        case .idle, .done, .subscribed:
            EmptyView()
        case .loading:
            Section {
                HStack(spacing: DSSpacing.sm) {
                    ProgressView()
                    Text(localized("读取中")).foregroundStyle(DSColor.textSecondary)
                }
                .accessibilityElement(children: .combine)
            }
            .interfaceSectionSurface()
        case .failed(let message):
            Section {
                Text(message)
                    .foregroundStyle(DSColor.textPrimary)
                    .textSelection(.enabled)
                    .accessibilityIdentifier("module.import.failure")
            } header: {
                Text(localized("无法加入这个模组")).foregroundStyle(DSColor.textSecondary)
            }
            .interfaceSectionSurface()
        case .upToDate(let message):
            Section {
                Label(message, systemImage: "checkmark.circle")
                    .foregroundStyle(DSColor.textPrimary)
                    .accessibilityIdentifier("module.import.upToDate")
            }
            .interfaceSectionSurface()
        case .preview(let preview):
            RuleModuleManifestSections(module: preview.module, addedHosts: preview.addedHosts,
                                       newVersion: preview.replacing == nil ? nil : preview.module.version)
        case .repository(let repository):
            Section {
                ForEach(repository.index.modules) { entry in
                    VStack(alignment: .leading, spacing: DSSpacing.xxs) {
                        Text(entry.title).foregroundStyle(DSColor.textPrimary)
                        if let description = entry.description {
                            Text(description)
                                .font(DSFont.footnote)
                                .foregroundStyle(DSColor.textSecondary)
                        }
                    }
                    .accessibilityElement(children: .combine)
                }
            } header: {
                Text(repository.index.name).foregroundStyle(DSColor.textSecondary)
            } footer: {
                Text(localized("订阅后在「模组」页挑选要安装的模组；仓库里的模组不会自动安装。")).dsSectionFooter()
            }
            .interfaceSectionSurface()
            .accessibilityIdentifier("module.import.repository")
        }
    }
}

/// What a module says about itself, on the import sheet and its own page.
struct RuleModuleManifestSections: View {
    let module: RuleModule
    /// Sites an update adds, said before it replaces anything.
    var addedHosts: [String] = []
    /// Shown as the header when this is an update.
    var newVersion: String?

    var body: some View {
        Section {
            if let author = nonEmpty(module.author) {
                LabeledContent(localized("作者"), value: author)
            }
            LabeledContent(localized("版本"), value: module.version)
            if let required = nonEmpty(module.requiredVersion) {
                LabeledContent(localized("最低格式版本"), value: required)
            }
            if let site = nonEmpty(module.site) {
                LabeledContent(localized("网站"), value: site)
            }
            if let description = nonEmpty(module.description) {
                Text(description).foregroundStyle(DSColor.textPrimary)
            }
            // The credit the site's terms ask for (format 3.0), as the site words it.
            if let attribution = module.attribution, let text = nonEmpty(attribution.text) {
                if let url = attribution.url.flatMap({ safeURL(string: $0) }) {
                    Link(text, destination: url)
                } else {
                    Text(text).foregroundStyle(DSColor.textSecondary)
                }
            }
        } header: {
            Text(newVersion.map { String(format: localized("新版本 %@"), $0) } ?? module.title)
                .foregroundStyle(DSColor.textSecondary)
        }
        .interfaceSectionSurface()

        Section {
            ForEach(Array(module.modules.enumerated()), id: \.offset) { _, entry in
                entryRow(title: entry.title ?? entry.id ?? "", description: entry.description)
            }
            if let search = module.search {
                entryRow(title: localized("搜索"), description: search.description)
            }
            if let lookup = module.lookup {
                entryRow(title: localized("以 ISBN 查询"), description: lookup.description)
            }
        } header: {
            Text(localized("清单")).foregroundStyle(DSColor.textSecondary)
        }
        .interfaceSectionSurface()

        if !addedHosts.isEmpty {
            Section {
                ForEach(addedHosts, id: \.self) { Text($0).foregroundStyle(DSColor.textPrimary) }
            } header: {
                Text(localized("新增的网站")).foregroundStyle(DSColor.textSecondary)
            } footer: {
                Text(localized("更新后也会向这些网站送出请求。")).dsSectionFooter()
            }
            .interfaceSectionSurface()
        }

        Section {
            ForEach(module.hosts, id: \.self) { Text($0).foregroundStyle(DSColor.textPrimary) }
        } header: {
            Text(localized("会连线的网站")).foregroundStyle(DSColor.textSecondary)
        } footer: {
            VStack(alignment: .leading, spacing: DSSpacing.xs) {
                Text(localized("模组只会向这些网站送出请求，封面也只从这些网站载入。"))
                // Phase 6h: a module with a search fills by default (maintainer, 2026-10-15);
                // one with a lookup is sent ISBNs (M4).
                switch (module.search != nil, module.lookup != nil) {
                case (true, false):
                    Text(localized("自动补齐书籍资料开启时，书架上的书名与作者也会送到这些网站，用来补上空白的简介与分类；可在「资料来源」取消勾选。"))
                case (false, true):
                    Text(localized("自动补齐书籍资料开启时，书架上的书的 ISBN 也会送到这些网站，用来补上空白的封面、简介与出版社；可在「资料来源」取消勾选。"))
                case (true, true):
                    Text(localized("自动补齐书籍资料开启时，书架上的书名、作者与 ISBN 也会送到这些网站，用来补上空白的封面、简介与分类；可在「资料来源」取消勾选。"))
                case (false, false):
                    EmptyView()
                }
            }
            .dsSectionFooter()
        }
        .interfaceSectionSurface()
    }

    private func entryRow(title: String, description: String?) -> some View {
        VStack(alignment: .leading, spacing: DSSpacing.xxs) {
            Text(title).foregroundStyle(DSColor.textPrimary)
            if let description = nonEmpty(description) {
                Text(description).font(DSFont.subheadline).foregroundStyle(DSColor.textSecondary)
            }
        }
        .accessibilityElement(children: .combine)
    }

    private func nonEmpty(_ text: String?) -> String? {
        text.flatMap { $0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? nil : $0 }
    }
}

#Preview("A refused module") {
    let model = RuleModuleImportModel(download: { _ in throw URLError(.notConnectedToInternet) })
    RuleModuleImportSheet(model: model, title: localized("新增模组"))
        .task {
            await model.read(clipboard: #"{"id":"bad id","title":"x","version":"1","hosts":[],"modules":[]}"#)
        }
}

#Preview("A module to add") {
    let model = RuleModuleImportModel(download: { _ in throw URLError(.notConnectedToInternet) })
    RuleModuleImportSheet(model: model, title: localized("新增模组"))
        .task { await model.read(clipboard: RuleModulePreviewData.json(id: "example.newbooks", title: "新书速报")) }
}

#Preview("A module with a credit") {
    let model = RuleModuleImportModel(download: { _ in throw URLError(.notConnectedToInternet) })
    RuleModuleImportSheet(model: model, title: localized("新增模组"))
        .task {
            await model.read(clipboard: #"""
            {"id":"example.credit","title":"书籍资料","version":"1.0","requiredVersion":"3.0","hosts":["example.com"],
             "attribution":{"text":"Supported by Example Developers","url":"https://example.com/dev"},
             "search":{"request":{"url":"https://example.com/s?q={{keyword}}"},"list":{"items":"$.items[*]","title":"$.title"}}}
            """#)
        }
}

#Preview("A module that looks up ISBNs") {
    let model = RuleModuleImportModel(download: { _ in throw URLError(.notConnectedToInternet) })
    RuleModuleImportSheet(model: model, title: localized("新增模组"))
        .task {
            await model.read(clipboard: #"""
            {"id":"example.isbn","title":"书目资料","version":"1.0","requiredVersion":"3.0","hosts":["api.example.com"],"modules":[],
             "lookup":{"request":{"url":"https://api.example.com/isbn/{{isbn}}"},"isbnPrefixes":["9784"],
                       "list":{"items":"$[*]","title":"$.title","isbn":"$.isbn"}}}
            """#)
        }
}
