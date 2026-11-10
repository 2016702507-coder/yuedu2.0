import SwiftUI

private typealias BookSearchResultRoute = SearchResultRoute<SearchBook>

/// Navigation route for one frozen search-result snapshot.
///
/// Value-based navigation is deliberate. The closure form
/// `NavigationLink { destination } label: { … }` builds its destination for every
/// visible row on *every* list body evaluation. Before search-row presentation
/// snapshots were introduced, that repeatedly ran audio/text inference over
/// unbounded metadata such as full-page HTML intros. Value routing also keeps
/// destination creation out of the streaming list's redraw path.
///
/// The discover page never had this: it routes through `.navigationDestination`,
/// which resolves the destination once, on tap. The route retains that tapped
/// snapshot so later `SearchAggregator` publications cannot replace the data
/// under an active iOS 17 destination.

/// Installs value routing for results where the native SwiftUI list pushes them by
/// value (iOS 18 and later). The UIKit list iOS 17 uses has no `NavigationLink`, so its
/// results go through the page's one item-based destination instead
/// (`SearchPagePush.result`). Delete the iOS 17 branch together with the native iOS 17
/// table when the deployment target reaches iOS 18.
private struct SearchResultNavigationModifier<Destination: View>: ViewModifier {
    let mode: SearchResultNavigationMode
    let destination: (BookSearchResultRoute) -> Destination

    @ViewBuilder
    func body(content: Content) -> some View {
        switch mode {
        case .selectedItem:
            content
        case .valueRoute:
            content
                .navigationDestination(
                    for: BookSearchResultRoute.self,
                    destination: destination
                )
                // The tab root's works (unified search 4c-3).
                .navigationDestination(for: UnifiedSearchResultRoute.self, destination: UnifiedSearchDestination.init(route:))
        }
    }
}

/// Everything the search page pushes through its one item-based destination.
///
/// One destination, never one per kind. TestFlight build 5 gave 最近阅读's reader a
/// second `navigationDestination(item:)` beside the results' own, and on iOS 17 the
/// result's detail then lost its own reader push: the second time through, the manga
/// reader would not open from the detail, or would not leave it on Back (iOS 17.5
/// simulator; `DetailReaderBackSwipeUITests.testSearchTabMangaResultOpensEveryTime`).
/// With this page still reading `DismissAction`, the same build froze on the first tap of
/// a result instead (Technotes/iOS17ReaderNavigationWatchdog.md). 最近阅读's reader is
/// no longer pushed at all — see `recentReaderRoute`.
private enum SearchPagePush: Hashable {
    /// A search result. Pushed this way on iOS 17 only; later systems push results by
    /// value from the list's `NavigationLink`.
    case result(BookSearchResultRoute)
    /// A work of the tab root's one list (unified search 4c-3), on iOS 17 likewise.
    case work(UnifiedSearchResultRoute)
}

/// Resolves a push without capturing `BookSearchView` or its live `SearchAggregator`
/// (Technotes/iOS17SearchWatchdogPostmortem.md, guardrail 3).
private struct SearchPagePushDestination: View {
    let push: SearchPagePush

    var body: some View {
        switch push {
        case .result(let route):
            SearchResultDestination(route: route)
        case .work(let route):
            UnifiedSearchDestination(route: route)
        }
    }
}

/// Resolves a frozen route without capturing `BookSearchView` or its live
/// `SearchAggregator`. The inherited store is forwarded explicitly to preserve
/// the existing detail-view environment contract.
///
/// A result opens 作品详情 (unified library 5f-4c, decision 29: a work has one page wherever it
/// is opened from), made in `init` from the route's snapshot: SwiftUI may build the destination
/// again as the page updates, so it reads only the snapshot and an indexed source lookup. Its
/// version is drawn as the result's own page, with the work's known reading sources first in 换源.
private struct SearchResultDestination: View {
    let route: BookSearchResultRoute
    private let work: WorkDetailRoute?
    @EnvironmentObject private var bookStore: BookStore

    init(route: BookSearchResultRoute) {
        self.route = route
        work = WorkDetailRoute(searchResult: route.snapshot)
    }

    var body: some View {
        if let work {
            WorkDetailView(route: work, searchResults: [work.nodeKey: route.snapshot])
                .environmentObject(bookStore)
        } else {
            ContentUnavailableView {
                UnavailableLabel(localized("来源配置已被删除"), systemImage: "books.vertical")
            }
        }
    }
}

/// A work of the tab root's one list (unified search 4c-3): 作品详情 of its lead, with every
/// other member as a version and each book-source member's result for its page's 换源. Made
/// in `init` from the selection frozen at the tap, as `SearchResultDestination` is.
private struct UnifiedSearchDestination: View {
    private let parts: UnifiedSearchDestinationParts?
    @EnvironmentObject private var bookStore: BookStore

    init(route: UnifiedSearchResultRoute) {
        parts = route.snapshot.destination()
    }

    var body: some View {
        if let parts {
            WorkDetailView(route: parts.route, searchResults: parts.searchResults, searchVersions: parts.versions)
                .environmentObject(bookStore)
        } else {
            ContentUnavailableView {
                UnavailableLabel(localized("来源配置已被删除"), systemImage: "books.vertical")
            }
        }
    }
}

/// 搜索's title: a tab root's at the root of its tab, `.inline` where it is pushed.
private struct SearchPageTitle: ViewModifier {
    let isTabRoot: Bool

