import SwiftUI

// MARK: - 书架（纸感版）
//
// The shelf, drawn as the maintainer's reference (2026-11-04): one page of paper with the
// book you were last in at the top — cover, title, author, the chapter you stopped at — then
// the rest of the shelf as a grid. The tab keeps its name: 书架, never 藏书.
//
// What the old grid did and this one still does: open a book, add a book, sort, select and
// delete. 分组 pages are gone with the old layout — the chips across the middle filter the
// shelf (全部 / 本地 / 漫画 / 视频 / 听书 / 养肥) instead of by folder, which is what the
// reference shows and what the shelf is actually used for. Only 养肥 is a shelf the reader
// fills by hand; the rest read from the book itself.

struct ShelfPaperView: View {
    @EnvironmentObject private var store: BookStore
    @Environment(\.colorScheme) private var scheme
    @Bindable private var gs = GlobalSettings.shared
    @ObservedObject private var subscription = SubscriptionStore.shared

    @State private var filter: ShelfFilter = .all
    @State private var sort: ShelfSort = .recent
    @State private var isManaging = false
    @State private var selection: Set<UUID> = []
    @State private var readingBookID: UUID?
    @State private var showsAddBook = false
    @State private var confirmsDelete = false
    /// 长按「搜索网络封面」时要找封面的那本书。用整本书而不只是 id：封面搜索按
    /// 书名 + 作者查，换书的同一帧里 state 还没落盘时也能拿到正确的名字。
    @State private var coverSearchBook: ReadingBook?
    /// 选完封面后正在下载 —— 期间再点一次不应叠第二个下载。
    @State private var isApplyingCover = false

    // MARK: Data

    /// The book the reader was in last: what 接着读 offers, and the one the grid leaves out.
    private var currentBook: ReadingBook? {
        store.books
            .filter { $0.lastOpenedDate != nil }
            .max { ($0.lastOpenedDate ?? .distantPast) < ($1.lastOpenedDate ?? .distantPast) }
    }

    private var restBooks: [ReadingBook] {
        store.books
            .filter { $0.id != currentBook?.id }
            .filter(filter.accepts)
            .sorted(by: sort.areInIncreasingOrder)
    }

    /// Every chip stays on the bar even when its count is 0 — 视频 / 漫画 / 听书 are how the
    /// maintainer looks for those books, so hiding the entry until one exists made them
    /// impossible to find. An empty chip now says so instead of disappearing.
    private var availableFilters: [ShelfFilter] { ShelfFilter.allCases }

