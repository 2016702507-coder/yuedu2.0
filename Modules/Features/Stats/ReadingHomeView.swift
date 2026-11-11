import SwiftUI

// MARK: - 首页
//
// maintainer, 2026-11-06: redrawn to the reference clip — 首页 on the left of the masthead,
// the greeting under it, then one large cover sitting in the middle of a carousel with the
// neighbouring books turned away from it, the title / author / chapter centred below, one
// deep 继续阅读 pill, and the page dots. Under that, 阅读小笺 as a sheet of glass rather than
// a card, so the artwork shows through it.
//
// The page no longer paints paper of its own when the active theme carries a page background:
// the tab's backdrop (`ThemedSurfaceBackground`, `.global`) already holds the artwork, and
// 剑来's 山水 shows through instead of being covered by the warm gradient.
//
// It takes 资源库's place in the root tabs. 资源库 itself is not gone: 来源配置管理, 模组 and
// 远端书库 are all reachable from 设置 (`ProfileView`), which is why nothing here links to them.

struct ReadingHomeView: View {
    /// 书架 is another root tab, not a page this one can push: the shell hands the switch
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

    /// Where `scrollPosition` puts the strip: written by `settleCarousel` to open on the book
    /// last read, never read back for the caption.
    @State private var centeredBookID: UUID?
    /// 中间那本封面在 window 里的位置：开书卡片从这里展开，和书架一样。
    @State private var centeredCoverFrame: CGRect?

    /// The cover square on screen, measured rather than reported. `scrollPosition`'s binding
    /// does not reliably write back on iOS 17 (`LazyHStack` + `viewAligned`), which left the
    /// caption, the dots and 继续阅读 pointing at the book the reader had already swiped past;
    /// each cover now reports its own mid line, and the one near the screen's middle wins.
    @State private var restingBookID: UUID?

    /// The space the covers measure their positions in.
    private static let carouselSpace = "homeCarousel"

    /// 一页一页地翻，摆十几本刚好；再多就不是「今天这一本」而是书架了。
    private static let carouselLimit = 12

    /// 最近被打开的在前，没打开过的补在后面 —— 进门先看到的就是上次那一本。
    private var carouselBooks: [ReadingBook] {
        let sorted = store.books.sorted {
            ($0.lastOpenedDate ?? $0.addedDate) > ($1.lastOpenedDate ?? $1.addedDate)
        }
        return Array(sorted.prefix(Self.carouselLimit))
    }

    private var centeredBook: ReadingBook? {
        guard let id = restingBookID ?? centeredBookID else { return carouselBooks.first }
        return carouselBooks.first { $0.id == id } ?? carouselBooks.first
    }

    private var centeredIndex: Int {
        guard let book = centeredBook,
              let index = carouselBooks.firstIndex(where: { $0.id == book.id })
        else { return 0 }
        return index
    }

    /// 没有页面背景图时，这一页仍然要像一张纸。
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
            set: { isPresented in
                guard !isPresented else { return }
                readingBookID = nil
                // 合上阅读器：刚读的这本因为「最近打开」跳到第一位，把轮播重新摆回它身上。
                recenterCarousel()
            }
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

    /// 第一次进来停在最近读的那本，而不是第一本。
    private func settleCarousel() {
        guard !carouselBooks.isEmpty else {
            centeredBookID = nil
            restingBookID = nil
            return
        }
        if let current = restingBookID, carouselBooks.contains(where: { $0.id == current }) {
            return
        }
        let target = store.books
            .filter { $0.lastOpenedDate != nil }
            .max { ($0.lastOpenedDate ?? .distantPast) < ($1.lastOpenedDate ?? .distantPast) }
        let settled = target?.id ?? carouselBooks.first?.id
        centeredBookID = settled
        restingBookID = settled
    }

    /// A cover whose middle line sits within half a slot of the screen's middle is the one
    /// square on; the ones either side are turned away. Only a change of book writes state,
    /// so dragging the strip does not recompute the page on every frame.
    private func settleResting(_ book: ReadingBook, midX: CGFloat, middle: CGFloat, slot: CGFloat) {
        guard abs(midX - middle) < slot * 0.5 else { return }
        if restingBookID != book.id { restingBookID = book.id }
    }

    /// 进阅读：有声书先让播放器长出来；其余统一走书架那张封面翻开卡片。
    private func openBook(_ book: ReadingBook) {
        guard !NowPlayingHub.shared.openIfAudiobook(book, store: store) else { return }
        // 首页「继续阅读」以前是黑屏「加载中…」直接硬切；现在和书架同一个
        // 开书界面。转场不可用时回落到原来的全屏模态，保证书一定打得开。
        if ReaderOpener.open(
            bookID: book.id,
            store: store,
            coverFrame: centeredCoverFrame,
            onDismiss: { recenterCarousel() }
        ) { return }
        readingBookID = book.id
    }

