import SwiftUI

// MARK: - 書架（紙感版）
//
// The shelf, drawn as the maintainer's reference (2026-11-04): one page of paper with the
// book you were last in at the top — cover, title, author, the chapter you stopped at — then
// the rest of the shelf as a grid. The tab keeps its name: 書架, never 藏書.
//
// What the old grid did and this one still does: open a book, add a book, sort, select and
// delete. 分組 pages are gone with the old layout — the chips across the middle filter the
// shelf (全部 / 本地 / 漫畫 / 視頻 / 聽書 / 養肥) instead of by folder, which is what the
// reference shows and what the shelf is actually used for. Only 養肥 is a shelf the reader
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

    // MARK: Data

    /// The book the reader was in last: what 接着讀 offers, and the one the grid leaves out.
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

    /// Every chip stays on the bar even when its count is 0 — 視頻 / 漫畫 / 聽書 are how the
    /// maintainer looks for those books, so hiding the entry until one exists made them
    /// impossible to find. An empty chip now says so instead of disappearing.
    private var availableFilters: [ShelfFilter] { ShelfFilter.allCases }

    /// 讀者給書架設了頁面背景圖時，頁面下半的書名會直接坐在圖上 —— 那時才需要底下那層
    /// 從透明回到頁面色的柔邊。沒設圖時整頁都是底色，柔邊只會讓頁面發灰。
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
            // 有背景圖時，頁面下半的書名直接坐在山水上，灰字讀不清。這層柔邊把頁面下半
            // 漸回頁面底色，圖仍從上半頁透出來；它鋪在內容**之下**，所以封面和文字照舊
            // 清楚，只是它們背後的圖淡了。沒設圖時它整層隱形。
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
        .confirmationDialog(
            localized("刪除所選書籍"),
            isPresented: $confirmsDelete,
            titleVisibility: .visible
        ) {
            Button(localized("刪除"), role: .destructive) {
                for id in selection { store.delete(bookId: id) }
                selection = []
                isManaging = false
            }
            Button(localized("取消"), role: .cancel) {}
        } message: {
            Text(localized("刪除後，書籍與其閱讀進度都會從這台裝置移除。"))
        }
    }

    // MARK: 標題

    private var masthead: some View {
        HStack(alignment: .center) {
            Text(localized("書架"))
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
                        Label(localized("添加書籍"), systemImage: "plus")
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
                .accessibilityLabel(localized("書架選項"))
            }
        }
        .padding(.top, 6)
    }

    // MARK: 接着讀

    @ViewBuilder
    private var continueReading: some View {
        // 篩到某個分類時，卡片跟著走：在「漫畫」下卻頂著最近讀的 TXT，會讓人以為
        // 那本書屬於這個分類 —— 養肥尤其如此，它現在是讀者自己挑的一架書。
        if let book = currentBook, filter.accepts(book) {
            VStack(alignment: .leading, spacing: 12) {
                HStack(spacing: 6) {
                    Text(localized("接着讀"))
                        .font(.system(size: 12.5, weight: .semibold))
                        .tracking(0.6)
                        .foregroundStyle(ShelfInk.strong(scheme))
                    Spacer(minLength: 0)
                    Text(localized("上次打開"))
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

                            Text(chapterLine(for: book) ?? localized("還沒有開始讀"))
                                .font(.system(size: 12.5))
                                .foregroundStyle(ShelfInk.muted(scheme))
                                .lineLimit(1)
                                .padding(.top, 8)
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                    }

                    // 書簽提示在左、繼續閱讀在右 — the button used to sit under the title
                    // and squeezed the three lines of text into a narrow column.
                    HStack(spacing: 12) {
                        HStack(spacing: 5) {
                            Image(systemName: "bookmark")
                                .font(.system(size: 10))
                            Text(localized("已為你保留上次閱讀位置"))
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
                                Text(localized("繼續閱讀"))
                                    .font(.system(size: 13, weight: .medium))
                                Image(systemName: "arrow.right")
                                    .font(.system(size: 11, weight: .semibold))
                            }
                            .foregroundStyle(ShelfInk.strong(scheme))
                            .padding(.horizontal, 16)
                            .padding(.vertical, 9)
                            // 主題色染的實底，不是又一層玻璃：卡片本身已經是玻璃，裡面
                            // 再套一層玻璃，iOS 26 的兩層 glassEffect 會互相採樣，糊成一團。
                            .background {
                                Capsule().fill(
                                    DSColor.accent.opacity(scheme == .dark ? 0.26 : 0.14)
                                )
                            }
                        }
                        .buttonStyle(.plain)
                    }
                    .padding(.top, 14)
                }
                .padding(16)
                .frame(maxWidth: .infinity, alignment: .leading)
                .paperCard(radius: 22)
                // 長按整張卡都能彈出菜單，不只是封面和文字那幾塊 —— 讀者圈著整張卡說
                // 「這裡刪不掉」，就是因為空白處（右半邊、書名右側）沒有命中區域。
                .contentShape(RoundedRectangle(cornerRadius: 22, style: .continuous))
                // The book being read is the one most often 養肥-ed (a serial you are
                // letting run), and it never appears in the grid below — so the menu
                // has to be reachable here too.
                .contextMenu {
                    Button {
                        if !NowPlayingHub.shared.openIfAudiobook(book, store: store) {
                            readingBookID = book.id
                        }
                    } label: {
                        Label(localized("打開"), systemImage: "book")
                    }
                    Button {
                        store.setFattening(!book.isFattening, for: book.id)
                    } label: {
                        Label(
                            book.isFattening ? localized("移出養肥") : localized("加入養肥"),
                            systemImage: book.isFattening ? "leaf.fill" : "leaf"
                        )
                    }
                    Button(role: .destructive) {
                        store.delete(bookId: book.id)
                    } label: {
                        Label(localized("刪除"), systemImage: "trash")
                    }
                }
            }
        }
    }

    // MARK: 分類

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
                                // 選中態染主題強調色，不畫一塊不透明的灰：玻璃上的不透明
                                // 色塊會把整條 bar 的玻璃打斷，看起來像貼紙。
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
        .interfaceCardSurface(in: Capsule(), fill: PaperPalette.card(scheme))
        .overlay(Capsule().strokeBorder(PaperPalette.hairline(scheme).opacity(0.55), lineWidth: 0.6))
        .padding(.top, 18)
    }

    // MARK: 其餘書籍

    /// 「其餘書籍」 only describes the whole shelf; once a chip is chosen the list below is
    /// that shelf, so it takes the chip's own name — 養肥 is the reader's own shelf now.
    private var sectionTitle: String {
        filter == .all ? localized("其餘書籍") : filter.title
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
                    Text("\(selection.count) \(localized("已選"))")
                        .font(.system(size: 12))
                        .foregroundStyle(ShelfInk.muted(scheme))
                    Button {
                        confirmsDelete = true
                    } label: {
                        Text(localized("刪除"))
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
                    // 養肥 is a shelf the reader fills by hand now, so 空 is the normal
                    // state on a fresh install — say how to add one instead of "no books".
                    VStack(alignment: .leading, spacing: 8) {
                        Text(localized("養肥還是空的"))
                            .font(.system(size: 14, weight: .medium))
                            .foregroundStyle(ShelfInk.strong(scheme))
                        Text(localized("長按書架上的書，選「加入養肥」。"))
                            .font(.system(size: 12.5))
                            .foregroundStyle(ShelfInk.muted(scheme))
                        Button {
                            withAnimation(.snappy(duration: 0.18)) { filter = .all }
                        } label: {
                            HStack(spacing: 5) {
                                Text(localized("去挑書"))
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
                    Text(localized("這個分類還沒有書"))
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

                    // 次要行用二級文字而非三級：書名下面這一行在頁面背景圖上也要讀得清。
                    Text(subtitle(for: book))
                        .font(.system(size: 11.5))
                        .foregroundStyle(ShelfInk.soft(scheme))
                        .lineLimit(1)
                }
            }
            // 封面與書名之間的空隙原本不屬於任何可命中區域，長按會落空；鋪平之後
            // 整格都是長按範圍，刪除、加入養肥不必對準封面。
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
                Label(localized("打開"), systemImage: "book")
            }
            Button {
                store.setFattening(!book.isFattening, for: book.id)
            } label: {
                Label(
                    book.isFattening ? localized("移出養肥") : localized("加入養肥"),
                    systemImage: book.isFattening ? "leaf.fill" : "leaf"
                )
            }
            Button(role: .destructive) {
                store.delete(bookId: book.id)
            } label: {
                Label(localized("刪除"), systemImage: "trash")
            }
        }
    }

    private var emptyShelf: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(localized("書架還是空的"))
                .font(PaperFont.serif(20))
                .foregroundStyle(ShelfInk.strong(scheme))
            Text(localized("匯入一本書，這裡就會亮起來。"))
                .font(.system(size: 13))
                .foregroundStyle(ShelfInk.soft(scheme))
            Button {
                showsAddBook = true
            } label: {
                HStack(spacing: 6) {
                    Image(systemName: "plus")
                        .font(.system(size: 11, weight: .semibold))
                    Text(localized("添加書籍"))
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
            return String(format: localized("讀至 %d%%"), Int(book.currentPosition * 100))
        }
        return nil
    }

    /// 第 3 章 — what the grid's second line leads with.
    private func chapterNumber(_ index: Int) -> String {
        String(format: localized("第 %d 章"), index)
    }

    /// 第 12 章 · 本地 — where it is, and how far in.
    private func subtitle(for book: ReadingBook) -> String {
        let place = book.isOnline ? localized("雲端") : localized("本地")
        guard let chapter = chapterLine(for: book) else {
            return "\(localized("未讀")) · \(place)"
        }
        return "\(chapter) · \(place)"
    }
}