    /// 读者给书架设了页面背景图时，页面下半的书名会直接坐在图上 —— 那时才需要底下那层
    /// 从透明回到页面色的柔边。没设图时整页都是底色，柔边只会让页面发灰。
    private var showsArtwork: Bool {
        guard subscription.hasAccess(.readerThemePacks) else { return false }
        return gs.resolvedPageBackgroundSlice(for: .bookshelf, colorScheme: scheme) != nil
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                masthead
                    .padding(.bottom, 22)

                if store.books.isEmpty {
                    emptyShelf
                } else {
                    continueReading
                    chips
                    restOfShelf
                }
            }
            .padding(.horizontal, 20)
            .padding(.bottom, 32)
        }
        .scrollIndicators(.hidden)
        .background {
            // 有背景图时，页面下半的书名直接坐在山水上，灰字读不清。这层柔边把页面下半
            // 渐回页面底色，图仍从上半页透出来；它铺在内容**之下**，所以封面和文字照旧
            // 清楚，只是它们背后的图淡了。没设图时它整层隐形。
            ZStack(alignment: .bottom) {
                PaperBackground(scope: .bookshelf)

                LinearGradient(
                    stops: [
                        .init(color: PaperPalette.page(scheme).opacity(0), location: 0),
                        .init(color: PaperPalette.page(scheme).opacity(0.55), location: 0.45),
                        .init(color: PaperPalette.page(scheme).opacity(0.92), location: 1),
                    ],
                    startPoint: .top,
                    endPoint: .bottom
                )
                .frame(height: 420)
                .opacity(showsArtwork ? 1 : 0)
                .allowsHitTesting(false)
                .ignoresSafeArea(edges: .bottom)
            }
        }
        .toolbar(.hidden, for: .navigationBar)
        .fullScreenCover(isPresented: Binding(
            get: { readingBookID != nil },
            set: { if !$0 { readingBookID = nil } }
        )) {
            if let id = readingBookID {
                BookReaderView(bookId: id)
                    .environmentObject(store)
            }
        }
        .sheet(isPresented: $showsAddBook) {
            AdaptiveSheetContainer(maxWidth: DSLayout.readableListWidth) {
                AddBookView()
                    .environmentObject(store)
            }
        }
        // 书架长按 → 搜索网络封面。复用 书籍资讯 → 封面 里那张页，只是把入口从
        // 三层深的面板搬到长按菜单上：想换封面的时候人正在书架上，不该先点进书。
        // onDismiss 一定把 item 清掉：页内选中后是它自己 dismiss 的，binding 若还留着
        // 那本书，下次长按同一本不会重新弹出。
        .sheet(item: $coverSearchBook, onDismiss: { coverSearchBook = nil }) { book in
            NavigationStack {
                OnlineCoverSearchView(
                    title: book.title,
                    author: book.author,
                    onSelect: { candidate in
                        applyCover(candidate, to: book)
                    },
                    onImportImage: { data in
                        applyImportedCover(data, to: book)
                    }
                )
                .toolbar {
                    ToolbarItem(placement: .topBarLeading) {
                        Button(localized("取消")) { coverSearchBook = nil }
                    }
                }
            }
            // 全 App 的浮层都是玻璃，这一张也一样：后面的书架透上来，
            // 封面格子自己带 surface，不会糊成一片。统一走「全局玻璃」总闸，
            // 关掉时退成不透明纯色，供 iOS 17 一键兜底（第 13 条）。
            .presentationBackground { GlobalGlassBackdrop() }
        }
        .confirmationDialog(
            localized("删除所选书籍"),
            isPresented: $confirmsDelete,
            titleVisibility: .visible
        ) {
            Button(localized("删除"), role: .destructive) {
                for id in selection { store.delete(bookId: id) }
                selection = []
                isManaging = false
            }
            Button(localized("取消"), role: .cancel) {}
        } message: {
            Text(localized("删除后，书籍与其阅读进度都会从这台装置移除。"))
        }
    }

    // MARK: 标题

    private var masthead: some View {
        HStack(alignment: .center) {
            Text(localized("书架"))
                .font(PaperFont.serif(32))
                .foregroundStyle(ShelfInk.strong(scheme))
                .accessibilityAddTraits(.isHeader)

            Spacer(minLength: 12)

            if isManaging {
                Button {
                    withAnimation(.snappy(duration: 0.2)) {
                        isManaging = false
                        selection = []
                    }
                } label: {
                    Text(localized("完成"))
                        .font(.system(size: 14, weight: .medium))
                        .foregroundStyle(ShelfInk.strong(scheme))
                        .padding(.horizontal, 16)
                        .padding(.vertical, 9)
                        .glassCapsule(scheme)
                }
                .buttonStyle(.plain)
            } else {
                Menu {
                    Button {
                        showsAddBook = true
                    } label: {
                        Label(localized("添加书籍"), systemImage: "plus")
                    }
                    Divider()
                    Picker(localized("排序"), selection: $sort) {
                        ForEach(ShelfSort.allCases) { option in
                            Text(option.title).tag(option)
                        }
                    }
                    Divider()
                    Button {
                        withAnimation(.snappy(duration: 0.2)) { isManaging = true }
                    } label: {
                        Label(localized("管理"), systemImage: "checkmark.circle")
                    }
                } label: {
                    Image(systemName: "slider.horizontal.3")
                        .font(.system(size: 15, weight: .medium))
                        .foregroundStyle(ShelfInk.strong(scheme))
                        .frame(width: 38, height: 38)
                        .glassCircle(scheme)
                }
                .accessibilityLabel(localized("书架选项"))
            }
        }
        .padding(.top, 6)
    }

    // MARK: 接着读

    @ViewBuilder
    private var continueReading: some View {
        // 筛到某个分类时，卡片跟著走：在「漫画」下却顶著最近读的 TXT，会让人以为
        // 那本书属于这个分类 —— 养肥尤其如此，它现在是读者自己挑的一架书。
        if let book = currentBook, filter.accepts(book) {
            VStack(alignment: .leading, spacing: 12) {
                HStack(spacing: 6) {
                    Text(localized("接着读"))
                        .font(.system(size: 12.5, weight: .semibold))
                        .tracking(0.6)
                        .foregroundStyle(ShelfInk.strong(scheme))
                    Spacer(minLength: 0)
                    Text(localized("上次打开"))
                        .font(.system(size: 11.5))
                        .foregroundStyle(ShelfInk.muted(scheme))
                    Image(systemName: "chevron.right")
                        .font(.system(size: 9, weight: .semibold))
                        .foregroundStyle(ShelfInk.muted(scheme))
                }
                .padding(.horizontal, 4)

                VStack(alignment: .leading, spacing: 0) {
                    HStack(alignment: .top, spacing: 16) {
                        shelfCover(book, width: 74, height: 104)

                        VStack(alignment: .leading, spacing: 0) {
                            Text(book.title)
                                .font(PaperFont.serif(20))
                                .foregroundStyle(ShelfInk.strong(scheme))
                                .lineLimit(2)
                                .minimumScaleFactor(0.85)

                            Text(book.author)
                                .font(.system(size: 12.5))
                                .foregroundStyle(ShelfInk.soft(scheme))
                                .lineLimit(1)
                                .padding(.top, 5)

                            Text(chapterLine(for: book) ?? localized("还没有开始读"))
                                .font(.system(size: 12.5))
                                .foregroundStyle(ShelfInk.muted(scheme))
                                .lineLimit(1)
                                .padding(.top, 8)
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                    }

                    // 书签提示在左、继续阅读在右 — the button used to sit under the title
                    // and squeezed the three lines of text into a narrow column.
                    HStack(spacing: 12) {
                        HStack(spacing: 5) {
                            Image(systemName: "bookmark")
                                .font(.system(size: 10))
                            Text(localized("已为你保留上次阅读位置"))
                                .font(.system(size: 11.5))
                                .lineLimit(1)
                        }
                        .foregroundStyle(ShelfInk.muted(scheme))

                        Spacer(minLength: 8)

                        Button {
                            // An audiobook's player grows out of the now-playing bar.
                            if !NowPlayingHub.shared.openIfAudiobook(book, store: store) {
                                readingBookID = book.id
                            }
                        } label: {
                            HStack(spacing: 6) {
                                Text(localized("继续阅读"))
                                    .font(.system(size: 13, weight: .medium))
                                Image(systemName: "arrow.right")
                                    .font(.system(size: 11, weight: .semibold))
                            }
                            .foregroundStyle(ShelfInk.strong(scheme))
                            .padding(.horizontal, 16)
                            .padding(.vertical, 9)
                            // 与首页「继续阅读」按钮同一套玻璃语言：卡片本身已经是玻璃，
                            // 里面不能再叠 .ultraThinMaterial（两层 glassEffect 会互采、
                            // 糊成一团），所以用「单层中性半透明填充」——读起来是透明玻璃，
                            // 而不是主题色块。
                            .background {
                                Capsule().fill(
                                    Color.primary.opacity(scheme == .dark ? 0.12 : 0.05)
                                )
                            }
                            .overlay(Capsule().strokeBorder(PaperPalette.hairline(scheme), lineWidth: 0.5))
                        }
                        .buttonStyle(.plain)
                    }
                    .padding(.top, 14)
                }
                .padding(16)
                .frame(maxWidth: .infinity, alignment: .leading)
                .paperCard(radius: 22)
                // 长按整张卡都能弹出菜单，不只是封面和文字那几块 —— 读者圈著整张卡说
                // 「这里删不掉」，就是因为空白处（右半边、书名右侧）没有命中区域。
                .contentShape(RoundedRectangle(cornerRadius: 22, style: .continuous))
                // The book being read is the one most often 养肥-ed (a serial you are
                // letting run), and it never appears in the grid below — so the menu
                // has to be reachable here too.
                .contextMenu {
                    Button {
                        if !NowPlayingHub.shared.openIfAudiobook(book, store: store) {
                            readingBookID = book.id
                        }
                    } label: {
                        Label(localized("打开"), systemImage: "book")
                    }
                    Button {
                        requestCoverSearch(for: book)
                    } label: {
                        Label(localized("搜索网络封面"), systemImage: "photo.on.rectangle.angled")
                    }
                    Button {
                        store.setFattening(!book.isFattening, for: book.id)
                    } label: {
                        Label(
                            book.isFattening ? localized("移出养肥") : localized("加入养肥"),
                            systemImage: book.isFattening ? "leaf.fill" : "leaf"
                        )
                    }
                    Button(role: .destructive) {
                        store.delete(bookId: book.id)
                    } label: {
                        Label(localized("删除"), systemImage: "trash")
                    }
                }
            }
        }
    }

    // MARK: 分类

    private var chips: some View {
        ScrollView(.horizontal) {
            HStack(spacing: 4) {
                ForEach(availableFilters) { option in
                    let isOn = option == filter
                    Button {
                        withAnimation(.snappy(duration: 0.18)) { filter = option }
                    } label: {
                        HStack(spacing: 5) {
                            Text(option.title)
                                .font(.system(size: 13, weight: isOn ? .semibold : .regular))
                            Text("\(count(for: option))")
                                .font(.system(size: 11, weight: .medium))
                                .foregroundStyle(
                                    isOn ? ShelfInk.soft(scheme)
                                         : ShelfInk.muted(scheme)
                                )
                        }
                        .foregroundStyle(
                            isOn ? ShelfInk.strong(scheme)
                                 : ShelfInk.soft(scheme)
                        )
                        .padding(.horizontal, 12)
                        .padding(.vertical, 9)
                        .background {
                            if isOn {
                                // 选中态染主题强调色，不画一块不透明的灰：玻璃上的不透明
                                // 色块会把整条 bar 的玻璃打断，看起来像贴纸。
                                Capsule().fill(
                                    DSColor.accent.opacity(scheme == .dark ? 0.28 : 0.16)
                                )
                            }
                        }
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(4)
        }
        .scrollIndicators(.hidden)
        // 收编到全局玻璃统一入口（参考待改清单第 13 条）：与设置行/卡片同一套玻璃，
        // 由「全局玻璃」总闸控制；关掉后连同整条分类栏一起回退为不透明底色，
        // 不再绕过开关写死 .ultraThinMaterial（iOS 17 兜底）。横向 ScrollView 保留。
        .clearGlassSurface(in: Capsule())
        .overlay(Capsule().strokeBorder(PaperPalette.hairline(scheme).opacity(0.55), lineWidth: 0.6))
        .padding(.top, 18)
    }

    // MARK: 其余书籍

    /// 「其余书籍」 only describes the whole shelf; once a chip is chosen the list below is
    /// that shelf, so it takes the chip's own name — 养肥 is the reader's own shelf now.
    private var sectionTitle: String {
        filter == .all ? localized("其余书籍") : filter.title
    }

    private var restOfShelf: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 8) {
                Text(sectionTitle)
                    .font(.system(size: 12.5, weight: .semibold))
                    .tracking(0.6)
                    .foregroundStyle(ShelfInk.strong(scheme))
                Text("· \(restBooks.count)")
                    .font(.system(size: 12))
                    .foregroundStyle(ShelfInk.muted(scheme))

                Spacer(minLength: 8)

                if isManaging {
                    Text("\(selection.count) \(localized("已选"))")
                        .font(.system(size: 12))
                        .foregroundStyle(ShelfInk.muted(scheme))
                    Button {
                        confirmsDelete = true
                    } label: {
                        Text(localized("删除"))
                            .font(.system(size: 12.5, weight: .medium))
                            .foregroundStyle(.red)
                            .padding(.horizontal, 12)
                            .padding(.vertical, 6)
                            .glassCapsule(scheme)
                    }
                    .buttonStyle(.plain)
                    .disabled(selection.isEmpty)
                } else {
                    Menu {
                        Picker(localized("排序"), selection: $sort) {
                            ForEach(ShelfSort.allCases) { option in
                                Text(option.title).tag(option)
                            }
                        }
                    } label: {
                        HStack(spacing: 3) {
                            Text(sort.title)
                            Image(systemName: "chevron.down")
                                .font(.system(size: 8, weight: .semibold))
                        }
                        .font(.system(size: 12))
                        .foregroundStyle(ShelfInk.muted(scheme))
                    }
                }
            }
            .padding(.horizontal, 4)

            if restBooks.isEmpty {
                if filter == .fattening {
                    // 养肥 is a shelf the reader fills by hand now, so 空 is the normal
                    // state on a fresh install — say how to add one instead of "no books".
                    VStack(alignment: .leading, spacing: 8) {
                        Text(localized("养肥还是空的"))
                            .font(.system(size: 14, weight: .medium))
                            .foregroundStyle(ShelfInk.strong(scheme))
                        Text(localized("长按书架上的书，选「加入养肥」。"))
                            .font(.system(size: 12.5))
                            .foregroundStyle(ShelfInk.muted(scheme))
                        Button {
                            withAnimation(.snappy(duration: 0.18)) { filter = .all }
                        } label: {
                            HStack(spacing: 5) {
                                Text(localized("去挑书"))
                                    .font(.system(size: 12.5, weight: .medium))
                                Image(systemName: "arrow.right")
                                    .font(.system(size: 10, weight: .semibold))
                            }
                            .foregroundStyle(ShelfInk.strong(scheme))
                            .padding(.horizontal, 14)
                            .padding(.vertical, 8)
                            .glassCapsule(scheme)
                        }
                        .buttonStyle(.plain)
                        .padding(.top, 2)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 4)
                    .padding(.vertical, 18)
                } else {
                    Text(localized("这个分类还没有书"))
                        .font(.system(size: 12.5))
                        .foregroundStyle(ShelfInk.muted(scheme))
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.horizontal, 4)
                        .padding(.vertical, 18)
                }
            } else {
                LazyVGrid(
                    columns: Array(repeating: GridItem(.flexible(), spacing: 14, alignment: .top), count: 3),
                    alignment: .leading,
                    spacing: 22
                ) {
                    ForEach(restBooks) { book in
                        cell(for: book)
                    }
                }
            }
        }
        .padding(.top, 26)
    }

    private func cell(for book: ReadingBook) -> some View {
        Button {
            if isManaging {
                if selection.contains(book.id) { selection.remove(book.id) }
                else { selection.insert(book.id) }
            } else {
                // An audiobook's player grows out of the now-playing bar.
                if !NowPlayingHub.shared.openIfAudiobook(book, store: store) {
                    readingBookID = book.id
                }
            }
        } label: {
            VStack(alignment: .leading, spacing: 8) {
                ZStack(alignment: .topTrailing) {
                    shelfCover(book, width: nil, height: 150)
                    if isManaging {
                        Image(systemName: selection.contains(book.id) ? "checkmark.circle.fill" : "circle")
                            .font(.system(size: 19))
                            .foregroundStyle(
                                selection.contains(book.id)
                                    ? ShelfInk.strong(scheme)
                                    : Color.white.opacity(0.9)
                            )
                            .shadow(color: .black.opacity(0.25), radius: 3)
                            .padding(6)
                    }
                }

                VStack(alignment: .leading, spacing: 3) {
                    Text(book.title)
                        .font(.system(size: 13, weight: .medium))
                        .foregroundStyle(ShelfInk.strong(scheme))
                        .lineLimit(1)

                    // 次要行用二级文字而非三级：书名下面这一行在页面背景图上也要读得清。
                    Text(subtitle(for: book))
                        .font(.system(size: 11.5))
                        .foregroundStyle(ShelfInk.soft(scheme))
                        .lineLimit(1)
                }
            }
            // 封面与书名之间的空隙原本不属于任何可命中区域，长按会落空；铺平之后
            // 整格都是长按范围，删除、加入养肥不必对准封面。
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .contextMenu {
            Button {
                // An audiobook's player grows out of the now-playing bar.
                if !NowPlayingHub.shared.openIfAudiobook(book, store: store) {
                    readingBookID = book.id
                }
            } label: {
                Label(localized("打开"), systemImage: "book")
            }
            Button {
                requestCoverSearch(for: book)
            } label: {
                Label(localized("搜索网络封面"), systemImage: "photo.on.rectangle.angled")
            }
            Button {
                store.setFattening(!book.isFattening, for: book.id)
            } label: {
                Label(
                    book.isFattening ? localized("移出养肥") : localized("加入养肥"),
                    systemImage: book.isFattening ? "leaf.fill" : "leaf"
                )
            }
            Button(role: .destructive) {
                store.delete(bookId: book.id)
            } label: {
                Label(localized("删除"), systemImage: "trash")
            }
        }
    }

    private var emptyShelf: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(localized("书架还是空的"))
                .font(PaperFont.serif(20))
                .foregroundStyle(ShelfInk.strong(scheme))
            Text(localized("汇入一本书，这里就会亮起来。"))
                .font(.system(size: 13))
                .foregroundStyle(ShelfInk.soft(scheme))
            Button {
                showsAddBook = true
            } label: {
                HStack(spacing: 6) {
                    Image(systemName: "plus")
                        .font(.system(size: 11, weight: .semibold))
                    Text(localized("添加书籍"))
                        .font(.system(size: 13, weight: .medium))
                }
                .foregroundStyle(ShelfInk.strong(scheme))
                .padding(.horizontal, 16)
                .padding(.vertical, 9)
                .glassCapsule(scheme)
            }
            .buttonStyle(.plain)
            .padding(.top, 6)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(20)
        .paperCard(radius: 22)
    }

    // MARK: 零件

    /// A cover on the page: no tilt here, the shelf is a shelf — the spine's shade and a soft
    /// shadow are enough to keep it from reading as a flat rectangle.
    private func shelfCover(_ book: ReadingBook, width: CGFloat?, height: CGFloat) -> some View {
        BookCoverImage(readingBook: book)
            .frame(width: width, height: height)
            .frame(maxWidth: width == nil ? .infinity : nil)
            .clipShape(RoundedRectangle(cornerRadius: 5, style: .continuous))
            .overlay(alignment: .leading) {
                LinearGradient(
                    colors: [Color.black.opacity(0.22), .clear],
                    startPoint: .leading,
                    endPoint: .trailing
                )
                .frame(width: (width ?? 100) * 0.1)
                .clipShape(RoundedRectangle(cornerRadius: 5, style: .continuous))
                .allowsHitTesting(false)
            }
            .shadow(color: .black.opacity(0.16), radius: 8, x: 3, y: 6)
            .accessibilityHidden(true)
    }

    private func count(for option: ShelfFilter) -> Int {
        store.books.filter(option.accepts).count
    }

    /// 第三章 · 未寄出的信 — the chapter the book is open at, when the book knows its chapters.
    private func chapterLine(for book: ReadingBook) -> String? {
        if let chapters = book.onlineChapters, !chapters.isEmpty {
            let index = min(chapters.count - 1, max(0, Int(book.currentPosition * Double(chapters.count))))
            let title = chapters[index].title
            return title.isEmpty ? chapterNumber(index + 1) : "\(chapterNumber(index + 1)) · \(title)"
        }
        if let total = book.totalChapterNum, total > 0, book.currentPosition > 0.001 {
            let index = min(total, max(1, Int(book.currentPosition * Double(total)) + 1))
            return chapterNumber(index)
        }
        if book.currentPosition > 0.001 {
            return String(format: localized("读至 %d%%"), Int(book.currentPosition * 100))
        }
        return nil
    }

    /// 第 3 章 — what the grid's second line leads with.
    private func chapterNumber(_ index: Int) -> String {
        String(format: localized("第 %d 章"), index)
    }

    /// 第 12 章 · 本地 — where it is, and how far in.
    private func subtitle(for book: ReadingBook) -> String {
        let place = book.isOnline ? localized("云端") : localized("本地")
        guard let chapter = chapterLine(for: book) else {
            return "\(localized("未读")) · \(place)"
        }
        return "\(chapter) · \(place)"
    }

    // MARK: 搜索网络封面

    /// 从长按菜单请求封面搜索。
    ///
    /// 菜单收起和 sheet 弹出若撞在同一帧，iOS 会把这个 presentation 丢掉 —— 表现就是
    /// 「长按点了没反应」。让出两帧再设 item，菜单先收干净。
    private func requestCoverSearch(for book: ReadingBook) {
        Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(220))
            coverSearchBook = book
        }
    }

    /// 下载长按选中封面并设成这本书的封面。
    ///
    /// 走的是 书籍资讯 里同一个 `applyCustomCover`，所以去重、备份原封面、
    /// 「重设封面」能还原，全都和面板里改的一致。失败不静默：书架上的封面没变，
    /// 不说一声就会以为点空了。
    private func applyCover(_ candidate: CoverCandidate, to book: ReadingBook) {
        guard !isApplyingCover else {
            BookSourceFormLoginView.presentToastAlert(message: localized("正在应用上一张封面…"))
            return
        }
        isApplyingCover = true
        Task { @MainActor in
            let applied = await store.applyCustomCover(
                bookId: book.id,
                coverUrl: candidate.coverUrl,
                sourceId: candidate.sourceId
            )
            isApplyingCover = false
            // 选中后面板会自己关掉；关闭动画还在跑时 present 会落在一个正在消失的
            // 控制器上，系统直接丢掉这个 alert。等一拍，等它落定。
            try? await Task.sleep(for: .milliseconds(350))
            BookSourceFormLoginView.presentToastAlert(
                message: applied
                    ? localized("封面已更新")
                    : localized("无法下载这张封面，请换一张或检查网络。")
            )
        }
    }

    /// 「导入封面」：把相簿/档案里选的图片直接设成封面。走 BookStore 里与
    /// 书籍资讯相同的 `applyCustomCover(bookId:imageData:)`，所以降采样、备份
    /// 原封面、「重设封面」可还原都一致。
    private func applyImportedCover(_ data: Data, to book: ReadingBook) {
        let applied = store.applyCustomCover(bookId: book.id, imageData: data)
        BookSourceFormLoginView.presentToastAlert(
            message: applied
                ? localized("封面已更新")
                : localized("无法读取图片。")
        )
    }
}

