import SwiftUI

// Unified library 5d-5: 选择内容来源 (design §13.3; Phase 5 plan, decision 23), grouped as
// 资源库 groups them: App 资料, 书库 (the reader's connections), 来源配置, 官方模组 (AI 推荐,
// 古腾堡, 青空文库, the bundled modules; M2b), 模组 (the imported ones). A source pushes its items: a
// connection's feeds, Gutenberg's lists and feeds, 青空文库's indexes, a book source's discover
// categories. 「目前」 marks the group and source in use; a check mark, the item.
// - 加入清单 of a layout of lists (maintainer, 2026-10-27: 「预设全部、可增减」): each source's
//   items start with 全部清单, every list it offers as a card each, up to
//   `HomeSection.listCardLimit` with the cards already there.
//
// A sheet over the form, or pushed in the form's stack when the form is a sheet already on
// iOS 17 (`isPushed`), as the design says.

extension EnvironmentValues {
    /// 选择轮播数据 (maintainer, 2026-10-27): the picker offers only what draws books
    /// (`HomeSectionBinding.showsBooks`), for the 顶部轮播图's band of covers.
    @Entry var homePickerOffersBooksOnly = false
}

/// What 选择内容来源 gives the form.
struct HomeContentChoice: Equatable {
    let binding: HomeSectionBinding
    var parameters: [String: String] = [:]
    /// The item's name, for a binding that cannot name itself (`HomeSectionEditor.choose`).
    var itemTitle: String = ""
    /// A book source's category: the discover filter values it was listed under
    /// (`HomeSection.filtersKey`), also in `parameters`.
    var filterValues: [String: String] = [:]
}

extension HomeContentChoice {
    /// A module's lists (Phase 6f), each titled after itself. Its search entry is no list.
    static func lists(of module: RuleModule) -> [HomeContentChoice] {
        module.modules.compactMap { entry in
            entry.id.map { HomeContentChoice(binding: .module(moduleID: module.id, entryID: $0), itemTitle: entry.title ?? $0) }
        }
    }
}

struct HomeContentSourcePicker: View {
    let current: HomeSectionBinding?
    /// The section's parameters: a book source's categories list under its filter values.
    let parameters: [String: String]
    let isPushed: Bool
    /// The page's title: the name of the row or button that opened it.
    var title = localized("选择内容来源")
    let choose: (HomeContentChoice) -> Void
    /// 全部清单, for 加入清单: nil offers none.
    var chooseAll: (([HomeContentChoice]) -> Void)?
    let cancel: () -> Void

    @Environment(\.homePickerOffersBooksOnly) private var booksOnly

    @ObservedObject private var connections = RemoteLibraryConnectionStore.shared
    @ObservedObject private var availability = PublicLibraryAvailability.shared
    @ObservedObject private var sources = BookSourceStore.shared
    @ObservedObject private var modules = RuleModuleLibrary.shared

    init(current: HomeSectionBinding?, parameters: [String: String] = [:], isPushed: Bool,
         title: String = localized("选择内容来源"),
         choose: @escaping (HomeContentChoice) -> Void, chooseAll: (([HomeContentChoice]) -> Void)? = nil,
         cancel: @escaping () -> Void) {
        self.current = current
        self.parameters = parameters
        self.isPushed = isPushed
        self.title = title
        self.choose = choose
        self.chooseAll = chooseAll
        self.cancel = cancel
    }

    private var owner: HomeContentOwner? { current?.contentOwner }

    /// The connections with feeds of their own: OPDS and Calibre. WebDAV serves 最新 only.
    private var feedConnections: [RemoteLibraryConnection] {
        connections.catalogs.filter { $0.kind != .webDAV }
    }