    /// 把刚合上的那本摆回中间。排序会把它挪到第一位，写回 `scrollPosition` 让轮播跟过去。
    private func recenterCarousel() {
        guard let id = restingBookID ?? carouselBooks.first?.id else { return }
        centeredBookID = id
    }

    // MARK: Masthead

    private var masthead: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(alignment: .center) {
                Text(localized("首页"))
                    .font(.system(size: 30, weight: .bold))
                    .foregroundStyle(PaperPalette.textPrimary(scheme))
                    .accessibilityAddTraits(.isHeader)
                Spacer(minLength: 8)
                readingTimeBadge
            }
            .padding(.top, 10)

            greetingLine
                .padding(.top, 26)

            Text(localized("喜欢的故事，总能让日常松一口气。"))
                .font(.system(size: 12.5))
                .foregroundStyle(PaperPalette.textSecondary(scheme))
                .padding(.top, 7)
        }
        .padding(.horizontal, 22)
    }

    /// 晚上好，慢慢读。 — the greeting in ink, the wish in the page's darkest ink, one serif line.
    private var greetingLine: some View {
        HStack(alignment: .firstTextBaseline, spacing: 0) {
            Text(salutation)
                .font(PaperFont.serif(25))
                .foregroundStyle(PaperPalette.ink(scheme))
            Text(localized("慢慢读。"))
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

    /// 右上角那一行小字：不抢戏，只是让人知道今天读了多久。
    private var readingTimeBadge: some View {
        Button {
            showsStats = true
        } label: {
            HStack(spacing: 5) {
                Image(systemName: "clock")
                    .font(.system(size: 10.5, weight: .medium))
                Text(localized("阅读时光"))
                    .font(.system(size: 11.5))
            }
            .foregroundStyle(PaperPalette.textTertiary(scheme))
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .interfaceCardSurface(in: Capsule(), fill: PaperPalette.card(scheme))
            .overlay(Capsule().strokeBorder(PaperPalette.hairline(scheme).opacity(0.5), lineWidth: 0.6))
        }
        .buttonStyle(.plain)
    }

    // MARK: 封面轮播

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
                            .background {
                                // 让位置自己说话：每张卡量出自己的中线，落在屏幕中线附近的那本
                                // 就是「当前这一本」。不依赖 `scrollPosition` 回写。
                                GeometryReader { geometry in
                                    Color.clear
                                        .onChange(
                                            of: geometry.frame(in: .named(Self.carouselSpace)).midX,
                                            initial: true
                                        ) { _, midX in
                                            settleResting(book, midX: midX, middle: width / 2, slot: slot)
                                        }
                                }
                            }
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
                            // 点封面直接进阅读；拖动时这个手势自动让位给滚动。
                            .contentShape(Rectangle())
                            .onTapGesture { openBook(book) }
                            .accessibilityElement(children: .ignore)
                            .accessibilityAddTraits(.isButton)
                            .accessibilityLabel(book.title)
                            .accessibilityValue(book.author)
                    }
                }
                .scrollTargetLayout()
            }
            .contentMargins(.horizontal, max(0, (width - slot) / 2), for: .scrollContent)
            .scrollTargetBehavior(.viewAligned)
            .scrollPosition(id: $centeredBookID, anchor: .center)
            .scrollIndicators(.hidden)
            .scrollClipDisabled()
            .coordinateSpace(.named(Self.carouselSpace))
            .onChange(of: proxy.frame(in: .global), initial: true) { _, global in
                centeredCoverFrame = CGRect(
                    x: global.minX + (global.width - coverWidth) / 2,
                    y: global.minY + (global.height - coverHeight) / 2,
                    width: coverWidth,
                    height: coverHeight
                )
            }
        }
        .frame(height: 254)
        .padding(.top, 18)
    }

    /// 书名・按钮・页码：底下垫一层纸色，主题背景里山水正好压在字后面时也读得清。
    private var details: some View {
        VStack(spacing: 0) {
            caption
            continueButton
            pageDots
        }
        .background {
            // 四段停靠点代替 `.blur`：轮播在滑，模糊层每帧都要重算，会拖慢手指；
            // 色阶本身已经够软，看不出是渐变。
            LinearGradient(
                stops: [
                    .init(color: PaperPalette.page(scheme).opacity(0), location: 0),
                    .init(color: PaperPalette.page(scheme).opacity(0.55), location: 0.34),
                    .init(color: PaperPalette.page(scheme).opacity(0.84), location: 0.72),
                    .init(color: PaperPalette.page(scheme).opacity(0.92), location: 1),
                ],
                startPoint: .top,
                endPoint: .bottom
            )
            .allowsHitTesting(false)
        }
    }

    // MARK: 书名・作者・章节

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
                Text(localized("书架还是空的")).font(PaperFont.serif(19))
                Text(localized("去书架挑一本，这里就会亮起来。"))
                    .font(.system(size: 12.5))
                    .foregroundStyle(PaperPalette.textSecondary(scheme))
            }
            .foregroundStyle(PaperPalette.textPrimary(scheme))
            .frame(maxWidth: .infinity)
            .padding(.top, 26)
        }
    }

    // MARK: 继续阅读

    private var continueButton: some View {
        Button {
            if let book = centeredBook {
                openBook(book)
            } else {
                onOpenBookshelf()
            }
        } label: {
            HStack(spacing: 10) {
                Text(centeredBook == nil ? localized("查看书架") : localized("继续阅读"))
                    // 跟随读者导入的界面字体：没有导入时 fixedFont 回落系统字体，
                    // 字号字重不变，外观与原来一致。箭头是 SF Symbol，仍用系统字体。
                    .font(GlobalAppTypography.fixedFont(size: 15, weight: .semibold))
                Image(systemName: "arrow.right")
                    .font(.system(size: 13, weight: .semibold))
            }
            // 玻璃是浅色半透明，白字会看不清；改用主题强调色，与页码点同色。
            .foregroundStyle(PaperPalette.ink(scheme))
            .frame(maxWidth: .infinity)
            .padding(.vertical, 15)
            // 与书架页「继续阅读」的 glassCapsule、本页「阅读小笺」同一套玻璃。
            .clearGlassSurface(in: Capsule())
            .overlay(Capsule().strokeBorder(PaperPalette.hairline(scheme), lineWidth: 0.8))
            .shadow(color: PaperPalette.shadow(scheme), radius: 16, x: 0, y: 8)
        }
        .buttonStyle(.plain)
        .padding(.horizontal, 44)
        .padding(.top, 22)
        .accessibilityIdentifier("home_continue_reading")
    }

    // MARK: 页码点

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

    // MARK: 阅读小笺

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
                        Text(localized("阅读小笺"))
                            .font(.system(size: 12.5, weight: .semibold))
                            .foregroundStyle(PaperPalette.textPrimary(scheme))
                    }

                    Text(localized("今日阅读"))
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
            .interfaceCardSurface(
                in: RoundedRectangle(cornerRadius: 24, style: .continuous),
                fill: PaperPalette.card(scheme)
            )
            .overlay {
                RoundedRectangle(cornerRadius: 24, style: .continuous)
                    .strokeBorder(PaperPalette.hairline(scheme).opacity(0.55), lineWidth: 0.6)
            }
        }
        .buttonStyle(.plain)
        .padding(.horizontal, 22)
        .padding(.top, 26)
    }

    /// 不足 1 分钟 / 12 分钟 — the count is the one number on the page that should be large.
    private var todayReadingValue: some View {
        let seconds = todaySeconds
        let minutes = seconds / 60
        return HStack(alignment: .firstTextBaseline, spacing: 5) {
            if seconds == 0 {
                Text("0")
                    .font(PaperFont.serif(38))
                    .foregroundStyle(PaperPalette.textPrimary(scheme))
                Text(localized("分钟"))
                    .font(.system(size: 10.5))
                    .foregroundStyle(PaperPalette.textSecondary(scheme))
            } else if minutes == 0 {
                Text(localized("不足"))
                    .font(.system(size: 11))
                    .foregroundStyle(PaperPalette.textSecondary(scheme))
                Text("1")
                    .font(PaperFont.serif(38))
                    .foregroundStyle(PaperPalette.textPrimary(scheme))
                Text(localized("分钟"))
                    .font(.system(size: 10.5))
                    .foregroundStyle(PaperPalette.textSecondary(scheme))
            } else {
                Text("\(minutes)")
                    .font(PaperFont.serif(38))
                    .foregroundStyle(PaperPalette.textPrimary(scheme))
                    .monospacedDigit()
                Text(localized("分钟"))
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
            localized("忙碌之外，也留了一点时间给自己。"),
            localized("故事还在原来那一页等著。"),
            localized("读几页，也算好好休息。"),
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