    func body(content: Content) -> some View {
        if isTabRoot {
            content.rootTabTitle(localized("搜索"), onScroll: .minimizesBar)
        } else {
            content
                .navigationTitle(localized("搜索"))
                .toolbarTitleDisplayMode(.inline)
        }
    }
}

/// iOS 17's results in the native table: at the tab's root, the one list of works (unified
/// search 4c-3); elsewhere, the sources' results. A view of its own, so the search page never
/// reads the parts' changing finds (postmortem guardrail 13).
private struct IOS17SearchResults: View {
    /// The tab root's works; `nil` shows the sources' `rows` instead.
    let works: UnifiedSearchModel?
    var libraries: LibrarySearchModel? = nil
    let rows: [IOS17SearchResultTableRow]
    var sourcesSearching = false
    var sourcesPaused = false
    /// The query submitted, while it is still the one in the field.
    var submittedQuery: String? = nil
    let onSelect: (UUID) -> Void
    /// Pushes a work's 作品详情 through the page's one item destination.
    var openWork: (UnifiedSearchResultRoute) -> Void = { _ in }
    @Environment(\.colorScheme) private var colorScheme
    @Environment(FilledCoverIndex.self) private var filledCovers: FilledCoverIndex?

    var body: some View {
        let workRows = works?.rows ?? []
        let groups = works?.groups ?? []
        IOS17SearchResultTable(
            content: IOS17SearchResultTableContent(
                rows: works == nil ? rows : [],
                works: works.map { works in
                    IOS17SearchWorksSection(
                        groups: groups.map { group in
                            IOS17SearchWorkGroup(kind: group.kind, title: group.kind.searchGroupTitle, rows: group.rows.map {
                                IOS17SearchResultTableRow(unified: $0, colorScheme: colorScheme,
                                                          filledCover: { filledCovers?.path(for: $0) })
                            })
                        },
                        status: UnifiedSearchStatus(
                            hasRows: !groups.isEmpty, isSearching: sourcesSearching || works.isResolving,
                            isPaused: sourcesPaused,
                            othersSearching: libraries?.isSearching ?? false,
                            submittedQuery: submittedQuery,
                            failures: libraries?.failures ?? [],
                            filteredOut: works.isFilteredOut)
                    )
                }
            ),
            onSelect: onSelect,
            onSelectWork: { id in
                guard let row = workRows.first(where: { $0.id == id }) else {
                    AppLogger.error("⟐ search tap found no work", context: ["id": id.uuidString, "rows": workRows.count])
                    return
                }
                openWork(UnifiedSearchResultRoute(id: row.id, snapshot: row.selection))
            }
        )
    }
}

/// The tab root's one list on iOS 18 and later: its status computed here, so the search page
/// never reads the parts' changing finds (guardrail 13).
@available(iOS 18.0, *)
private struct ModernUnifiedSearchRows: View {
    let works: UnifiedSearchModel
    let libraries: LibrarySearchModel
    let sourcesSearching: Bool
    let sourcesPaused: Bool
    let submittedQuery: String?

    var body: some View {
        UnifiedSearchRows(
            model: works,
            status: UnifiedSearchStatus(
                hasRows: !works.groups.isEmpty, isSearching: sourcesSearching || works.isResolving,
                isPaused: sourcesPaused, othersSearching: libraries.isSearching,
                submittedQuery: submittedQuery, failures: libraries.failures,
                filteredOut: works.isFilteredOut))
    }
}

/// The results' scroll edge: a tab root's under the 搜索 tab's minimizing bar, the app's
/// soft edge where the page is pushed.
private struct SearchResultsScrollEdges: ViewModifier {
    let isTabRoot: Bool

    func body(content: Content) -> some View {
        if isTabRoot {
            content.rootTabSearchScrollEdges()
        } else {
            content.softScrollEdges()
        }
    }
}

// MARK: - Book Search View

struct BookSearchView: View {
    var initialQuery: String = ""
    /// A scope for this search page only, never saved — Legado's 搜索 on one source
    /// (`searchScope.update(scope, save = false)`). `nil` uses the saved scope.
    var sessionScope: SearchSourceScope?
    /// The 搜索 tab's own root, which carries a tab root's title; pushed from elsewhere,
    /// the page is `.inline` like any other.
    var isTabRoot = false

    @EnvironmentObject var bookStore: BookStore
    @StateObject private var aggregator = SearchAggregator()
    @StateObject private var scopeStore = SearchSourceScopeStore.shared
    @ObservedObject private var sourceStore = BookSourceStore.shared
    @ObservedObject private var availability = PublicLibraryAvailability.shared
    /// 聚合设置's 搜寻来源 (search 9d), for 青空文库, matched as you type here.
    @ObservedObject private var aggregation = AggregationSettingsStore.shared
    // No `@Environment(\.dismiss)` here: iOS 17 replaces DismissAction over and over
    // while a result's detail is pushed above this page, and every replacement re-runs
    // this body (Technotes/iOS17ReaderNavigationWatchdog.md).
    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    /// 搜索框是否处于输入状态：来源配置目录只在「没在打字」的空查询下露面，
    /// 一旦点进搜索框，就让位给最近搜索。
    @Environment(\.isSearching) private var isSearchFieldActive
    /// The tab's stack, which 作品详情 is pushed onto. A reference that never
    /// changes (postmortem guardrail 13).
    @Environment(\.searchTabNavigation) private var tabNavigation