    var body: some View {
        List {
            Section {
                ForEach(HomeSectionBinding.appData.filter { !booksOnly || $0.showsBooks }, id: \.self) { binding in
                    HomeChoiceRow(title: HomeSection(layout: .row, binding: binding).displayTitle(sourceName: ""),
                                  isCurrent: current == binding) {
                        choose(HomeContentChoice(binding: binding))
                    }
                }
            } header: {
                Text(localized("App 资料"))
            }
            .interfaceSectionSurface()

            if !feedConnections.isEmpty {
                Section {
                    ForEach(feedConnections) { connection in
                        NavigationLink {
                            HomeFeedChoices(source: .connection(connection), current: current, choose: choose,
                                            chooseAll: chooseAll)
                        } label: {
                            ownerLabel(connection.name, systemImage: SourceKindSymbol.symbol(for: ProviderType(connection.kind)),
                                       isCurrent: owner == .connection(id: connection.id))
                        }
                    }
                } header: {
                    Text(localized("书库"))
                }
                .interfaceSectionSurface()
            }

            Section {
                NavigationLink {
                    HomeSourceChoices(current: current, parameters: parameters, choose: choose, chooseAll: chooseAll)
                } label: {
                    ownerLabel(localized("来源配置"), systemImage: "square.grid.2x2.fill",
                               isCurrent: { if case .bookSource = owner { true } else { false } }())
                }
                .accessibilityIdentifier("homePicker.bookSources")
            }
            .interfaceSectionSurface()

            // As 资源库 groups them (M2b): AI 推荐, 古腾堡, 青空文库, then the bundled modules.
            Section {
                ForEach(HomeSectionBinding.official, id: \.self) { binding in
                    HomeChoiceRow(title: HomeSection(layout: .row, binding: binding).displayTitle(sourceName: ""),
                                  isCurrent: current == binding) {
                        choose(HomeContentChoice(binding: binding))
                    }
                }
                if availability.isAvailable {
                    NavigationLink {
                        HomeFeedChoices(source: .gutenberg, current: current, choose: choose, chooseAll: chooseAll)
                    } label: {
                        ownerLabel(localized("Project Gutenberg"), systemImage: SourceKindSymbol.symbol(for: .gutenberg),
                                   isCurrent: owner == .gutenberg)
                    }
                    NavigationLink {
                        HomeAozoraChoices(current: current, choose: choose, chooseAll: chooseAll)
                    } label: {
                        ownerLabel(localized("青空文库"), systemImage: SourceKindSymbol.symbol(for: .aozora),
                                   isCurrent: owner == .aozora)
                    }
                }
                // A module turned off (停用) offers nothing until it is on again.
                ForEach(modules.official.filter { modules.isEnabled($0.module.id) }, id: \.module.id) { installed in
                    moduleLink(installed)
                }
            } header: {
                Text(localized("官方模组"))
            }
            .interfaceSectionSurface()

            let imported = modules.imported.filter { modules.isEnabled($0.module.id) }
            if !imported.isEmpty {
                Section {
                    ForEach(imported, id: \.module.id) { installed in
                        moduleLink(installed)
                    }
                } header: {
                    Text(localized("模组"))
                }
                .interfaceSectionSurface()
            }
        }
        .navigationTitle(title)
        .toolbarTitleDisplayMode(.inline)
        .themedAppSurface(for: .explore)
        .task { await modules.loadIfNeeded() }
        .toolbar {
            if !isPushed {
                ToolbarItem(placement: .cancellationAction) {
                    Button(action: cancel) {
                        Label(localized("取消"), systemImage: "xmark")
                    }
                }
            }
        }
    }

    private func moduleLink(_ installed: InstalledRuleModule) -> some View {
        NavigationLink {
            HomeModuleChoices(module: installed.module, current: current, choose: choose, chooseAll: chooseAll)
        } label: {
            ownerLabel(installed.module.title, systemImage: "puzzlepiece.extension",
                       isCurrent: owner == .module(id: installed.module.id))
        }
        .accessibilityIdentifier("homePicker.module.\(installed.module.id)")
    }

    private func ownerLabel(_ name: String, systemImage: String?, isCurrent: Bool) -> some View {
        LabeledContent {
            if isCurrent { Text(localized("目前")) }
        } label: {
            Label {
                Text(name)
            } icon: {
                Image(systemName: systemImage ?? "books.vertical")
                    .accessibilityHidden(true)
            }
        }
    }
}

// MARK: - Rows

/// An item: its name, checked when it is the one in use.
private struct HomeChoiceRow: View {
    let title: String
    let isCurrent: Bool
    let action: () -> Void
    @Environment(\.isEnabled) private var isEnabled

