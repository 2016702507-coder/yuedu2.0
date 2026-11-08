import SwiftUI

/// 探索's root since unified library 5c-3 (design §13.3): the reader's sections, in their order,
/// across every source — Emby's model under Apple Books' covers (Phase 5 plan, settled
/// decision 11). Its one ••• (decision 36, 2026-10-13, which took 范围 away) holds every other
/// way in but 首页配置's (5d-4, decision 22), a button of its own since 2026-10-22: 编辑首页,
/// 聚合设置, and the browser (5d-1, settled
/// decision 12, which took 我的书库 off the home). 古腾堡 and 青空文库 have no page of shelves
/// since 2026-10-22: their lists are rows here, and 资源库 says what they offer. There is no
/// catalog entry at the top (decision 20's, removed 2026-10-11 by the maintainer): a reader adds the sections
/// they want, and a row's 查看全部 opens the rest of what it shows.
///
/// - One stack for everything the home opens (decision 5): Explore's routes, the libraries'
///   feeds, folders and books, the store's pages, and the store's card carousel over it all.
/// - The page is read once the book-source library is read (its stack shows 载入中 until
///   then), and the defaults are saved then, for good but for 预设's official modules' lists,
///   which follow the language (`HomePageStore.pageOrDefaults`).
/// - Rows are built again when the page (or the 首页配置 chosen), the sources, the connections or
///   the region change. Rows read from this device load again when the home comes back into
///   view, never on a shelf change: a page turn is one.
/// - Books are searched from the 搜索 tab. The field that narrowed 我的书库's book sources went
///   with it.
struct ExploreHome: View {
    @ObservedObject var browser: BrowserState
    @EnvironmentObject private var store: BookStore

    var body: some View {
        // The store is handed down, not observed: every reading-position save publishes it.
        ExploreHomeRoot(store: store, browser: browser)
    }
}

private struct ExploreHomeRoot: View {
    let store: BookStore
    @ObservedObject var browser: BrowserState

    @StateObject private var model: HomeModel
    @ObservedObject private var pageStore = HomePageStore.shared
    @ObservedObject private var sourceStore = BookSourceStore.shared
    @ObservedObject private var connections = RemoteLibraryConnectionStore.shared
    @ObservedObject private var availability = PublicLibraryAvailability.shared
    @ObservedObject private var tabModel = ExploreTabModel.shared
    @ObservedObject private var aozora = AozoraCatalogStore.shared
    @ObservedObject private var aggregation = AggregationSettingsStore.shared
    /// Its installs, updates and removals change the rows (Phase 6f).
    @ObservedObject private var modules = RuleModuleLibrary.shared
    @AppStorage(ExploreSettings.modeKey) private var storedMode = ExploreMode.publicLibraries.rawValue
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    @State private var path = NavigationPath()
    @State private var exploreSources: [BookSource] = []
    @State private var browserPresentation: BrowserPresentation?
    /// 编辑首页: the sections drawn as cards to show, hide, reorder and open (5d-2).
    @State private var isEditing = false
    /// 编辑首页's bars, the bar's 完成 and the ＋ where the tab bar was: `isEditing`, but set
    /// without the morph's animation (`setEditing(_:)`).
    @State private var showsEditorBars = false
    /// 新增栏目's sheet (5d-5).
    @State private var addsSection = false
    /// The section 新增栏目 just added, brought into view: it is at the end of the home.
    @State private var addedSection: UUID?
    /// iOS 17: ••• is a chooser sheet, and what was picked runs once it is gone
    /// (Technotes/iOS17MenuModalPresentation.md).
    @State private var showsMoreChooser = false
    @State private var moreSequence = DismissalSequencedPresentation<ExploreMoreAction>()
    /// Set as the home is edited or done, until the reader drags the page: the page keeps to
    /// its end, where 编辑首页 and 完成 are, while the other mode lays out.
    @State private var followsEnd = false
    /// The safe area under the page: the tab bar's, or the ＋'s bar while the home is edited.
    @State private var bottomInset: CGFloat = 0
    /// The page's width, which each section keeps in its card while the home is edited.
    @State private var pageWidth: CGFloat = 0
    /// The 顶部轮播图's height, and whether it is still under the bar: the bar's 探索 and
    /// buttons are white on its colour (maintainer, 2026-10-27).
    @State private var carouselHeight: CGFloat = 0
    @State private var barIsOverCarousel = true
    /// The 轮播图 draws its band, as its row reports it (`HomeCarouselBandKey`).
    @State private var carouselDrawsBand = false
    /// 选择轮播数据, from 编辑首页's header or the 轮播图's long press.
    @State private var choosesCarousel = false