    @State private var query = ""
    @State private var errorMsg: String? = nil
    @State private var submittedQuery = ""
    @State private var showsSourceScopeSheet = false
    @State private var needsSearchResubmission = false
    /// 来源配置目录里长按卡片改名：正在改的书源，与输入框草稿。
    @State private var renamingSource: BookSource?
    @State private var renameText = ""
    /// 搜索页书源目录的分组筛选：nil = 全部，其它 = 某个自定义分组名。
    /// 只存在内存里，退出页面回到「全部」，不写进设置。
    @State private var selectedSourceGroup: String? = nil
    /// 自定义分组编辑器，以及长按单张卡片时预选的那本书源。
    @State private var showsSourceGroupEditor = false
    @State private var groupEditorPreselected: UUID? = nil
    /// The session scope as the reader changes it on this page.
    @State private var editedSessionScope: SearchSourceScope?
    /// What this page has pushed through its one item-based destination: a result on
    /// iOS 17.
    @State private var pushed: SearchPagePush?
    /// A book opened from 最近阅读, full screen over the search, as Apple Books opens a
    /// book from its search; closing it comes back to the list as it was left. 最近阅读
    /// shows only while the search field is active, and pushed onto this stack the reader
    /// lost its hidden navigation bar: the active `UISearchController` puts back the bar
    /// it had collapsed as the push starts (`_navigationControllerWillShowViewController:`,
    /// right after SwiftUI hid it), which left a bar-high band above the classic top bar.
    @State private var recentReaderRoute: DetailReaderRoute?
    /// The shelf's matches as you type (unified search 4b-1); read only by the views that
    /// draw them.
    @State private var shelfSearch = ShelfSearchModel()
    /// The saved OPDS and Calibre libraries' answers (unified search 4b-2) and the modules' (Phase
    /// 6g; Open Library among them since OL3), asked on submit.
    @State private var librarySearch = LibrarySearchModel()
    /// Every part's finds merged into one list of works (4c-3); read only by the views that
    /// draw it.
    @State private var unifiedSearch = UnifiedSearchModel()
    @AppStorage(RecentSearchQueries.storageKey) private var recentQueries = RecentSearchQueries()

    /// The scope this page searches: its own session scope, else the saved one.
    private var activeScope: SearchSourceScope {
        editedSessionScope ?? sessionScope ?? scopeStore.scope
    }

    var enabledSources: [BookSource] { sourceStore.enabledSources }