    var body: some View {
        Button(action: action) {
            HStack {
                Text(title)
                    .foregroundStyle(isEnabled ? DSColor.textPrimary : DSColor.textTertiary)
                Spacer()
                if isCurrent {
                    Image(systemName: "checkmark")
                        .foregroundStyle(DSColor.accent)
                        .accessibilityHidden(true)
                }
            }
            .contentShape(Rectangle())
        }
        .accessibilityAddTraits(isCurrent ? .isSelected : [])
        .accessibilityIdentifier("homePicker.item.\(title)")
    }
}

/// 全部清单: every list the page offers, as 加入清单's cards. Nothing when the page offers none
/// (yet) or 加入清单 did not open it.
private struct HomeAllListsRow: View {
    let choices: [HomeContentChoice]
    let chooseAll: (([HomeContentChoice]) -> Void)?

    var body: some View {
        if let chooseAll, !choices.isEmpty {
            Section {
                Button { chooseAll(choices) } label: {
                    Text(localized("全部清单"))
                        .foregroundStyle(DSColor.textPrimary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .contentShape(Rectangle())
                }
                .accessibilityIdentifier("homePicker.allLists")
            } footer: {
                Text(String(format: localized("每个清单一张卡片，最多 %d 张。"), HomeSection.listCardLimit))
                    .dsSectionFooter()
            }
            .interfaceSectionSurface()
        }
    }
}

// MARK: - 书库

/// A library that speaks OPDS: Gutenberg's bundled lists first (no request), then the feeds its
/// catalog lists, fetched when this opens.
private struct HomeFeedChoices: View {
    enum Source {
        case connection(RemoteLibraryConnection)
        case gutenberg
    }

    enum LoadState {
        case loading
        case loaded([CollectionLocation])
        case failed(String)
    }

    let source: Source
    let current: HomeSectionBinding?
    let choose: (HomeContentChoice) -> Void
    var chooseAll: (([HomeContentChoice]) -> Void)?
    @State private var state = LoadState.loading
    @ObservedObject private var aggregation = AggregationSettingsStore.shared
    @Environment(\.homePickerOffersBooksOnly) private var booksOnly

    private var name: String {
        switch source {
        case .connection(let connection): connection.name
        case .gutenberg: localized("Project Gutenberg")
        }
    }

    private var provider: (any OPDSFeedProviding)? {
        switch source {
        case .connection(let connection): SourceProviderRegistry.shared.opdsProvider(catalogID: connection.id)
        case .gutenberg: SourceProviderRegistry.shared.gutenberg
        }
    }

    private func binding(for url: String) -> HomeSectionBinding {
        switch source {
        case .connection(let connection): .opdsFeed(connectionID: connection.id, url: url)
        case .gutenberg: .gutenbergFeed(url: url)
        }
    }

    /// 全部清单: Gutenberg's shelves and bundled lists (精选书单 is them all already) before its
    /// feeds; a library's feeds, or its root when it lists none.
    private var allLists: [HomeContentChoice] {
        var choices: [HomeContentChoice] = []
        if case .gutenberg = source {
            choices += GutenbergShelf.shelves(languages: aggregation.readingLanguages.languages)
                .map { HomeContentChoice(binding: .gutenbergShelf(id: $0.id)) }
            choices += HomeSectionBinding.gutenbergCollections.filter { $0 != .gutenbergLists }
                .map { HomeContentChoice(binding: $0) }
        }
        guard case .loaded(let feeds) = state else { return choices }
        if feeds.isEmpty, case .connection = source, let root = provider?.rootURL?.absoluteString {
            return choices + [HomeContentChoice(binding: binding(for: root), itemTitle: name)]
        }
        return choices + feeds.map { HomeContentChoice(binding: binding(for: $0.id), itemTitle: $0.title) }
    }

