import SwiftUI

// MARK: - 書架（紙感版）
//
// The shelf, drawn as the maintainer's reference (2026-11-04): one page of paper with the
// book you were last in at the top — cover, title, author, the chapter you stopped at — then
// the rest of the shelf as a grid. The tab keeps its name: 書架, never 藏書.
//
// What the old grid did and this one still does: open a book, add a book, sort, select and
// delete. 分組 pages are gone with the old layout — the chips across the middle filter by
// where a book lives (本地 / 雲端 / 視頻 / 漫畫) instead of by folder, which is what the
// reference shows and what the shelf is actually used for.

struct ShelfPaperView: View {
    @EnvironmentObject private var store: BookStore
    @Environment(\.colorScheme) private var scheme

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
        .background(PaperBackground())
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
        if let book = currentBook {
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
                            readingBookID = book.id
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
                            .glassCapsule(scheme)
                        }
                        .buttonStyle(.plain)
                    }
                    .padding(.top, 14)
                }
                .padding(16)
                .frame(maxWidth: .infinity, alignment: .leading)
                .paperCard(radius: 22)
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
                        .padding(.horizontal, 14)
                        .padding(.vertical, 9)
                        .background {
                            if isOn {
                                Capsule().fill(PaperPalette.iconTile(scheme))
                            }
                        }
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(4)
        }
        .scrollIndicators(.hidden)
        .background(Capsule().fill(PaperPalette.card(scheme)))
        .overlay(Capsule().strokeBorder(PaperPalette.hairline(scheme), lineWidth: 0.8))
        .padding(.top, 18)
    }

    // MARK: 其餘書籍

    private var restOfShelf: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 8) {
                Text(localized("其餘書籍"))
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
                Text(localized("這個分類還沒有書"))
                    .font(.system(size: 12.5))
                    .foregroundStyle(ShelfInk.muted(scheme))
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 4)
                    .padding(.vertical, 18)
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
                readingBookID = book.id
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

                    Text(subtitle(for: book))
                        .font(.system(size: 11.5))
                        .foregroundStyle(ShelfInk.muted(scheme))
                        .lineLimit(1)
                }
            }
        }
        .buttonStyle(.plain)
        .contextMenu {
            Button {
                readingBookID = book.id
            } label: {
                Label(localized("打開"), systemImage: "book")
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
    case audio
    case fattening

    var id: String { rawValue }

    var title: String {
        switch self {
        case .all: return localized("全部")
        case .local: return localized("本地")
        case .manga: return localized("漫畫")
        case .audio: return localized("聽書")
        case .fattening: return localized("養肥")
        }
    }

    func accepts(_ book: ReadingBook) -> Bool {
        let kind = book.resolvedPipelineKind
        switch self {
        case .all: return true
        case .manga: return kind == .manga
        case .audio: return kind == .audio
        case .local: return !book.isOnline && !Self.isMediaOnly(kind)
        // 養肥 — shelved but not opened yet: the ones you are letting grow.
        case .fattening: return book.currentPosition <= 0.001
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
    /// A clear capsule of glass: the page's paper shows through, one hairline holds the edge.
    /// The maintainer asked for 透明玻璃 rather than the ink-green pill the reference drew.
    func glassCapsule(_ scheme: ColorScheme) -> some View {
        self
            .background(.ultraThinMaterial, in: Capsule())
            .overlay(Capsule().strokeBorder(PaperPalette.hairline(scheme), lineWidth: 0.8))
    }

    func glassCircle(_ scheme: ColorScheme) -> some View {
        self
            .background(.ultraThinMaterial, in: Circle())
            .overlay(Circle().strokeBorder(PaperPalette.hairline(scheme), lineWidth: 0.8))
    }
}