    private var trimmedQuery: String {
        query.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// Only the tab's root searches the public libraries too: its stack carries the store's
    /// pages and 作品详情. Never in China.
    private var offersPublicLibraries: Bool {
        isTabRoot && tabNavigation != nil && availability.isAvailable
    }

    /// One search for all (Phase 5 plan decision 17, as amended 2026-10-11; unified search
    /// 4b, 4c-3): one list of works from the shelf, the saved libraries, 青空文库 where the
    /// public libraries are offered, the sources and Open Library, as soon as there is a
    /// query. Only the tab's root: its stack carries 作品详情.
    private var showsCombinedResults: Bool {
        isAtTabRoot && !trimmedQuery.isEmpty
    }

    /// The 搜索 tab's root, whose stack carries 作品详情 and whose list is the works'.
    private var isAtTabRoot: Bool {
        isTabRoot && tabNavigation != nil
    }

    /// What the sources' part says while it has no result.
    private var sourcesNotice: String? {
        guard aggregator.results.isEmpty else { return nil }
        if aggregator.isSearching { return localized("搜索中…") }
        if aggregator.isPaused { return localized("已暂停") }
        if shouldShowEmptyResult { return String(format: localized("没有找到「%@」"), submittedQuery) }
        return nil
    }

    private var shouldShowEmptyResult: Bool {
        !submittedQuery.isEmpty && trimmedQuery == submittedQuery
    }

    var body: some View {
        AdaptiveContentContainer(maxWidth: DSLayout.readableExpandedWidth) {
            VStack(spacing: 0) {
                // No rule under the scope row: as in Apple Books' search, the content
                // starts below the controls, and on iOS 26 the list's soft scroll edge
                // marks where it slides out of view.
                if isAtTabRoot || !enabledSources.isEmpty {
                    sourceScopeBar
                }

                ZStack {
                    if showsCombinedResults || !aggregator.results.isEmpty {
                        resultList
                    } else if aggregator.isSearching {
                        // Progress and the pause control sit in the scope row above.
                        ProgressView(localized("搜索中…"))
                            .frame(maxWidth: .infinity, maxHeight: .infinity)
                            .rootTabTitleScrollAnchor()
                    } else if aggregator.isPaused {
                        pausedPlaceholder
                            .rootTabTitleScrollAnchor()
                    } else if shouldShowEmptyResult {
                        emptyResultView
                            .rootTabTitleScrollAnchor()
                    } else if showsSourcesDirectory {
                        sourcesDirectory
                    } else {
                        SearchIdleContent(
                            isQueryEmpty: trimmedQuery.isEmpty,
                            onSearch: searchAgain,
                            onOpenBook: openRecentBook
                        ) {
                            hintView
                                .rootTabTitleScrollAnchor()
                        }
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            // No page background here: the full-screen one below paints the page. A second one
            // inside the safe area drew the theme's picture again, lower, under the bar and the
            // search field (2026-10-17).
            .background {
                UnifiedSearchFeed(query: showsCombinedResults ? trimmedQuery : "", shelf: shelfSearch,
                                  libraries: librarySearch, aggregator: aggregator,
                                  offersPublicLibraries: offersPublicLibraries
                                      && aggregation.isShownInSearch(SourceInstanceKey(type: .aozora, id: PublicLibraryID.aozora.rawValue)),
                                  model: unifiedSearch)
            }
        }
        .background(PageBackgroundView(scope: .search).ignoresSafeArea())
        .pageBackgroundToolbar(for: .search)
        .modifier(SearchPageTitle(isTabRoot: isTabRoot))
        // Declared here, outside the lazy result containers, so the navigation
        // stack can always see the active destination.
        .modifier(
            SearchResultNavigationModifier(
                mode: .current,
                destination: SearchResultDestination.init(route:)
            )
        )
        // The page's only item-based destination (see `SearchPagePush`).
        .navigationDestination(item: $pushed, destination: SearchPagePushDestination.init(push:))
        .fullScreenCover(item: $recentReaderRoute) { route in
            BookReaderView(bookId: route.id)
                .environmentObject(bookStore)
                .environment(\.readerNavigator, nil)
        }
        // At the tab root on iOS 27 the field rises to the top as the bar slides away.
        .searchable(
            text: $query,
            placement: .navigationBarDrawer(displayMode: .always),
            prompt: localized("输入书名或作者")
        )
        .sheet(isPresented: $showsSourceScopeSheet) {
            SearchSourceScopeSheet(
                enabledSources: enabledSources,
                initialScope: activeScope,
                onSave: applySearchSourceScope
            )
        }
        .sheet(isPresented: $showsSourceGroupEditor) {
            SearchSourceGroupEditor(
                sources: exploreSources,
                existingGroups: directoryGroups,
                preselectedID: groupEditorPreselected
            )
        }
        .onSubmit(of: .search) { submit() }
        .task(id: showsCombinedResults ? trimmedQuery : "") {
            await shelfSearch.search(showsCombinedResults ? trimmedQuery : "", in: bookStore)
        }
        .task {
            // The modules a submit asks are known only once their library has been read, and
            // 搜索 may be the first page opened.
            await RuleModuleLibrary.shared.loadIfNeeded()
        }
        .task(id: offersPublicLibraries) {
            // 青空文库's catalog may not have been read yet when 探索 was never opened.
            if offersPublicLibraries, AozoraCatalogStore.shared.catalog == nil {
                await AozoraCatalogStore.shared.load()
            }
        }
        .onChange(of: query) { _, newValue in
            // Mirror the old clear button: emptying the field resets the search.
            if newValue.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                submittedQuery = ""
                needsSearchResubmission = false
                aggregator.cancelAndClear()
                librarySearch.clear()
                unifiedSearch.clear()
            }
        }
        .alert(
            localized("搜索失败"),
            isPresented: Binding(get: { errorMsg != nil }, set: { if !$0 { errorMsg = nil } })
        ) {
            Button(localized("确认")) { errorMsg = nil }
        } message: {
            Text(errorMsg ?? "")
        }
        // 长按来源配置卡片改名。输入框草稿在弹出前由长按动作填成当前名字。
        .alert(
            localized("重新命名"),
            isPresented: Binding(
                get: { renamingSource != nil },
                set: { if !$0 { renamingSource = nil } }
            )
        ) {
            TextField(localized("名称"), text: $renameText)
            Button(localized("取消"), role: .cancel) { renamingSource = nil }
            Button(localized("确定")) { commitSourceRename() }
        } message: {
            Text(localized("改名后，这张卡片和该来源的发现页会一起更新"))
        }
        .onAppear {
            aggregator.setResultPresentationActive(scenePhase == .active)
            if !initialQuery.isEmpty && query.isEmpty {
                query = initialQuery
                doSearch()
            }
        }
        .onChange(of: scenePhase) { _, phase in
            aggregator.setResultPresentationActive(phase == .active)
        }
    }

    // Shown when a search was paused before any result came back. The ring in the
    // scope row above carries the search on.
    private var pausedPlaceholder: some View {
        ContentUnavailableView {
            UnavailableLabel(localized("已暂停"), systemImage: "pause.circle")
        } description: {
            Text(localized("点击继续搜索剩余来源配置")).font(DSFont.unavailableDescription)
                .foregroundStyle(DSColor.textSecondary)
        }
    }

    // MARK: Source Scope

    /// The filter chips, as Emby's search has them (search 9c): 类型 at the tab's root, whose
    /// list is grouped by kind, and the 来源配置 scope where there are sources; at the other
    /// end, while a search runs or is paused, its progress ring — the one pause / resume
    /// control on the page. Manual companion to
    /// the network-settings auto-pause: tap to pause the in-flight search (battery,
    /// traffic) and again to resume the sources not yet asked. Auto-pause lands in the
    /// same paused state, so the same ring resumes an automatically paused search.
    private var sourceScopeBar: some View {
        HStack(spacing: DSSpacing.sm) {
            if isAtTabRoot {
                SearchKindFilterChip(model: unifiedSearch)
            }
            if !enabledSources.isEmpty {
                // A button, not a menu item: a sheet from a menu is lost on iOS 17.
                SearchSourceScopeCapsule(
                    title: sourceScopeSummary,
                    isCustom: activeScope.mode == .custom,
                    action: { showsSourceScopeSheet = true }
                )
            }
            Spacer(minLength: DSSpacing.sm)
            if isSearchInProgress {
                SearchProgressControl(
                    progress: aggregator.progress,
                    isPaused: aggregator.isPaused,
                    onPause: { aggregator.pause() },
                    onResume: { aggregator.resume() }
                )
                .transition(.opacity)
            }
        }
        .padding(.horizontal, DSSpacing.lg)
        .padding(.vertical, DSSpacing.xs)
        .animation(reduceMotion ? nil : DSAnimation.standard, value: isSearchInProgress)
    }

    private var isSearchInProgress: Bool {
        aggregator.isSearching || aggregator.isPaused
    }

    private var sourceScopeSummary: String {
        switch activeScope.mode {
        case .all:
            return localized("全部来源配置")
        case .custom:
            return String(
                format: localized("已选 %d 个来源配置"),
                activeScope.resolvedSources(from: enabledSources).count
            )
        }
    }

    // MARK: Sources Directory

    /// 搜索 tab 的根页、空查询、没在打字：下半页就是来源配置目录。
    private var showsSourcesDirectory: Bool {
        isAtTabRoot
            && trimmedQuery.isEmpty
            && !isSearchFieldActive
            && !aggregator.isSearching
            && !aggregator.isPaused
            && !exploreSources.isEmpty
    }

    /// 每个书源一张卡，不再按分组合并。
    ///
    /// 旧版把好几个书源塞进「所有来源配置 / 某个分组」一张卡里，点进去还得再挑一次
    /// 才到书源的发现页。现在目录直接平铺每个可发现书源：点按直达它的发现页
    /// (`ExploreNavigationRoute.source`)，长按「重新命名」改卡片上的名字。
    private var sourcesDirectory: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: DSSpacing.xl) {
                sourceGroupBar
                LibrarySection(localized("来源配置")) {
                    NavigationLink(value: ExploreNavigationRoute.sourceManager) {
                        LibrarySectionAccessoryLabel()
                    }
                    .accessibilityLabel(localized("管理来源配置"))
                    .accessibilityIdentifier("search.sources.manage")
                } content: { layout in
                    ForEach(visibleExploreSources) { source in
                        NavigationLink(value: ExploreNavigationRoute.source(sourceURL: source.bookSourceUrl)) {
                            ExploreEntryLabel(
                                title: source.bookSourceName,
                                artwork: nil,
                                layout: layout,
                                glass: true
                            )
                        }
                        .buttonStyle(ExploreTileButtonStyle())
                        .accessibilityLabel(source.bookSourceName)
                        .accessibilityIdentifier("search.source.\(source.id.uuidString)")
                        .contextMenu {
                            Button {
                                renameText = source.bookSourceName
                                renamingSource = source
                            } label: {
                                Label(localized("重新命名"), systemImage: "pencil")
                            }
                            Button {
                                groupEditorPreselected = source.id
                                showsSourceGroupEditor = true
                            } label: {
                                Label(localized("加入分组…"), systemImage: "folder.badge.plus")
                            }
                        }
                    }
                }
            }
            .padding(.horizontal, DSSpacing.lg)
            .padding(.top, DSSpacing.md)
            .padding(.bottom, 28)
        }
        .scrollIndicators(.hidden)
        .scrollDismissesKeyboard(.immediately)
    }