    private struct BrowserPresentation: Identifiable {
        let id = UUID()
        let entry: BrowserEntry
    }

    init(store: BookStore, browser: BrowserState) {
        self.store = store
        self.browser = browser
        _model = StateObject(wrappedValue: HomeModel.live(shelf: store))
    }

    // MARK: State

    /// The top of the home, where another 首页配置 opens.
    private static let top = "home.top"

    private var mode: ExploreMode {
        ExploreMode.effective(stored: .storedValue(storedMode, hasImportedSources: tabModel.hasSources),
                              hasImportedSources: tabModel.hasSources, librariesAvailable: availability.isAvailable)
    }

    /// Whom the defaults are for: a new install's 预设, and 预设配置's 首页配置 (maintainer,
    /// 2026-10-23).
    private var defaultsContext: HomePageDefaults.Context {
        HomePageDefaults.Context(mode: mode, publicLibrariesAvailable: availability.isAvailable,
                                 languages: aggregation.readingLanguages.languages)
    }

    /// The sections drawn, in the reader's languages' order (聚合设置, 5d-3d). Built again on each
    /// read, several per body: a span, so a main-thread stall during it is named.
    private var groups: [HomeSectionGroup] {
        SourcePerfTrace.span("home.groups", "rows=\(model.rows.count)", thresholdMs: 16) {
            let lookup = store.copyLookup()
            return model.groups(in: nil, languages: aggregation.readingLanguages,
                                readFilter: HomeReadFilter(hides: aggregation.hidesRead, isRead: lookup.isRead))
        }
    }

    /// The 顶部轮播图's section: the page's first band (`HomePage.carouselSection`); before the
    /// page's first read saves it, the first the home draws.
    private var carouselID: UUID? {
        pageStore.page.map { $0.carouselSection?.id }
            ?? groups.lazy.map(\.section).first { $0.layout == .band && $0.isEditable }?.id
    }

    /// The 顶部轮播图 as the home draws it: nil while it is hidden or has nothing to show.
    private var carouselGroup: HomeSectionGroup? {
        guard let carouselID else { return nil }
        return groups.first { $0.section.id == carouselID && !$0.isSettledEmpty }
    }

    /// The bar is over the 轮播图's band: its colour, not the page's under a carousel drawn
    /// without one.
    private var barIsOverColor: Bool {
        !isEditing && barIsOverCarousel && carouselGroup != nil && carouselDrawsBand
    }

    /// The home's sections, each one view in and out of 编辑首页 (`HomeSectionSlot`): one list
    /// in both, the sections drawn and every section 编辑首页 lists, so the morph changes no
    /// section's place in it, and its cards the home's books, so it changes no row either. The
    /// 顶部轮播图 is none of them: it is drawn above them, and 编辑首页's header sets it.
    private var sectionEntries: [HomeSectionEntry] {
        let drawn = groups
        let home = Dictionary(drawn.map { ($0.section.id, $0) }, uniquingKeysWith: { first, _ in first })
        let editable = pageStore.page?.editableSections.map(\.id) ?? []
        let carousel = carouselID
        // The page before its first read saves it: what the home draws.
        return (pageStore.page?.sections ?? drawn.map(\.section)).compactMap { section in
            guard section.id != carousel else { return nil }
            let editableIndex = editable.firstIndex(of: section.id)
            guard home[section.id] != nil || editableIndex != nil else { return nil }
            return HomeSectionEntry(section: section, homeGroup: home[section.id], editableIndex: editableIndex)
        }
    }

    /// What the rows are built from; any change builds them again.
    private var syncKey: [AnyHashable] {
        // 中继资料语言偏好推荐: a module's 地区 that follows it reads it.
        [tabModel.isLoaded, pageStore.page, connections.catalogs.map(\.id), exploreSources.map(\.bookSourceUrl), availability.isAvailable,
         aozora.catalog != nil, aggregation.settings.hiddenFromLatest, aggregation.readingLanguages.language,
         modules.modules.map { "\($0.module.id)@\($0.module.version)" }]
    }

    /// Every section is settled with nothing in it, so the home would be blank: a China
    /// storefront with no source and nothing read yet, a source no section draws from, or a
    /// 首页配置 with no section shown.
    private var showsNothing: Bool {
        groups.allSatisfy(\.isSettledEmpty)
    }

    /// The selected 首页配置 shows no section at all: none left, or every one hidden.
    private var hasNoSections: Bool {
        !(pageStore.page?.sections.contains { $0.isEnabled && $0.isEditable } ?? false)
    }

    private var selectedConfiguration: HomeConfigurationListing? {
        pageStore.configurations.first { $0.id == pageStore.selectedConfiguration }
    }

