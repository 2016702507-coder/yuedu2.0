import SwiftUI

// MARK: - 首頁
//
// maintainer, 2026-11-06: redrawn to the reference clip — 首頁 on the left of the masthead,
// the greeting under it, then one large cover sitting in the middle of a carousel with the
// neighbouring books turned away from it, the title / author / chapter centred below, one
// deep 繼續閱讀 pill, and the page dots. Under that, 閱讀小箋 as a sheet of glass rather than
// a card, so the artwork shows through it.
//
// The page no longer paints paper of its own when the active theme carries a page background:
// the tab's backdrop (`ThemedSurfaceBackground`, `.global`) already holds the artwork, and
// 劍來's 山水 shows through instead of being covered by the warm gradient.
//
// It takes 資源庫's place in the root tabs. 資源庫 itself is not gone: 來源配置管理, 模組 and
// 遠端書庫 are all reachable from 設定 (`ProfileView`), which is why nothing here links to them.

struct ReadingHomeView: View {
    /// 書架 is another root tab, not a page this one can push: the shell hands the switch
    /// down rather than the page reaching for a tab it does not own.
    var onOpenBookshelf: () -> Void

    init(onOpenBookshelf: @escaping () -> Void = {}) {
        self.onOpenBookshelf = onOpenBookshelf
    }

    @EnvironmentObject private var store: BookStore
    @Environment(\.colorScheme) private var scheme

    @Bindable private var gs = GlobalSettings.shared
    @ObservedObject private var stats = ReadingStatsStore.shared
    @ObservedObject private var subscription = SubscriptionStore.shared

    @State private var readingBookID: UUID?
    @State private var showsStats = false
    @State private var now = Date()

    /// Which cover the carousel is resting on. Bound to `scrollPosition`, so it follows the
    /// reader's finger; the title under the carousel reads from it.
    @State private var centeredBookID: UUID?

    /// 一頁一頁地翻，擺十幾本剛好；再多就不是「今天這一本」而是書架了。
    private static let carouselLimit = 12

    /// 最近被打開的在前，沒打開過的補在後面 —— 進門先看到的就是上次那一本。
    private var carouselBooks: [ReadingBook] {
        let sorted = store.books.sorted {
            ($0.lastOpenedDate ?? $0.addedDate) > ($1.lastOpenedDate ?? $1.addedDate)
        }
        return Array(sorted.prefix(Self.carouselLimit))
    }

    private var centeredBook: ReadingBook? {
        guard let id = centeredBookID else { return carouselBooks.first }
        return carouselBooks.first { $0.id == id } ?? carouselBooks.first
    }

    private var centeredIndex: Int {
        guard let book = centeredBook,
              let index = carouselBooks.firstIndex(where: { $0.id == book.id })
        else { return 0 }
        return index
    }

    /// 沒有頁面背景圖時，這一頁仍然要像一張紙。
    private var showsThemedBackdrop: Bool {
        guard subscription.hasAccess(.readerThemePacks) else { return false }
        return gs.resolvedPageBackgroundSlice(for: .global, colorScheme: scheme) != nil
    }

    var body: some View {
        ScrollView {
            VStack(spacing: 0) {
                masthead
                carousel
                details
                readingNote
            }
            .padding(.bottom, 30)
        }
        .scrollIndicators(.hidden)
        .background {
            PaperBackground()
                .opacity(showsThemedBackdrop ? 0 : 1)
        }
        .onAppear {
            now = Date()
            settleCarousel()
        }
        .onChange(of: store.books.count) { _, _ in settleCarousel() }
        .fullScreenCover(isPresented: Binding(
            get: { readingBookID != nil },
            set: { if !$0 { readingBookID = nil } }
        )) {
            if let id = readingBookID {
                BookReaderView(bookId: id)
                    .environmentObject(store)
            }
        }
        .sheet(isPresented: $showsStats) {
            NavigationStack { ReadingStatsView() }
        }
    }

    /// 第一次進來停在最近讀的那本，而不是第一本。
    private func settleCarousel() {
        guard !carouselBooks.isEmpty else { return }
        if let current = centeredBookID, carouselBooks.contains(where: { $0.id == current }) {
            return
        }
        let target = store.books
            .filter { $0.lastOpenedDate != nil }
            .max { ($0.lastOpenedDate ?? .distantPast) < ($1.lastOpenedDate ?? .distantPast) }
        centeredBookID = target?.id ?? carouselBooks.first?.id
    }