    /// 目录里的来源：与 资源库 同一套过滤（已启用、可发现、有探索地址）。
    private var exploreSources: [BookSource] {
        DiscoverViewModel.exploreSources(in: enabledSources)
    }

    // MARK: 自定义分组

    /// 分组名去掉首尾空白：Legado 允许书源带空分组，视为「未分组」。
    private static func groupName(of source: BookSource) -> String {
        source.bookSourceGroup.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// 目录里出现过的自定义分组，按书源顺序去重，带上该组在目录里的书源数。
    /// 用 `exploreSources` 而不是全库统计，免得 chip 上的数字和目录里能点开的卡片对不上。
    private var directoryGroups: [BookSourceGroupCandidate] {
        var order: [String] = []
        var counts: [String: Int] = [:]
        for source in exploreSources {
            let name = Self.groupName(of: source)
            guard !name.isEmpty else { continue }
            if counts[name] == nil { order.append(name) }
            counts[name, default: 0] += 1
        }
        return order.map { BookSourceGroupCandidate(name: $0, count: counts[$0] ?? 0) }
    }

    /// 选中的分组若已被拆空，自动回到「全部」，不留一个空目录。
    private var activeGroup: String? {
        guard let selected = selectedSourceGroup,
              directoryGroups.contains(where: { $0.name == selected })
        else { return nil }
        return selected
    }

    /// 选了某个分组就只显示这一组的书源（同一组「放在一起」）；「全部」时
    /// 也按分组稳定排序，让同组卡片挨在一起，未分组的排在最后。
    private var visibleExploreSources: [BookSource] {
        if let group = activeGroup {
            return exploreSources.filter { Self.groupName(of: $0) == group }
        }
        let order = Dictionary(
            uniqueKeysWithValues: directoryGroups.enumerated().map { ($0.element.name, $0.offset) }
        )
        let grouped = exploreSources.filter { !Self.groupName(of: $0).isEmpty }
        let ungrouped = exploreSources.filter { Self.groupName(of: $0).isEmpty }
        let sorted = grouped.enumerated().sorted { lhs, rhs in
            let li = order[Self.groupName(of: lhs.element)] ?? .max
            let ri = order[Self.groupName(of: rhs.element)] ?? .max
            return li == ri ? lhs.offset < rhs.offset : li < ri
        }.map { $0.element }
        return sorted + ungrouped
    }

    /// 可横向滑动的分类栏，跟书架分类栏同一套清透玻璃胶囊，受「全局玻璃」总闸控制。
    private var sourceGroupBar: some View {
        ScrollView(.horizontal) {
            HStack(spacing: 4) {
                sourceGroupChip(title: localized("全部"), count: exploreSources.count,
                                isOn: activeGroup == nil) {
                    withAnimation(.snappy(duration: 0.18)) { selectedSourceGroup = nil }
                }
                ForEach(directoryGroups) { group in
                    sourceGroupChip(title: group.name, count: group.count,
                                    isOn: activeGroup == group.name) {
                        withAnimation(.snappy(duration: 0.18)) { selectedSourceGroup = group.name }
                    }
                }
                Button {
                    groupEditorPreselected = nil
                    showsSourceGroupEditor = true
                } label: {
                    Label(localized("自定义分组"), systemImage: "folder.badge.gearshape")
                        .font(.system(size: 13, weight: .medium))
                        .foregroundStyle(DSColor.accent)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 9)
                }
                .buttonStyle(.plain)
                .accessibilityLabel(localized("自定义分组"))
                .accessibilityIdentifier("search.sources.editGroups")
            }
            .padding(4)
        }
        .scrollIndicators(.hidden)
        .clearGlassSurface(in: Capsule())
        .overlay(Capsule().strokeBorder(Color.primary.opacity(0.08), lineWidth: 0.6))
    }