    // MARK: Body

    var body: some View {
        // The stack is there from the tab's first frame, the source library read or not, and
        // stays the same stack. On iOS 17 a tab whose content had no navigation stack on its
        // first frame never hands the status bar or the tab bar to the pages pushed on it, and
        // 探索 is the tab the app opens on: built only once the library had been read, the stack
        // left the status bar, the tab bar and the home indicator over every reader 探索 pushed —
        // 继续阅读's, 作品详情's, a library's — while 书架's, which UIKit pushes, hid them (FB-100,
        // iOS 17.7.2; on the iOS 17.5 simulator the tab's hosting controller named no child for
        // the status bar).
        NavigationStack(path: $path) {
            if tabModel.isLoaded {
                home
                .toolbar { toolbar }
                // 编辑首页 hides the tab bar while the home is being edited, as 书架's 选取 does, and
                // its ＋ takes the bar's place (maintainer, 2026-10-17).
                .hidesRootTabBar(showsEditorBars)
                .exploreRouteDestinations(openBrowser: openBrowser)
                .homeEditDestinations()
                .remoteLibraryDestinations()
                .publicLibraryDestinations()
            } else {
                // The source library is still being read (about a second at 50 000 sources); the
                // home's default sections depend on whether it holds any, and are saved for good
                // the first time it draws.
                ProgressView()
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        // Both covers on the stack, not its root: on iOS 26.4.x a cover on the root had its content
        // built again whenever anything was presented over it, 选择内容来源's sheet or a filter's
        // menu, and 新增栏目 fell back to the layout gallery (#51; iOS 26.4.1 simulator, not 26.5 or
        // 18.6). The browser's 书签 sheet closed as it opened there too (`BrowserCoverUITests`).
        // Full screen, as Forward's 选择模板: the gallery's previews run to the screen's edges.
        .fullScreenCover(isPresented: $addsSection) {
            HomeNewSectionSheet(added: { addedSection = $0; addsSection = false }, close: { addsSection = false })
                .environmentObject(store)
        }
        .fullScreenCover(item: $browserPresentation) { presentation in
            NavigationStack {
                BrowserPage(browser: browser, entry: presentation.entry)
            }
            .environmentObject(store)
        }
        // The store's card carousel is off the home for now (Phase 5 plan, decision 27): a store
        // page's book opens 作品详情 as the home's cards do. `PublicLibraryBookSheet` stays.
        .environment(\.openPublicLibraryBooks) { selection in
            if let book = selection.selectedBook { path.append(WorkDetailRoute(book)) }
        }
        .environment(\.explorePush) { $0.open(in: &path, store: store) }
        .environment(\.homeDefaults, defaultsContext)
        .task(id: syncKey) {
            // Saved here, not while drawing: the first read saves the defaults. Not before the
            // library is read: the defaults depend on whether it holds any source.
            guard tabModel.isLoaded else { return }
            await model.sync(with: pageStore.pageOrDefaults(mode: defaultsContext.mode,
                                                            publicLibrariesAvailable: defaultsContext.publicLibrariesAvailable,
                                                            languages: defaultsContext.languages),
                             hiddenFromLatest: Set(aggregation.settings.hiddenFromLatest ?? []))
        }
        // After the library is read, as when the home was built only then.
        .task(id: tabModel.isLoaded) {
            guard tabModel.isLoaded else { return }
            await aozora.load()
        }
        .onReceive(sourceStore.sourcesPublisher) { library in
            // Not the placeholder `[]` published until the library is read. The read's own
            // publish passes. The published value, not the store: the publisher sends before
            // the store holds it.
            guard sourceStore.isLoaded else { return }
            exploreSources = DiscoverViewModel.exploreSources(in: library)
        }
    }

    // MARK: 全部

    private var home: some View {
        ScrollViewReader { proxy in
        ScrollView {
            // Each section has the gap after it (`HomeSectionSlot`), going with it where only the
            // home or only the editor gives it room.
            VStack(alignment: .leading, spacing: 0) {
                Color.clear.frame(height: 0).id(Self.top)
                top
                VStack(alignment: .leading, spacing: 0) {
                    LazyVStack(alignment: .leading, spacing: 0) {
                        let entries = sectionEntries
                        let editableCount = entries.count(where: { $0.editableIndex != nil })
                        ForEach(entries) { entry in
                            HomeSectionSlot(entry: entry, isEditing: isEditing, pageWidth: pageWidth, count: editableCount,
                                            openSettings: { path.append(HomeEditRoute.section($0)) }) { group in
                                groupHost(group, model: model, isEditable: true)
                            }
                            .id(entry.id)
                        }
                    }
                    // Over a home with nothing drawn, the button is the empty state's own.
                    if model.isReady, isEditing || !showsNothing {
                        // At the end of the home (maintainer, 2026-10-11, decision 18). Out of the lazy
                        // stack, so it is always there to scroll to.
                        Button { setEditing(!isEditing) } label: { HomeEditButtonTitle(isEditing: isEditing) }
                            .buttonStyle(.bordered)
                            // One piece moving with the page through the morph. Without it the button just
                            // tapped moved by its press's animation instead, sinking under the ＋'s bar and
                            // coming back, and its new title was drawn where it ends up while the page was
                            // still scrolling there, below its capsule (iOS 27 simulator).
                            .geometryGroup()
                            .frame(maxWidth: .infinity)
                            .accessibilityLabel(localized(isEditing ? "完成" : "编辑首页"))
                            .accessibilityIdentifier(isEditing ? "home.editDone" : "home.edit")
                    }
                }
                .padding(.vertical, DSSpacing.lg)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .onGeometryChange(for: CGFloat.self) { $0.size.width } action: { pageWidth = $0 }
            .homeEditMorph(isEditing)
            .rootTabTitleScrollAnchor()
            // Both ways the home opens at its end, where 编辑首页 and 完成 are (maintainer,
            // 2026-10-17). The cards are taller than the rows, and the offset the scroll view
            // kept showed the editor's middle on the way in and, past the end of the shorter
            // home, nothing at all on the way out. The page travels to its end with the morph,
            // frame by frame, from as far above it as it was, then follows it through the passes
            // the other mode lays out over, its lazy stack measuring the cards it reaches (884,
            // 1505, 1773, 1749 and 1727 points tall within 100 ms, iOS 27 simulator), until the
            // reader scrolls it off its end — a drag, or VoiceOver's or the status bar's scroll,
            // which no section changing its size afterwards takes back. And through the bars
            // that come and go with the editor: the tab bar, back after the ＋'s bar was gone,
            // covered 编辑首页 the page had just followed (iOS 18.6 simulator).
            .pinsScrollToEnd(followsEnd, through: isEditing, bottomInset: bottomInset) { followsEnd = false }
            // A drag lets go at once, the morph's hold too.
            .onScrollDragBegan { followsEnd = false }
        }
        .onGeometryChange(for: CGFloat.self) { $0.safeAreaInsets.bottom } action: { bottomInset = $0 }
        .onChange(of: addedSection) { _, added in
            guard let added else { return }
            followsEnd = false
            withAnimation(reduceMotion ? nil : DSAnimation.standard) { proxy.scrollTo(added, anchor: .center) }
            addedSection = nil
        }
        // 编辑首页 edits one 首页配置; deleting it, the one 预设 takes the place of, ends the edit.
        // Another 首页配置 picked on its page is another page, opening at its top. Kept where the
        // page was, every section's identity changed under an offset deep into the home, and its
        // lazy stack drew no row at all, at that offset or any scrolled to after, and not after
        // switching back either: the home stayed blank but for 编辑首页 (iOS 27 simulator,
        // 2026-10-23; the maintainer's 「切换完还是空白的」).
        .onChange(of: pageStore.selectedConfiguration) { _, _ in
            if isEditing {
                setEditing(false)
            } else {
                followsEnd = false
                proxy.scrollTo(Self.top, anchor: .top)
            }
        }
        }
        .overlay {
            if !model.isReady {
                ProgressView()
            } else if showsNothing, !isEditing {
                ContentUnavailableView {
                    if hasNoSections {
                        UnavailableLabel(localized("这个首页配置还没有栏目"), systemImage: "rectangle.stack")
                    } else {
                        UnavailableLabel(localized("探索还没有内容"), systemImage: "rectangle.stack")
                    }
                } actions: {
                    UnavailableActions {
                        if hasNoSections {
                            Button(localized("新增栏目")) { addsSection = true }
                                .buttonStyle(.onAccentProminent)
                                .accessibilityIdentifier("home.addSection")
                        }
                        Button(localized("编辑首页")) { setEditing(true) }
                            .buttonStyle(.bordered)
                            .accessibilityIdentifier("home.edit")
                    }
                }
            }
        }
        .refreshable { await refresh() }
        // Again when a sync changes the rows: a Gutenberg row added while the home shows.
        .task(id: model.rows.map(\.id)) { model.homeAppeared(in: nil) }
        // On the stack's root, not the stack: coming back from a page the home pushed is coming
        // back into view too. An article read there reads as read; a book read from 作品详情
        // moves in 继续阅读.
        .onAppear {
            model.reloadLocal()
        }
        .background(PageBackgroundView(scope: .explore).ignoresSafeArea())
        .pageBackgroundToolbar(for: .explore)
        // While the home is edited the bar stays, for its 完成 (maintainer, 2026-10-17).
        .rootTabTitle(localized("探索"), onScroll: isEditing ? .fadesTitle : .minimizesBar, overColor: barIsOverColor)
        .navigationDestination(isPresented: $choosesCarousel) { carouselPicker }
        .animation(reduceMotion ? nil : DSAnimation.standard, value: groups.map(\.id))
    }

    // MARK: 顶部轮播图

    /// The 顶部轮播图 at the top of the home, from edge to edge, its colour up behind the bars
    /// (maintainer, 2026-10-27); 编辑首页's header in its place while the home is edited.
    @ViewBuilder
    private var top: some View {
        if isEditing {
            HomeEditorHeader(openConfigurations: { path.append(HomeEditRoute.configurations) },
                             chooseCarousel: { choosesCarousel = true })
                .transition(.opacity)
        } else if let carouselGroup {
            HomeRowHost(group: carouselGroup, store: store, aozoraIndex: aozora.catalog, model: model, isEditable: true,
                        push: push, openSettings: { choosesCarousel = true })
                .environment(\.homeRowIsCarousel, true)
                .onGeometryChange(for: CGFloat.self) { $0.size.height } action: { carouselHeight = $0 }
                .onPreferenceChange(HomeCarouselBandKey.self) { carouselDrawsBand = $0 }
                // Until it has scrolled out from under the bar.
                .reportsScrollOffset { offset in
                    let isUnder = offset < carouselHeight
                    if isUnder != barIsOverCarousel { barIsOverCarousel = isUnder }
                }
                .transition(.opacity)
        }
    }

    /// 选择内容来源 for the 轮播图: what draws books, its chosen item checked. A choice shows it.
    private var carouselPicker: some View {
        let carousel = pageStore.page?.carouselSection
        return HomeContentSourcePicker(current: carousel?.binding, parameters: carousel?.parameters ?? [:], isPushed: true,
                                       title: localized("选择轮播数据")) { choice in
            // Named by its binding, or by the item where the binding cannot name itself, as
            // 新增栏目 names a section (`HomeSectionEditor.choose`).
            let ownName = HomeSection(layout: .band, binding: choice.binding).displayTitle(sourceName: "")
            pageStore.edit {
                $0.setCarousel(choice.binding, parameters: choice.parameters, title: ownName.isEmpty ? choice.itemTitle : "")
            }
            choosesCarousel = false
        } cancel: {
            choosesCarousel = false
        }
        .environment(\.homePickerOffersBooksOnly, true)
        .hidesRootTabBar()
    }

    private func groupHost(_ group: HomeSectionGroup, model: HomeModel, isEditable: Bool) -> some View {
        HomeRowHost(group: group, store: store, aozoraIndex: aozora.catalog, model: model, isEditable: isEditable,
                    push: push,
                    openSettings: { path.append(HomeEditRoute.section(group.section.id)) })
    }

    /// Pull to refresh, and ••• → 重新整理.
    private func refresh() async {
        model.reload()
        // 订阅的最新文章 shows what the RSS tab stored; refreshing fetches the feeds too, as the
        // RSS tab's own refresh does (decision 29), then reads them again.
        async let feeds: Void = refreshSubscriptions()
        // 青空文库's rows are read from its catalog. Refreshing checks for it again, as 青空文库's
        // own page does, instead of waiting out the daily check: a device that found none (the
        // catalog went unpublished until 2026-10-11) would wait a day.
        if availability.isAvailable { await aozora.load(forceRefresh: true) }
        await feeds
    }

    /// Only when a section the home shows reads the feeds: a home without one sends nothing.
    private func refreshSubscriptions() async {
        guard groups.contains(where: { $0.section.binding == .subscriptionArticles }) else { return }
        await RSSFeedRefreshService.refreshAll()
        model.reloadLocal()
    }

    /// The sections morph into their cards and back (`HomeSectionSlot`, maintainer, 2026-10-21),
    /// the page taken to its end along the way (`pinsScrollToEnd`). Reduce Motion switches at once.
    private func setEditing(_ editing: Bool) {
        // The bars change at the tap, outside the morph. Changed in it, the page drew another
        // offset than the one it was set to: after 完成 the drawn one stayed some 400 points past
        // the end the page is pinned to for 0.2 s, blank under 编辑首页, then jumped, with no
        // animation on the scroll view's layer (iOS 26.5 simulator; 27 and 17 drew the set one).
        // Changed outside, the drawn offset is the set one, a frame behind, though the safe area
        // still eases into the tab bar's there.
        withAnimation(nil) { showsEditorBars = editing }
        // In the morph's own update: set before it, the page was put at its end a frame early.
        withAnimation(reduceMotion ? nil : DSAnimation.homeEditMorph) {
            followsEnd = true
            isEditing = editing
        }
    }

    // MARK: Toolbar

    @ToolbarContentBuilder
    private var toolbar: some ToolbarContent {
        if showsEditorBars {
            ToolbarItem(placement: .confirmationAction) {
                Button(localized("完成")) { setEditing(false) }
                    .accessibilityIdentifier("home.editDoneBar")
            }
            // 新增栏目: a ＋ in the middle, where the tab bar was, as in the maintainer's reference
            // app (2026-10-17).
            ToolbarItemGroup(placement: .bottomBar) {
                Spacer()
                Button { addsSection = true } label: {
                    Image(systemName: "plus")
                        .accessibilityHidden(true)
                }
                .accessibilityLabel(localized("新增栏目"))
                .accessibilityIdentifier("homeEditor.addSection")
                Spacer()
            }
        } else {
            ToolbarItem(placement: .topBarTrailing) { configurationsButton.rootTabBarButton(overColor: barIsOverColor) }
            // 首页配置 in its own glass, apart from ••• (maintainer, 2026-10-22).
            #if compiler(>=6.2)
            if #available(iOS 26.0, *) {
                ToolbarSpacer(.fixed, placement: .topBarTrailing)
            }
            #endif
            ToolbarItem(placement: .topBarTrailing) { moreControl.rootTabBarButton(overColor: barIsOverColor) }
        }
    }

    /// 首页配置's page, a button of its own since 2026-10-22 (maintainer, after Rex's 管理配置):
    /// ••• had it as a submenu.
    private var configurationsButton: some View {
        Button { path.append(HomeEditRoute.configurations) } label: {
            Image(systemName: "square.stack")
                .accessibilityHidden(true)
        }
        .accessibilityLabel(localized("首页配置"))
        .accessibilityValue(selectedConfiguration?.name ?? "")
        .accessibilityIdentifier("explore.configurations")
    }

    /// 探索's one ••• (Phase 5 plan, decisions 30 and 36). A native menu from iOS 18; on iOS 17
    /// a chooser sheet, since the browser's cover would be dropped while the menu dismisses.
    @ViewBuilder
    private var moreControl: some View {
        if MenuModalPresentationPolicy.requiresDismissalSequencedChooser {
            Button {
                moreSequence.cancel()
                showsMoreChooser = true
            } label: {
                Image(systemName: "ellipsis")
                    .accessibilityHidden(true)
            }
            .accessibilityLabel(localized("更多"))
            .accessibilityIdentifier("explore.more")
            .sheet(isPresented: $showsMoreChooser, onDismiss: {
                moreSequence.consumeAfterDismissal().map(perform)
            }) {
                AdaptiveSheetContainer(maxWidth: DSLayout.readableCompactWidth) {
                    DismissalSequencedActionChooser(title: localized("更多"), actions: moreChoices,
                                                    onSelect: { moreSequence.select($0) })
                }
            }
        } else {
            ExploreMoreMenu(perform: perform)
        }
    }

    /// The chooser's rows: the menu's items.
    private var moreChoices: [DismissalSequencedAction<ExploreMoreAction>] {
        [
            DismissalSequencedAction(route: .editHome, title: localized("编辑首页"), systemImage: "pencil"),
            DismissalSequencedAction(route: .readingLanguages, title: localized("中继资料语言偏好推荐"), systemImage: "globe"),
            DismissalSequencedAction(route: .aggregatedSources, title: localized("参与聚合的来源"),
                                     systemImage: "square.stack.3d.up"),
            DismissalSequencedAction(route: .refresh, title: localized("重新整理"), systemImage: "arrow.clockwise"),
            DismissalSequencedAction(route: .browser, title: localized("浏览器"), systemImage: "safari"),
        ]
    }

    private func perform(_ action: ExploreMoreAction) {
        switch action {
        case .editHome:
            setEditing(true)
        case .readingLanguages, .aggregatedSources:
            // Both are 聚合设置's (decision 36): the languages are its first section.
            path.append(ExploreNavigationRoute.aggregationSettings)
        case .refresh:
            Task { await refresh() }
        case .browser:
            openBrowser(.resume)
        }
    }

    // MARK: Opening

    private func push(_ push: ExplorePush) {
        push.open(in: &path, store: store)
    }

    private func openBrowser(_ entry: BrowserEntry) {
        browserPresentation = BrowserPresentation(entry: entry)
    }
}

// MARK: - A section

/// One section, resolved against the shelf when it draws. Its own view, so a section that did
/// not change is not drawn again when another one loads.
struct HomeRowHost: View {
    let group: HomeSectionGroup
    let store: BookStore
    let aozoraIndex: AozoraCatalogIndex?
    let model: HomeModel
    /// A section of the reader's home: its long press edits the 首页配置. A library's own sections
    /// are made, not saved, and have nothing to edit.
    let isEditable: Bool
    let push: (ExplorePush) -> Void
    let openSettings: () -> Void
    @State private var confirmsDelete = false

    var body: some View {
        row
            .homeSectionDeleteConfirmation(isPresented: $confirmsDelete, title: group.section.editorTitle()) {
                HomePageStore.shared.edit { $0.removeSection(group.section.id) }
            }
    }

    @ViewBuilder
    private var row: some View {
        // In a layout of lists, AI 推荐 is a card of its list, opening its page.
        if group.section.binding == .aiRecommendations, !group.section.drawsLists {
            AIRecommendationRow(section: group.section, title: group.title, actions: actions, open: open)
        } else {
            rowView
        }
    }

    private var rowView: some View {
        HomeRowView(group: group, content: content,
                    load: { for row in group.rows { model.load(row.id) } },
                    request: {
                        for row in group.rows { if case .failed = row.state { model.request(row.id) } }
                    },
                    showAll: showAll,
                    open: open,
                    openLocation: { location in
                        // Places come from a section of one source: an index's groups, a feed's.
                        guard let row = group.rows.first else { return }
                        ExplorePlace.page(of: location, in: row, aozoraIndex: aozoraIndex).map(push)
                    },
                    openCollection: { push(ExplorePlace.page(of: $0, aozoraIndex: aozoraIndex)) },
                    openArticle: { push(.article(SubscriptionArticleRoute(articleID: $0.id))) },
                    actions: actions,
                    bookActions: bookActions)
    }

    private var actions: HomeSectionActions? {
        guard isEditable else { return nil }
        return HomeSectionActions(
            setLayout: { layout in
                withAnimation(DSAnimation.standard) {
                    HomePageStore.shared.edit { $0.setLayout(layout, section: group.section.id) }
                }
            },
            hide: { HomePageStore.shared.edit { $0.setEnabled(false, section: group.section.id) } },
            openSettings: openSettings,
            delete: { confirmsDelete = true })
    }

    /// Every card made again, its text in the reader's script, whenever the section draws: a span,
    /// so a main-thread stall during it is named.
    private var content: HomeRowContent? {
        guard case .loaded(let entries) = group.state else { return nil }
        return SourcePerfTrace.span("home.rowContent", "entries=\(entries.count)", thresholdMs: 16) {
            HomeRowContent(entries: entries, store: store, withLists: group.section.layout.style == .chart)
        }
    }

    /// A shelf copy's ••• (5d-3c). The shelf's rows load again at once, so the card leaves
    /// 继续阅读 and 相关 sees the change.
    private var bookActions: HomeBookActions {
        let isContinueReading = group.section.binding == .continueReading
        return HomeBookActions(
            removeFromContinueReading: isContinueReading ? { book in
                store.removeFromContinueReading(bookId: book.id)
                model.reloadLocal()
            } : nil,
            markFinished: { book in
                store.markFinished(bookId: book.id)
                model.reloadLocal()
            })
    }

    /// The section's page (`ExplorePlace.sectionPage`).
    private var showAll: (() -> Void)? {
        ExplorePlace.sectionPage(group, aozoraIndex: aozoraIndex).map { target in { push(target) } }
    }

    /// Every card opens 作品详情 first, as Emby's posters open the item's page (Phase 5 plan,
    /// decision 27); a shelf copy on 继续阅读 or 书架 opens its reader (`ExplorePush.card`).
    private func open(_ card: HomeCardContent, _ cards: [HomeCardContent]) {
        guard let route = card.route else { return }
        push(.card(route, in: group.section.binding))
    }
}

// MARK: - 范围

/// Which sources 范围 offers, and whether a stored one is still there (design §13.3: 全部, or
/// any book source, library connection, Gutenberg or Aozora; no public library in China).
enum ExploreHomeScope {
    @MainActor
    static func isAvailable(_ key: SourceInstanceKey, sources: [BookSource], connections: RemoteLibraryConnectionStore,
                            librariesAvailable: Bool) -> Bool {
        switch key.type {
        case .bookSource:
            // The sources 探索 lists (`DiscoverViewModel.exploreSources`).
            return sources.contains {
                $0.bookSourceUrl == key.id && $0.enabledExplore
                    && !$0.exploreUrl.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            }
        case .opds, .calibre, .webDAV:
            return connections.connection(id: key.id).map { ProviderType($0.kind) } == key.type
        case .gutenberg, .aozora:
            return librariesAvailable
        case .library, .bibliographic, .module:
            return false
        }
    }

    @MainActor
    static func name(of key: SourceInstanceKey, sources: [BookSource], connections: RemoteLibraryConnectionStore) -> String {
        switch key.type {
        case .bookSource: sources.first { $0.bookSourceUrl == key.id }?.bookSourceName ?? key.id
        case .opds, .calibre, .webDAV: connections.connection(id: key.id)?.name ?? key.id
        case .gutenberg: localized("Project Gutenberg")
        case .aozora: localized("青空文库")
        case .library, .bibliographic, .module: key.id
        }
    }
}

/// A library as 范围, 显示在最新 and 搜寻来源 list it.
struct LibraryListing: Identifiable, Hashable {
    let key: SourceInstanceKey
    let name: String
    let systemImage: String

    var id: SourceInstanceKey { key }

    /// The libraries there are now (saved connections; Gutenberg and 青空文库 where offered).
    static func available(connections: [RemoteLibraryConnection], librariesAvailable: Bool) -> [LibraryListing] {
        let names = Dictionary(connections.map { ($0.id, $0.name) }, uniquingKeysWith: { first, _ in first })
        return LibraryKeys.available(connections: connections, librariesAvailable: librariesAvailable).map { key in
            let name = switch key.type {
            case .gutenberg: localized("Project Gutenberg")
            case .aozora: localized("青空文库")
            default: names[key.id] ?? key.id
            }
            return LibraryListing(key: key, name: name, systemImage: SourceKindSymbol.symbol(for: key.type) ?? "books.vertical")
        }
    }
}

/// What 探索's ••• does (Phase 5 plan, decisions 30 and 36), from the menu or iOS 17's chooser.
enum ExploreMoreAction: Hashable {
    case editHome
    case readingLanguages
    case aggregatedSources
    case refresh
    case browser
}

/// 编辑首页 and 完成 crossfading on the button at the home's end, each centred on the capsule
/// as it narrows or widens to the new title. Changed in place, the outgoing title kept to the
/// capsule's leading edge and ran out past its trailing one, reading as one word with the other.
private struct HomeEditButtonTitle: View {
    let isEditing: Bool

    var body: some View {
        // The title shown sizes the capsule; both are drawn over it. The button reads its own label.
        Text(localized(isEditing ? "完成" : "编辑首页"))
            .hidden()
            .overlay {
                ZStack {
                    Text(localized("编辑首页")).opacity(isEditing ? 0 : 1)
                    Text(localized("完成")).opacity(isEditing ? 1 : 0)
                }
                .fixedSize()
                .accessibilityHidden(true)
            }
    }
}

/// 探索's ••• from iOS 18: 编辑首页, the two entries into 聚合设置, 重新整理, and the browser, which
/// is presented rather than shown in place (5d-1) and always offered (maintainer, 2026-10-17).
/// 首页配置 has its own button beside it since 2026-10-22.
private struct ExploreMoreMenu: View {
    let perform: (ExploreMoreAction) -> Void

    var body: some View {
        Menu {
            Button { perform(.editHome) } label: {
                Label(localized("编辑首页"), systemImage: "pencil")
            }
            Section {
                Button { perform(.readingLanguages) } label: {
                    Label(localized("中继资料语言偏好推荐"), systemImage: "globe")
                }
                Button { perform(.aggregatedSources) } label: {
                    Label(localized("参与聚合的来源"), systemImage: "square.stack.3d.up")
                }
            }
            Section {
                Button { perform(.refresh) } label: {
                    Label(localized("重新整理"), systemImage: "arrow.clockwise")
                }
                Button { perform(.browser) } label: {
                    Label(localized("浏览器"), systemImage: "safari")
                }
            }
        } label: {
            Image(systemName: "ellipsis")
                .accessibilityHidden(true)
        }
        .accessibilityLabel(localized("更多"))
        .accessibilityIdentifier("explore.more")
    }
}

#Preview("Explore home") {
    ExploreHome(browser: BrowserState())
        .environmentObject(BookStore())
}

#Preview("编辑首页／完成") {
    @Previewable @State var isEditing = false
    Button { withAnimation(DSAnimation.homeEditMorph) { isEditing.toggle() } } label: {
        HomeEditButtonTitle(isEditing: isEditing)
    }
    .buttonStyle(.bordered)
    .geometryGroup()
}

#Preview("•••，iOS 18 起的选单") {
    NavigationStack {
        Text(localized("探索"))
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    ExploreMoreMenu(perform: { _ in })
                }
            }
    }
}