// MARK: - 分类与排序

enum ShelfFilter: String, CaseIterable, Identifiable {
    case all
    case local
    case manga
    case video
    case audio
    case fattening

    var id: String { rawValue }

    var title: String {
        switch self {
        case .all: return localized("全部")
        case .local: return localized("本地")
        case .manga: return localized("漫画")
        // 视频一直被 `isMediaOnly` 挡在「本地」之外，却没有自己的筛选 ——
        // 视频书只出现在「全部」里，等于没法找。漫画、听书都有，它也得有。
        case .video: return localized("视频")
        case .audio: return localized("听书")
        case .fattening: return localized("养肥")
        }
    }

    func accepts(_ book: ReadingBook) -> Bool {
        let kind = book.resolvedPipelineKind
        switch self {
        case .all: return true
        case .manga: return kind == .manga
        case .video: return kind == .video
        case .audio: return kind == .audio
        case .local: return !book.isOnline && !Self.isMediaOnly(kind)
        // 养肥 — a shelf the reader keeps themselves (长按 → 加入养肥), not "everything
        // imported but never opened": that swept in every new book and left no way to
        // leave one out. Nothing lands here unless the reader puts it here.
        case .fattening: return book.isFattening
        }
    }

    /// 漫画 / 听书 hang off their own chips; 本地 means "text books on this device".
    private static func isMediaOnly(_ kind: BookPipelineKind) -> Bool {
        kind == .video || kind == .manga || kind == .audio
    }
}