    private func sourceGroupChip(
        title: String,
        count: Int,
        isOn: Bool,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            HStack(spacing: 5) {
                Text(title)
                    .font(.system(size: 13, weight: isOn ? .semibold : .regular))
                    .lineLimit(1)
                Text("\(count)")
                    .font(.system(size: 11, weight: .medium))
                    .monospacedDigit()
                    .foregroundStyle(DSColor.textSecondary)
            }
            .foregroundStyle(isOn ? DSColor.accent : DSColor.textPrimary)
            .padding(.horizontal, 12)
            .padding(.vertical, 9)
            .background {
                if isOn {
                    Capsule().fill(DSColor.accent.opacity(0.16))
                }
            }
        }
        .buttonStyle(.plain)
        .accessibilityLabel(title)
        .accessibilityValue(String(format: localized("%d 个来源配置"), count))
    }

    /// 长按卡片改名：只改书源名字，其余字段按 id 从库里取最新，避免用长按那一刻的
    /// 快照覆盖掉别处的改动。写回走 `BookSourceStore.update`，它会发布变更让这张卡
    /// 和书源管理、发现页标题一起刷新，并跟着 iCloud 同步。
    private func commitSourceRename() {
        guard let target = renamingSource else { return }
        let name = renameText.trimmingCharacters(in: .whitespacesAndNewlines)
        defer { renamingSource = nil }
        guard !name.isEmpty,
              let current = sourceStore.sources.first(where: { $0.id == target.id }),
              name != current.bookSourceName
        else { return }
        var updated = current
        updated.bookSourceName = name
        BookSourceStore.shared.update(updated)
    }

    // MARK: Result List
    @ViewBuilder
    private var resultList: some View {
        if #available(iOS 18.0, *) {
            modernResultList
        } else {
            iOS17ResultList
        }
    }

    @available(iOS 18.0, *)
    private var modernResultList: some View {
        List {
            if showsCombinedResults {
                ModernUnifiedSearchRows(
                    works: unifiedSearch, libraries: librarySearch,
                    sourcesSearching: aggregator.isSearching, sourcesPaused: aggregator.isPaused,
                    submittedQuery: shouldShowEmptyResult ? submittedQuery : nil)
            } else {
                sourceRows
            }
        }
        .modifier(SearchResultsScrollEdges(isTabRoot: isTabRoot))
        .listStyle(.plain)
        .scrollContentBackground(.hidden)
        // Apple Books' result rows carry no disclosure chevron; the whole row opens the book.
        .navigationLinkIndicatorVisibility(.hidden)
    }

    /// The sources' results where the page is not the tab's root, and while there is no
    /// result what the search is doing.
    @available(iOS 18.0, *)
    @ViewBuilder
    private var sourceRows: some View {
        if let sourcesNotice {
            Text(sourcesNotice)
                .font(DSFont.subheadline)
                .foregroundStyle(DSColor.textSecondary)
                .listRowBackground(Color.clear)
                .listRowSeparator(.hidden, edges: .top)
                .background { Color.clear.rootTabTitleScrollAnchor() }
        }
        ForEach(aggregator.results) { book in
            resultLink(for: book)
            .listRowInsets(EdgeInsets(
                top: 0,
                leading: DSLayout.searchListHorizontalInset,
                bottom: 0,
                trailing: DSLayout.searchListHorizontalInset
            ))
            .listRowBackground(Color.clear)
            // No rule over the first result: the scope row above has none either.
            .listRowSeparator(
                book.id == aggregator.results.first?.id ? .hidden : .automatic,
                edges: .top
            )
            .background {
                // The first result measures the list's scroll for the 搜索 tab's title.
                if book.id == aggregator.results.first?.id {
                    Color.clear.rootTabTitleScrollAnchor()
                }
            }
        }
    }

    private var iOS17ResultList: some View {
        IOS17SearchResults(
            works: showsCombinedResults ? unifiedSearch : nil,
            libraries: librarySearch,
            rows: showsCombinedResults ? [] : aggregator.results.map(IOS17SearchResultTableRow.init(searchBook:)),
            sourcesSearching: aggregator.isSearching,
            sourcesPaused: aggregator.isPaused,
            submittedQuery: shouldShowEmptyResult ? submittedQuery : nil,
            onSelect: { id in
                guard let book = aggregator.results.first(where: { $0.id == id }) else {
                    // The row on screen is no longer among the results, so the tap opens
                    // nothing; logged rather than dropped without a trace.
                    AppLogger.error(
                        "⟐ search tap found no result",
                        context: ["id": id.uuidString, "results": aggregator.results.count]
                    )
                    return
                }
                pushed = .result(BookSearchResultRoute(id: id, snapshot: book))
            },
            openWork: { route in pushed = .work(route) }
        )
    }

    private func resultLink(for book: SearchBook) -> some View {
        NavigationLink(
            value: BookSearchResultRoute(id: book.id, snapshot: book)
        ) {
            AggregatedResultRow(book: book)
        }
    }

    // MARK: Empty State
    private var emptyResultView: some View {
        ContentUnavailableView {
            UnavailableLabel(
                String(format: localized("没有找到「%@」"), submittedQuery),
                systemImage: "magnifyingglass"
            )
        } description: {
            Text(localized("尝试换个关键字，或切换来源配置")).font(DSFont.unavailableDescription)
                .foregroundStyle(DSColor.textSecondary)
        }
    }

    @ViewBuilder
    private var hintView: some View {
        if enabledSources.isEmpty, !offersPublicLibraries {
            ContentUnavailableView {
                UnavailableLabel(localized("尚未设置来源配置"), systemImage: "exclamationmark.triangle")
            } description: {
                Text(localized("请先在来源配置管理中新增并启用来源配置")).font(DSFont.unavailableDescription)
                    .foregroundStyle(DSColor.textSecondary)
            }
        } else {
            ContentUnavailableView {
                UnavailableLabel(
                    needsSearchResubmission
                        ? localized("搜索范围已更新，请再次搜索")
                        : localized("输入书名或作者搜索"),
                    systemImage: "text.magnifyingglass"
                )
            }
        }
    }

    // MARK: Search Logic
    private func applySearchSourceScope(_ newScope: SearchSourceScope) {
        guard newScope != activeScope else { return }
        if sessionScope != nil {
            editedSessionScope = newScope
        } else {
            scopeStore.save(newScope)
        }
        submittedQuery = ""
        needsSearchResubmission = !trimmedQuery.isEmpty
        aggregator.cancelAndClear()
    }

    private func doSearch() {
        let q = trimmedQuery
        guard !q.isEmpty else { return }
        let sources = activeScope.resolvedSources(from: enabledSources)
        guard !sources.isEmpty else {
            errorMsg = activeScope.mode == .custom
                ? localized("请至少选择一个可用来源配置")
                : localized("没有可用的来源配置，请先启用来源配置")
            return
        }

        needsSearchResubmission = false
        submittedQuery = q
        recentQueries = recentQueries.recording(q)
        aggregator.search(query: q, sources: sources)
    }

    /// The keyboard's Search: the saved libraries with Gutenberg where it is offered, the
    /// modules, Open Library and the sources. Ignored while the source library is still being
    /// read, so a large library is not taken for none.
    private func submit() {
        // At the tab's root, the parts that answer on submit are asked first, whatever the
        // sources do.
        let atRoot = isTabRoot && tabNavigation != nil
        var othersAnswer = false
        if atRoot, !trimmedQuery.isEmpty {
            if librarySearch.isAvailable {
                librarySearch.start(trimmedQuery, store: bookStore)
                othersAnswer = true
            }
        }
        switch SearchSubmitPlan.decide(hasSources: !enabledSources.isEmpty, sourcesLoaded: sourceStore.isLoaded,
                                       othersAnswer: othersAnswer) {
        case .sources:
            doSearch()
        case .othersOnly:
            // Nothing to ask of the sources; the list's empty state waits for the others.
            submittedQuery = trimmedQuery
            recentQueries = recentQueries.recording(trimmedQuery)
        case .waitForSources:
            break
        }
    }

    /// 最近搜索: the same search again, as if typed and submitted.
    private func searchAgain(_ recent: String) {
        query = recent
        submit()
    }

    /// 最近阅读: back into the book where it was left. Its reader moves it to the front of
    /// 最近阅读, as every open does.
    private func openRecentBook(_ book: ReadingBook) {
        // An audiobook's player grows out of the now-playing bar, as Apple Books opens one.
        if NowPlayingHub.shared.openIfAudiobook(book, store: bookStore) { return }
        recentReaderRoute = DetailReaderRoute(id: book.id)
    }
}