    var body: some View {
        List {
            HomeAllListsRow(choices: allLists, chooseAll: chooseAll)
            if case .gutenberg = source {
                // Gutenberg's shelves, as its storefront lists them: 热门, 最新, the reader's
                // languages. Kept by id, so they follow the endpoint (5d-6a).
                Section {
                    ForEach(GutenbergShelf.shelves(languages: aggregation.readingLanguages.languages)) { shelf in
                        let binding = HomeSectionBinding.gutenbergShelf(id: shelf.id)
                        HomeChoiceRow(title: shelf.title, isCurrent: current == binding) {
                            choose(HomeContentChoice(binding: binding))
                        }
                    }
                }
                .interfaceSectionSurface()
                Section {
                    ForEach(HomeSectionBinding.gutenbergCollections.filter { !booksOnly || $0.showsBooks }, id: \.self) { binding in
                        HomeChoiceRow(title: HomeSection(layout: .row, binding: binding).displayTitle(sourceName: ""),
                                      isCurrent: current == binding) {
                            choose(HomeContentChoice(binding: binding))
                        }
                    }
                }
                .interfaceSectionSurface()
            }
            Section {
                if case .connection = source, let root = provider?.rootURL?.absoluteString {
                    HomeChoiceRow(title: name, isCurrent: current == binding(for: root)) {
                        choose(HomeContentChoice(binding: binding(for: root), itemTitle: name))
                    }
                }
                switch state {
                case .loading:
                    ProgressView().frame(maxWidth: .infinity)
                case .loaded(let feeds):
                    ForEach(feeds, id: \.id) { feed in
                        HomeChoiceRow(title: feed.title, isCurrent: current == binding(for: feed.id)) {
                            choose(HomeContentChoice(binding: binding(for: feed.id), itemTitle: feed.title))
                        }
                    }
                case .failed(let message):
                    VStack(alignment: .leading, spacing: DSSpacing.sm) {
                        Text(message)
                            .font(DSFont.footnote)
                            .foregroundStyle(DSColor.textSecondary)
                        Button(localized("重试")) { Task { await load() } }
                            .buttonStyle(.bordered)
                    }
                }
            }
            .interfaceSectionSurface()
        }
        .navigationTitle(name)
        .toolbarTitleDisplayMode(.inline)
        .themedAppSurface(for: .explore)
        .task { await load() }
    }

    /// The catalog's navigation feeds. An item-only catalog has none: its root is the one feed.
    private func load() async {
        guard let provider else {
            state = .failed(localized("此目录没有内容"))
            return
        }
        state = .loading
        do {
            let page = try await provider.browse(nil, after: nil)
            state = .loaded(page.entries.compactMap { entry in
                if case .location(let location) = entry { return location }
                return nil
            })
        } catch is CancellationError {
            return
        } catch {
            AppLogger.network("⟐ home picker could not list a library's feeds", error: error,
                              context: ["source": provider.instance.id])
            state = .failed(error.localizedDescription)
        }
    }
}

/// 青空文库: 新着 and its three indexes, read from the catalog.
private struct HomeAozoraChoices: View {
    let current: HomeSectionBinding?
    let choose: (HomeContentChoice) -> Void
    var chooseAll: (([HomeContentChoice]) -> Void)?

    @Environment(\.homePickerOffersBooksOnly) private var booksOnly

    var body: some View {
        List {
            HomeAllListsRow(choices: HomeSectionBinding.aozora.map { HomeContentChoice(binding: $0) }, chooseAll: chooseAll)
            Section {
                ForEach(HomeSectionBinding.aozora.filter { !booksOnly || $0.showsBooks }, id: \.self) { binding in
                    HomeChoiceRow(title: HomeSection(layout: .row, binding: binding).displayTitle(sourceName: ""),
                                  isCurrent: current == binding) {
                        choose(HomeContentChoice(binding: binding))
                    }
                }
            }
            .interfaceSectionSurface()
        }
        .navigationTitle(localized("青空文库"))
        .toolbarTitleDisplayMode(.inline)
        .themedAppSurface(for: .explore)
    }
}

// MARK: - 模组

/// A module's lists (Phase 6f): the one in use is checked.
struct HomeModuleChoices: View {
    let module: RuleModule
    let current: HomeSectionBinding?
    let choose: (HomeContentChoice) -> Void
    var chooseAll: (([HomeContentChoice]) -> Void)?