enum ShelfSort: String, CaseIterable, Identifiable {
    case recent
    case added
    case title

    var id: String { rawValue }

    var title: String {
        switch self {
        case .recent: return localized("最近阅读")
        case .added: return localized("最近添加")
        case .title: return localized("书名")
        }
    }

    func areInIncreasingOrder(_ lhs: ReadingBook, _ rhs: ReadingBook) -> Bool {
        switch self {
        case .recent:
            return (lhs.lastOpenedDate ?? lhs.addedDate) > (rhs.lastOpenedDate ?? rhs.addedDate)
        case .added:
            return lhs.addedDate > rhs.addedDate
        case .title:
            return lhs.title.localizedStandardCompare(rhs.title) == .orderedAscending
        }
    }
}

// MARK: - 黑白墨色

/// Headings, body and captions differ by weight and level, not by hue — that part of the
/// maintainer's 2026-11-04 reference stays. The levels now come from the appearance theme's
/// own label colours (2026-11-06: the shelf has to follow the theme like every other page),
/// instead of fixed greys that ignored it.
enum ShelfInk {
    static func strong(_ scheme: ColorScheme) -> Color {
        Color(uiColor: DSUIColor.textPrimary)
    }

    static func soft(_ scheme: ColorScheme) -> Color {
        Color(uiColor: DSUIColor.textSecondary)
    }

    static func muted(_ scheme: ColorScheme) -> Color {
        Color(uiColor: DSUIColor.textTertiary)
    }
}

// MARK: - 玻璃按钮

private extension View {
    /// The app's one glass entry point, not a private copy of it.
    ///
    /// These used to paint `.ultraThinMaterial` themselves, which meant 毛玻璃、透明度
    /// and 光晕 in 外观主题 › 界面效果 never reached them, and iOS 26's `glassEffect` —
    /// the material the system's own toolbars are made of — was never used on the page
    /// that has the most chrome on it.
    func glassCapsule(_ scheme: ColorScheme) -> some View {
        floatingSurface(in: Capsule())
    }

    func glassCircle(_ scheme: ColorScheme) -> some View {
        floatingSurface(in: Circle())
    }
}