// MARK: - 搜索页自定义分组编辑器

/// 搜索页书源目录的「自定义分组」：勾选好几个书源，一次性放进一个分组。
/// 写回统一走 `BookSourceStore.setGroup(_:ids:)` —— 与书源管理页、资源库的分组是
/// 同一份 `bookSourceGroup` 数据，会跟着 iCloud 同步，不会另立一份偏好设置。
private struct SearchSourceGroupEditor: View {
    let sources: [BookSource]
    let existingGroups: [BookSourceGroupCandidate]
    let preselectedID: UUID?

    @Environment(\.dismiss) private var dismiss
    @State private var selection: Set<UUID>
    @State private var newGroupName = ""
    @State private var query = ""

    init(
        sources: [BookSource],
        existingGroups: [BookSourceGroupCandidate],
        preselectedID: UUID?
    ) {
        self.sources = sources
        self.existingGroups = existingGroups
        self.preselectedID = preselectedID
        // 长按某张卡片进来时先勾上它；从分类栏「自定义分组」进来则不预选。
        // 放在 init 而不是 onAppear，避免 sheet 内容重建时把用户已勾的清掉。
        _selection = State(initialValue: preselectedID.map { Set([$0]) } ?? [])
    }

    private var trimmedName: String {
        newGroupName.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private var filteredSources: [BookSource] {
        let needle = query.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !needle.isEmpty else { return sources }
        return sources.filter { $0.bookSourceName.lowercased().contains(needle) }
    }

    var body: some View {
        NavigationStack {
            List {
                Section {
                    TextField(localized("新分组名称"), text: $newGroupName)
                } header: {
                    Text(localized("新建分组"))
                } footer: {
                    Text(localized("输入名称创建新分组，或直接点下方已有分组；选好书源后点右上角「加入分组」。"))
                }
                .interfaceSectionSurface()

                if !existingGroups.isEmpty {
                    Section {
                        ForEach(existingGroups) { group in
                            Button {
                                newGroupName = group.name
                            } label: {
                                HStack(spacing: DSSpacing.sm) {
                                    Label(group.name, systemImage: "folder")
                                        .foregroundStyle(
                                            trimmedName == group.name ? DSColor.accent : DSColor.textPrimary
                                        )
                                        .lineLimit(1)
                                    Spacer(minLength: DSSpacing.sm)
                                    if trimmedName == group.name {
                                        Image(systemName: "checkmark")
                                            .foregroundStyle(DSColor.accent)
                                    }
                                    Text("\(group.count)")
                                        .font(DSFont.subheadline)
                                        .foregroundStyle(DSColor.textSecondary)
                                        .monospacedDigit()
                                }
                            }
                        }
                    } header: {
                        Text(localized("已有分组"))
                    }
                    .interfaceSectionSurface()
                }

                Section {
                    ForEach(filteredSources) { source in
                        Button {
                            toggle(source.id)
                        } label: {
                            HStack(spacing: DSSpacing.sm) {
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(source.bookSourceName.isEmpty
                                         ? localized("未命名来源配置") : source.bookSourceName)
                                        .font(DSFont.subheadline)
                                        .foregroundStyle(DSColor.textPrimary)
                                        .lineLimit(1)
                                    let group = source.bookSourceGroup
                                        .trimmingCharacters(in: .whitespacesAndNewlines)
                                    if !group.isEmpty {
                                        Text(group)
                                            .font(DSFont.footnote)
                                            .foregroundStyle(DSColor.textSecondary)
                                            .lineLimit(1)
                                    }
                                }
                                Spacer(minLength: DSSpacing.sm)
                                Image(systemName: selection.contains(source.id)
                                      ? "checkmark.circle.fill" : "circle")
                                    .foregroundStyle(selection.contains(source.id)
                                                     ? DSColor.accent : DSColor.textSecondary)
                            }
                        }
                        .accessibilityLabel(source.bookSourceName)
                    }
                } header: {
                    Text(String(format: localized("已选 %d 个来源配置"), selection.count))
                }
                .interfaceSectionSurface()

                if !selection.isEmpty {
                    Section {
                        Button(role: .destructive) {
                            BookSourceStore.shared.setGroup("", ids: selection)
                            dismiss()
                        } label: {
                            Label(localized("移出分组（回到未分组）"), systemImage: "folder.badge.minus")
                                .foregroundStyle(DSColor.textPrimary)
                        }
                    }
                    .interfaceSectionSurface()
                }
            }
            .softScrollEdges()
            .listStyle(.insetGrouped)
            .scrollContentBackground(.hidden)
            .searchable(
                text: $query,
                placement: .navigationBarDrawer(displayMode: .always),
                prompt: localized("搜索来源配置")
            )
            .navigationTitle(localized("自定义分组"))
            .toolbarTitleDisplayMode(.inline)
            .themedAppSurface(for: .settings)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button(localized("取消")) { dismiss() }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        BookSourceStore.shared.setGroup(trimmedName, ids: selection)
                        dismiss()
                    } label: {
                        Text(localized("加入分组"))
                    }
                    .disabled(selection.isEmpty || trimmedName.isEmpty)
                }
            }
        }
    }

    private func toggle(_ id: UUID) {
        if selection.contains(id) {
            selection.remove(id)
        } else {
            selection.insert(id)
        }
    }
}