    var body: some View {
        List {
            HomeAllListsRow(choices: HomeContentChoice.lists(of: module), chooseAll: chooseAll)
            Section {
                ForEach(HomeContentChoice.lists(of: module), id: \.binding) { choice in
                    HomeChoiceRow(title: choice.itemTitle, isCurrent: current == choice.binding) {
                        choose(choice)
                    }
                }
            } footer: {
                if let description = module.description, !description.isEmpty {
                    Text(description).dsSectionFooter()
                }
            }
            .interfaceSectionSurface()
        }
        .navigationTitle(module.title)
        .toolbarTitleDisplayMode(.inline)
        .themedAppSurface(for: .explore)
    }
}

// MARK: - 来源配置

/// Every book source 探索 lists, searchable: a reader can have thousands, so only the rows on
/// screen are built (`HostedCollectionList`, as 书源管理).
struct HomeSourceChoices: View {
    let current: HomeSectionBinding?
    /// The section's parameters, for the filter values each source's categories list under.
    var parameters: [String: String] = [:]
    let choose: (HomeContentChoice) -> Void
    var chooseAll: (([HomeContentChoice]) -> Void)?
    @ObservedObject private var store = BookSourceStore.shared
    @State private var query = ""
    @State private var opened: String?

    private var currentSourceURL: String? {
        if case .bookSource(let url) = current?.contentOwner { return url }
        return nil
    }

    private var listed: [BookSource] {
        DiscoverViewModel.exploreSources(DiscoverViewModel.exploreSources(in: store), inGroup: nil,
                                         matching: query.trimmingCharacters(in: .whitespacesAndNewlines))
    }

    var body: some View {
        let sources = listed
        HostedCollectionList(items: sources.map(\.bookSourceUrl), contentVersion: currentSourceURL.hashValue,
                             showsSeparator: { _ in true }, usesSystemMargins: { _ in true }) { url in
            let source = sources.first { $0.bookSourceUrl == url }
            Button { opened = url } label: {
                HStack {
                    Text(source?.bookSourceName ?? url)
                        .foregroundStyle(DSColor.textPrimary)
                        .lineLimit(2)
                    Spacer()
                    if url == currentSourceURL {
                        Text(localized("目前")).foregroundStyle(DSColor.textSecondary)
                    }
                    Image(systemName: "chevron.right")
                        .font(DSFont.footnote.weight(.semibold))
                        .foregroundStyle(DSColor.textTertiary)
                        .accessibilityHidden(true)
                }
                .padding(.vertical, DSSpacing.sm)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityIdentifier("homePicker.source.\(source?.bookSourceName ?? url)")
        }
        .overlay {
            if sources.isEmpty {
                if query.isEmpty {
                    ContentUnavailableView {
                        UnavailableLabel(localized("没有可用的来源配置，请先启用来源配置"), systemImage: "puzzlepiece.extension")
                    }
                } else {
                    UnavailableSearchView(text: query)
                }
            }
        }
        .searchable(text: $query, placement: .navigationBarDrawer(displayMode: .always),
                    prompt: localized("搜寻来源配置名称或网址"))
        .navigationTitle(localized("来源配置"))
        .toolbarTitleDisplayMode(.inline)
        .themedAppSurface(for: .explore)
        .navigationDestination(item: $opened) { url in
            if let source = store.sources.first(where: { $0.bookSourceUrl == url }) {
                HomeCategoryChoices(source: source,
                                    filterValues: HomeSection.filterValues(in: parameters, sourceURL: url),
                                    current: current, choose: choose, chooseAll: chooseAll)
                    // Pushed from a section's form, which hides the tab bar (`homeEditDestinations`).
                    .hidesRootTabBar()
            }
        }
    }
}

/// A book source's discover categories, under the group labels it draws, searchable, with the
/// source's filters above them. A filter changed here lists the categories again under it for
/// this section only (`SourceCategoryListing`); the source's discover page keeps its own.
/// 全部清单 gives the categories it lists, under the filters set, as 加入清单's cards.
struct HomeCategoryChoices: View {
    let current: HomeSectionBinding?
    let choose: (HomeContentChoice) -> Void
    var chooseAll: (([HomeContentChoice]) -> Void)?
    @StateObject private var listing: SourceCategoryListing
    @State private var query = ""

    /// - Parameter filterValues: the section's, from when it picked its category here.
    init(source: BookSource, filterValues: [String: String] = [:], current: HomeSectionBinding?,
         choose: @escaping (HomeContentChoice) -> Void, chooseAll: (([HomeContentChoice]) -> Void)? = nil) {
        self.current = current
        self.choose = choose
        self.chooseAll = chooseAll
        _listing = StateObject(wrappedValue: SourceCategoryListing(source: source, filterValues: filterValues))
    }