// MARK: - 分類與排序

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
        case .manga: return localized("漫畫")
        // 視頻一直被 `isMediaOnly` 擋在「本地」之外，卻沒有自己的篩選 ——
        // 視頻書只出現在「全部」裡，等於沒法找。漫畫、聽書都有，它也得有。
        case .video: return localized("視頻")
        case .audio: return localized("聽書")
        case .fattening: return localized("養肥")
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
        // 養肥 — a shelf the reader keeps themselves (長按 → 加入養肥), not "everything
        // imported but never opened": that swept in every new book and left no way to
        // leave one out. Nothing lands here unless the reader puts it here.
        case .fattening: return book.isFattening
        }
    }

    /// 漫畫 / 聽書 hang off their own chips; 本地 means "text books on this device".
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
        case .recent: return localized("最近閱讀")
        case .added: return localized("最近添加")
        case .title: return localized("書名")
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

// MARK: - 玻璃按鈕

private extension View {
    /// The app's one glass entry point, not a private copy of it.
    ///
    /// These used to paint `.ultraThinMaterial` themselves, which meant 毛玻璃、透明度
    /// and 光暈 in 外觀主題 › 界面效果 never reached them, and iOS 26's `glassEffect` —
    /// the material the system's own toolbars are made of — was never used on the page
    /// that has the most chrome on it.
    func glassCapsule(_ scheme: ColorScheme) -> some View {
        floatingSurface(in: Capsule())
    }

    func glassCircle(_ scheme: ColorScheme) -> some View {
        floatingSurface(in: Circle())
    }
}