// MARK: - Aggregated Result Row

/// One search result as Apple Books lists one in its search (`SearchBookListRow`): the
/// cover, the title with the grey 有声书 tag on audiobooks, the author, and the kind and
/// source count in grey — 「小说 · 3 源」. Mirrors `IOS17SearchResultTableCell`, which draws
/// the same row in UIKit on iOS 17.
struct AggregatedResultRow: View {
    let book: SearchBook

    var body: some View {
        SearchBookListRow(content: SearchBookListRowContent(result: book)) {
            BookCoverImage(
                coverURL: book.coverUrl,
                title: book.displayName,
                author: book.author
            )
        }
    }
}

// MARK: - OnlineBook Identifiable (for sheet item)
extension OnlineBook: Hashable {
    static func == (lhs: OnlineBook, rhs: OnlineBook) -> Bool {
        lhs.id == rhs.id
    }
    func hash(into hasher: inout Hasher) {
        hasher.combine(id)
    }
}

// MARK: - SearchBook Identifiable (for sheet item)
extension SearchBook: Hashable {
    static func == (lhs: SearchBook, rhs: SearchBook) -> Bool {
        lhs.id == rhs.id
    }
    func hash(into hasher: inout Hasher) {
        hasher.combine(id)
    }
}

#Preview("搜索") {
    NavigationStack {
        BookSearchView()
            .environmentObject(BookStore())
    }
}