    private var currentReferences: [ExploreCategoryReference] {
        if case .sourceCategories(let references) = current { return references }
        return []
    }

    private var trimmedQuery: String { query.trimmingCharacters(in: .whitespacesAndNewlines) }

    private var groups: [DiscoverCategoryGroup] {
        DiscoverCategoryGroup.filtered(listing.groups, matching: trimmedQuery)
    }

    /// A category as 选择内容来源 gives it: with the filter values it is listed under.
    private func choice(_ reference: ExploreCategoryReference) -> HomeContentChoice {
        let values = listing.filterValues
        return HomeContentChoice(binding: .sourceCategories([reference]),
                                 parameters: HomeSection.filterParameters(values, sourceURL: reference.sourceURL),
                                 filterValues: values)
    }

    /// 全部清单: the categories listed, as the search narrows them.
    private var allLists: [HomeContentChoice] {
        guard listing.state == .loaded else { return [] }
        return groups.flatMap(\.items).compactMap { listing.reference(for: $0).map(choice) }
    }

    var body: some View {
        List {
            if !listing.filters.isEmpty {
                Section {
                    ForEach(listing.filters, id: \.paramKey) { filter in
                        Picker(filter.title, selection: Binding(
                            get: { filter.selected },
                            set: { value in Task { await listing.select(filter, value: value) } })) {
                            ForEach(Array(filter.options.enumerated()), id: \.offset) { _, option in
                                Text(option).tag(option)
                            }
                        }
                        .accessibilityIdentifier("homePicker.filter.\(filter.paramKey)")
                    }
                } header: {
                    Text(localized("筛选"))
                } footer: {
                    // Under the filters, not over them: the reader changes one back from here.
                    if listing.state == .empty {
                        Text(localized("暂无发现内容")).dsSectionFooter()
                    }
                }
                .interfaceSectionSurface()
            }
            HomeAllListsRow(choices: allLists, chooseAll: chooseAll)
            ForEach(groups) { group in
                Section {
                    ForEach(group.items, id: \.stableKey) { item in
                        if let reference = listing.reference(for: item) {
                            HomeChoiceRow(title: item.title, isCurrent: currentReferences.contains(reference)) {
                                choose(choice(reference))
                            }
                        }
                    }
                } header: {
                    Text(group.title)
                }
                .interfaceSectionSurface()
            }
        }
        .overlay {
            switch listing.state {
            case .loading:
                ProgressView()
            case .empty:
                if listing.filters.isEmpty {
                    ContentUnavailableView {
                        UnavailableLabel(localized("暂无发现内容"), systemImage: "sparkles")
                    }
                }
            case .failed(let message):
                ContentUnavailableView {
                    UnavailableLabel(localized("载入失败"), systemImage: "exclamationmark.triangle")
                } description: {
                    Text(String(format: localized("%@：%@"), localized("来源配置脚本错误"), message))
                }
            case .loaded:
                if !trimmedQuery.isEmpty, groups.isEmpty { UnavailableSearchView(text: trimmedQuery) }
            }
        }
        .searchable(text: $query, placement: .navigationBarDrawer(displayMode: .always),
                    prompt: localized("搜寻发现项目"))
        .navigationTitle(listing.source.bookSourceName)
        .toolbarTitleDisplayMode(.inline)
        .themedAppSurface(for: .explore)
        .task { await listing.load() }
    }
}

#Preview("模组的清单") {
    NavigationStack {
        HomeModuleChoices(module: RuleModulePreviewData.module(), current: .module(moduleID: "preview.module", entryID: "new"),
                          choose: { _ in })
    }
}

#Preview("选择内容来源") {
    NavigationStack {
        HomeContentSourcePicker(current: .continueReading, isPushed: false, choose: { _ in }, cancel: {})
    }
}

#Preview("选择轮播数据") {
    NavigationStack {
        HomeContentSourcePicker(current: .continueReading, isPushed: true, title: localized("选择轮播数据"), choose: { _ in }, cancel: {})
    }
    .environment(\.homePickerOffersBooksOnly, true)
}