    // MARK: Masthead

    private var masthead: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(alignment: .center) {
                Text(localized("首頁"))
                    .font(.system(size: 30, weight: .bold))
                    .foregroundStyle(PaperPalette.textPrimary(scheme))
                    .accessibilityAddTraits(.isHeader)
                Spacer(minLength: 8)
                readingTimeBadge
            }
            .padding(.top, 10)

            greetingLine
                .padding(.top, 26)

            Text(localized("喜歡的故事，總能讓日常鬆一口氣。"))
                .font(.system(size: 12.5))
                .foregroundStyle(PaperPalette.textSecondary(scheme))
                .padding(.top, 7)
        }
        .padding(.horizontal, 22)
    }

    /// 晚上好，慢慢讀。 — the greeting in ink, the wish in the page's darkest ink, one serif line.
    private var greetingLine: some View {
        HStack(alignment: .firstTextBaseline, spacing: 0) {
            Text(salutation)
                .font(PaperFont.serif(25))
                .foregroundStyle(PaperPalette.ink(scheme))
            Text(localized("慢慢讀。"))
                .font(PaperFont.serif(25))
                .foregroundStyle(PaperPalette.textPrimary(scheme))
        }
        .accessibilityElement(children: .combine)
    }

    private var salutation: String {
        switch Calendar.current.component(.hour, from: now) {
        case 5..<11: return localized("早上好，")
        case 11..<13: return localized("中午好，")
        case 13..<18: return localized("下午好，")
        case 18..<23: return localized("晚上好，")
        default: return localized("夜深了，")
        }
    }

    /// 右上角那一行小字：不搶戲，只是讓人知道今天讀了多久。
    private var readingTimeBadge: some View {
        Button {
            showsStats = true
        } label: {
            HStack(spacing: 5) {
                Image(systemName: "clock")
                    .font(.system(size: 10.5, weight: .medium))
                Text(localized("閱讀時光"))
                    .font(.system(size: 11.5))
            }
            .foregroundStyle(PaperPalette.textTertiary(scheme))
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background(Capsule().fill(PaperPalette.card(scheme).opacity(0.55)))
            .overlay(Capsule().strokeBorder(PaperPalette.hairline(scheme).opacity(0.7), lineWidth: 0.8))
        }
        .buttonStyle(.plain)
    }

    // MARK: 封面輪播

    /// One screenful of covers: the middle one square to the reader, the ones either side
    /// turned away and shrunk, the way the reference draws a small turntable of books.
    private var carousel: some View {
        GeometryReader { proxy in
            let width = proxy.size.width
            let slot = min(152, width * 0.40)
            let coverWidth = slot
            let coverHeight = coverWidth * 1.42

            ScrollView(.horizontal) {
                LazyHStack(spacing: 0) {
                    ForEach(carouselBooks) { book in
                        cover(book, width: coverWidth, height: coverHeight)
                            .frame(width: slot, height: proxy.size.height)
                            .scrollTransition(.interactive, axis: .horizontal) { content, phase in
                                content
                                    .scaleEffect(CGFloat(1 - abs(phase.value) * 0.34))
                                    .rotation3DEffect(
                                        .degrees(phase.value * -26),
                                        axis: (x: 0, y: 1, z: 0),
                                        anchor: .center,
                                        perspective: 0.5
                                    )
                                    .opacity(1 - abs(phase.value) * 0.12)
                            }
                    }
                }
                .scrollTargetLayout()
            }
            .contentMargins(.horizontal, max(0, (width - slot) / 2), for: .scrollContent)
            .scrollTargetBehavior(.viewAligned)
            .scrollPosition(id: $centeredBookID, anchor: .center)
            .scrollIndicators(.hidden)
            .scrollClipDisabled()
        }
        .frame(height: 254)
        .padding(.top, 18)
    }

    /// 書名・按鈕・頁碼：底下垫一层纸色，主題背景裡山水正好壓在字後面時也讀得清。
    private var details: some View {
        VStack(spacing: 0) {
            caption
            continueButton
            pageDots
        }
        .background {
            LinearGradient(
                colors: [
                    PaperPalette.page(scheme).opacity(0),
                    PaperPalette.page(scheme).opacity(0.62),
                    PaperPalette.page(scheme).opacity(0.88),
                ],
                startPoint: .top,
                endPoint: .bottom
            )
            .blur(radius: 26)
            .allowsHitTesting(false)
        }
    }

    // MARK: 書名・作者・章節

    @ViewBuilder
    private var caption: some View {
        if let book = centeredBook {
            VStack(spacing: 7) {
                Text(book.title)
                    .font(PaperFont.serif(19))
                    .foregroundStyle(PaperPalette.textPrimary(scheme))
                    .lineLimit(2)
                    .multilineTextAlignment(.center)
                    .minimumScaleFactor(0.85)

                if !book.author.isEmpty {
                    Text(String(format: localized("%@ 著"), book.author))
                        .font(.system(size: 11.5))
                        .foregroundStyle(PaperPalette.textTertiary(scheme))
                        .lineLimit(1)
                }

                if let chapter = chapterTitle(of: book) {
                    Text(chapter)
                        .font(.system(size: 12))
                        .foregroundStyle(PaperPalette.textSecondary(scheme))
                        .lineLimit(1)
                        .padding(.top, 2)
                }
            }
            .frame(maxWidth: .infinity)
            .padding(.horizontal, 34)
            .padding(.top, 18)
        } else {
            VStack(spacing: 8) {
                Text(localized("書架還是空的")).font(PaperFont.serif(19))
                Text(localized("去書架挑一本，這一頁就會亮起來。"))
                    .font(.system(size: 12.5))
                    .foregroundStyle(PaperPalette.textSecondary(scheme))
            }
            .foregroundStyle(PaperPalette.textPrimary(scheme))
            .frame(maxWidth: .infinity)
            .padding(.top, 26)
        }
    }

    // MARK: 繼續閱讀

    private var continueButton: some View {
        Button {
            if let book = centeredBook {
                readingBookID = book.id
            } else {
                onOpenBookshelf()
            }
        } label: {
            HStack(spacing: 10) {
                Text(centeredBook == nil ? localized("查看書架") : localized("繼續閱讀"))
                    .font(.system(size: 15, weight: .semibold))
                Image(systemName: "arrow.right")
                    .font(.system(size: 13, weight: .semibold))
            }
            .foregroundStyle(PaperPalette.page(scheme))
            .frame(maxWidth: .infinity)
            .padding(.vertical, 15)
            .background(Capsule().fill(PaperPalette.ink(scheme)))
            .shadow(color: Color.black.opacity(0.22), radius: 12, x: 0, y: 7)
        }
        .buttonStyle(.plain)
        .padding(.horizontal, 44)
        .padding(.top, 22)
        .accessibilityIdentifier("home_continue_reading")
    }

    // MARK: 頁碼點

    @ViewBuilder
    private var pageDots: some View {
        if carouselBooks.count > 1 {
            VStack(spacing: 7) {
                HStack(spacing: 5) {
                    ForEach(Array(carouselBooks.enumerated()), id: \.element.id) { index, _ in
                        Circle()
                            .fill(
                                index == centeredIndex
                                    ? PaperPalette.ink(scheme)
                                    : PaperPalette.textTertiary(scheme).opacity(0.4)
                            )
                            .frame(
                                width: index == centeredIndex ? 5 : 4,
                                height: index == centeredIndex ? 5 : 4
                            )
                    }
                }
                Text("\(centeredIndex + 1) / \(carouselBooks.count)")
                    .font(.system(size: 10.5))
                    .foregroundStyle(PaperPalette.textTertiary(scheme))
                    .monospacedDigit()
            }
            .padding(.top, 16)
            .animation(.easeOut(duration: 0.18), value: centeredIndex)
        }
    }

    // MARK: 閱讀小箋

    private var readingNote: some View {
        Button {
            showsStats = true
        } label: {
            HStack(alignment: .center, spacing: 14) {
                VStack(alignment: .leading, spacing: 8) {
                    HStack(spacing: 5) {
                        Image(systemName: "quote.opening")
                            .font(.system(size: 10.5, weight: .semibold))
                            .foregroundStyle(PaperPalette.ink(scheme).opacity(0.7))
                        Text(localized("閱讀小箋"))
                            .font(.system(size: 12.5, weight: .semibold))
                            .foregroundStyle(PaperPalette.textPrimary(scheme))
                    }

                    Text(localized("今日閱讀"))
                        .font(.system(size: 10.5))
                        .foregroundStyle(PaperPalette.textTertiary(scheme))

                    todayReadingValue
                }

                Spacer(minLength: 0)

                Text(noteOfTheDay)
                    .font(.system(size: 12))
                    .foregroundStyle(PaperPalette.textSecondary(scheme))
                    .multilineTextAlignment(.leading)
                    .lineSpacing(3.5)
                    .frame(maxWidth: 158, alignment: .leading)
            }
            .padding(.horizontal, 18)
            .padding(.vertical, 16)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background {
                RoundedRectangle(cornerRadius: 24, style: .continuous)
                    .fill(.ultraThinMaterial)
            }
            .overlay {
                RoundedRectangle(cornerRadius: 24, style: .continuous)
                    .strokeBorder(PaperPalette.hairline(scheme).opacity(0.75), lineWidth: 0.8)
            }
            .shadow(color: PaperPalette.shadow(scheme), radius: 16, x: 0, y: 8)
        }
        .buttonStyle(.plain)
        .padding(.horizontal, 22)
        .padding(.top, 26)
    }

    /// 不足 1 分鐘 / 12 分鐘 — the count is the one number on the page that should be large.
    private var todayReadingValue: some View {
        let seconds = todaySeconds
        let minutes = seconds / 60
        return HStack(alignment: .firstTextBaseline, spacing: 5) {
            if seconds == 0 {
                Text("0")
                    .font(PaperFont.serif(38))
                    .foregroundStyle(PaperPalette.textPrimary(scheme))
                Text(localized("分鐘"))
                    .font(.system(size: 10.5))
                    .foregroundStyle(PaperPalette.textSecondary(scheme))
            } else if minutes == 0 {
                Text(localized("不足"))
                    .font(.system(size: 11))
                    .foregroundStyle(PaperPalette.textSecondary(scheme))
                Text("1")
                    .font(PaperFont.serif(38))
                    .foregroundStyle(PaperPalette.textPrimary(scheme))
                Text(localized("分鐘"))
                    .font(.system(size: 10.5))
                    .foregroundStyle(PaperPalette.textSecondary(scheme))
            } else {
                Text("\(minutes)")
                    .font(PaperFont.serif(38))
                    .foregroundStyle(PaperPalette.textPrimary(scheme))
                    .monospacedDigit()
                Text(localized("分鐘"))
                    .font(.system(size: 10.5))
                    .foregroundStyle(PaperPalette.textSecondary(scheme))
            }
        }
        .accessibilityElement(children: .combine)
    }

    private var todaySeconds: Int {
        let start = Calendar.current.startOfDay(for: now)
        let total = stats.totalDuration(in: stats.sessionsInRange(from: start, to: now))
        return max(0, Int(total))
    }

    /// One sentence, the same all day: it is a small thing to notice, not a thing to rotate.
    private var noteOfTheDay: String {
        let lines = [
            localized("忙碌之外，也留了一點時間給自己。"),
            localized("故事還在原來那一頁等著。"),
            localized("讀幾頁，也算好好休息。"),
        ]
        let day = Calendar.current.ordinality(of: .day, in: .year, for: now) ?? 1
        return lines[day % lines.count]
    }

    // MARK: Pieces

    /// A book lying on the page: the cover, a darker spine down its left edge, and the shadow
    /// it casts to its right, so 3-D rather than a flat rectangle.
    private func cover(_ book: ReadingBook, width: CGFloat, height: CGFloat) -> some View {
        BookCoverImage(readingBook: book)
            .frame(width: width, height: height)
            .clipShape(RoundedRectangle(cornerRadius: 5, style: .continuous))
            .overlay(alignment: .leading) {
                LinearGradient(
                    colors: [Color.black.opacity(0.28), .clear],
                    startPoint: .leading,
                    endPoint: .trailing
                )
                .frame(width: width * 0.13)
                .clipShape(RoundedRectangle(cornerRadius: 5, style: .continuous))
                .allowsHitTesting(false)
            }
            .shadow(color: Color.black.opacity(0.3), radius: 18, x: 6, y: 14)
            .accessibilityHidden(true)
    }

    /// 第三章 · 未寄出的信 — from the table of contents where the book has one.
    private func chapterTitle(of book: ReadingBook) -> String? {
        guard let chapters = book.onlineChapters, !chapters.isEmpty else { return nil }
        let position = min(max(book.currentPosition, 0), 1)
        let index = min(chapters.count - 1, max(0, Int(position * Double(chapters.count))))
        return chapters[index].title
    }
}
