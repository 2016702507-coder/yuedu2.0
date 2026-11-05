import SwiftUI

// MARK: - 首頁
//
// The reader's landing page (maintainer's reference, 2026-11-04): drawn like a page of a
// book rather than a dashboard — warm paper, a serif masthead, one large cover for the book
// being read, and a small card that says how long they read today.
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

    @ObservedObject private var stats = ReadingStatsStore.shared

    @State private var readingBookID: UUID?
    @State private var showsStats = false
    @State private var now = Date()

    private var recentBook: ReadingBook? {
        store.books
            .filter { $0.lastOpenedDate != nil }
            .max { ($0.lastOpenedDate ?? .distantPast) < ($1.lastOpenedDate ?? .distantPast) }
    }

    /// The shelf minus the book on the card, newest first: 書架裡，還有故事.
    private var otherBooks: [ReadingBook] {
        store.books
            .filter { $0.id != recentBook?.id }
            .sorted { ($0.lastOpenedDate ?? $0.addedDate) > ($1.lastOpenedDate ?? $1.addedDate) }
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                masthead
                recentSection
                readingNote
                shelfSection
            }
            .padding(.horizontal, 20)
            .padding(.bottom, 28)
        }
        .scrollIndicators(.hidden)
        .background(PaperBackground())
        .onAppear { now = Date() }
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

    // MARK: Masthead

    private var masthead: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 7) {
                    greetingLine
                    Text(localized("喜歡的故事，總能讓日常鬆一口氣。"))
                        .font(.system(size: 13))
                        .foregroundStyle(PaperPalette.textSecondary(scheme))
                }
                Spacer(minLength: 8)
                nightBadge
            }
        }
        .padding(.top, 8)
        .padding(.bottom, 22)
    }

    /// 晚上好，慢慢讀。 — the greeting in ink, the wish in the page's darkest ink, one serif line.
    private var greetingLine: some View {
        HStack(alignment: .firstTextBaseline, spacing: 0) {
            Text(salutation)
                .font(PaperFont.serif(27))
                .foregroundStyle(PaperPalette.ink(scheme))
            Text(localized("慢慢讀。"))
                .font(PaperFont.serif(27))
                .foregroundStyle(PaperPalette.textPrimary(scheme))
        }
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(.isHeader)
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

    private var nightBadge: some View {
        HStack(spacing: 5) {
            Image(systemName: "moon.stars")
                .font(.system(size: 11, weight: .medium))
            Text(localized("夜讀時光"))
                .font(.system(size: 11.5))
        }
        .foregroundStyle(PaperPalette.textTertiary(scheme))
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .background(Capsule().fill(PaperPalette.card(scheme).opacity(0.7)))
        .overlay(Capsule().strokeBorder(PaperPalette.hairline(scheme), lineWidth: 0.8))
    }

    // MARK: 最近陪伴你的故事

    private var recentSection: some View {
        VStack(alignment: .leading, spacing: 14) {
            PaperSectionHeader(localized("最近陪伴你的故事"), symbol: "book.closed") {
                Button {
                    onOpenBookshelf()
                } label: {
                    HStack(spacing: 3) {
                        Text(localized("閱讀記錄"))
                        Image(systemName: "arrow.up.right")
                            .font(.system(size: 9, weight: .semibold))
                    }
                    .font(.system(size: 12))
                    .foregroundStyle(PaperPalette.textTertiary(scheme))
                }
                .buttonStyle(.plain)
            }

            if let book = recentBook {
                recentCard(book)
            } else {
                emptyCard
            }
        }
    }

    private func recentCard(_ book: ReadingBook) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(alignment: .top, spacing: 18) {
                cover(book, width: 122, height: 178)

                VStack(alignment: .leading, spacing: 0) {
                    Text(book.title)
                        .font(PaperFont.serif(22))
                        .foregroundStyle(PaperPalette.textPrimary(scheme))
                        .lineLimit(2)
                        .minimumScaleFactor(0.8)

                    Text(book.author)
                        .font(.system(size: 12.5))
                        .foregroundStyle(PaperPalette.textSecondary(scheme))
                        .lineLimit(1)
                        .padding(.top, 6)

                    Spacer(minLength: 12)

                    Text(localized("為你保留了上次的位置"))
                        .font(.system(size: 11))
                        .foregroundStyle(PaperPalette.textTertiary(scheme))

                    if let chapter = chapterTitle(of: book) {
                        Text(chapter)
                            .font(.system(size: 13.5, weight: .semibold))
                            .foregroundStyle(PaperPalette.textPrimary(scheme))
                            .lineLimit(2)
                            .padding(.top, 5)
                    }

                    Button {
                        readingBookID = book.id
                    } label: {
                        HStack(spacing: 6) {
                            Text(localized("繼續閱讀"))
                                .font(.system(size: 13, weight: .medium))
                            Image(systemName: "arrow.right")
                                .font(.system(size: 11, weight: .semibold))
                        }
                        .foregroundStyle(PaperPalette.ink(scheme))
                        .padding(.horizontal, 16)
                        .padding(.vertical, 9)
                        .background(Capsule().fill(PaperPalette.iconTile(scheme)))
                        .overlay(Capsule().strokeBorder(PaperPalette.hairline(scheme), lineWidth: 0.8))
                    }
                    .buttonStyle(.plain)
                    .padding(.top, 14)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }

            HStack(spacing: 6) {
                Text(localized("最近閱讀"))
                Text("·")
                Text(stamp(for: book.lastOpenedDate ?? book.addedDate))
                Spacer(minLength: 8)
                Button {
                    readingBookID = book.id
                } label: {
                    HStack(spacing: 4) {
                        Image(systemName: "bookmark")
                            .font(.system(size: 11))
                        Text(localized("查看詳情"))
                    }
                    .font(.system(size: 11.5))
                    .foregroundStyle(PaperPalette.textTertiary(scheme))
                }
                .buttonStyle(.plain)
            }
            .font(.system(size: 11.5))
            .foregroundStyle(PaperPalette.textTertiary(scheme))
            .padding(.top, 20)
        }
    }

    private var emptyCard: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(localized("還沒有最近在讀的書"))
                .font(PaperFont.serif(19))
                .foregroundStyle(PaperPalette.textPrimary(scheme))
            Text(localized("去書架挑一本，這裡就會亮起來。"))
                .font(.system(size: 12.5))
                .foregroundStyle(PaperPalette.textSecondary(scheme))
            Button {
                onOpenBookshelf()
            } label: {
                Text(localized("查看書架"))
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(PaperPalette.ink(scheme))
                    .padding(.horizontal, 16)
                    .padding(.vertical, 9)
                    .background(Capsule().fill(PaperPalette.iconTile(scheme)))
                    .overlay(Capsule().strokeBorder(PaperPalette.hairline(scheme), lineWidth: 0.8))
            }
            .buttonStyle(.plain)
            .padding(.top, 6)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(20)
        .paperCard(radius: 24)
    }

    // MARK: 閱讀小箋

    private var readingNote: some View {
        Button {
            showsStats = true
        } label: {
            VStack(alignment: .leading, spacing: 14) {
                HStack(spacing: 6) {
                    Image(systemName: "quote.opening")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(PaperPalette.ink(scheme).opacity(0.7))
                    Text(localized("閱讀小箋"))
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(PaperPalette.textPrimary(scheme))
                    Spacer(minLength: 8)
                    HStack(spacing: 3) {
                        Image(systemName: "arrow.up.right")
                            .font(.system(size: 9, weight: .semibold))
                        Text(localized("閱讀統計"))
                    }
                    .font(.system(size: 11.5))
                    .foregroundStyle(PaperPalette.textTertiary(scheme))
                }

                HStack(alignment: .bottom, spacing: 16) {
                    VStack(alignment: .leading, spacing: 3) {
                        Text(localized("今日閱讀"))
                            .font(.system(size: 11.5))
                            .foregroundStyle(PaperPalette.textTertiary(scheme))
                        todayReadingValue
                    }
                    Spacer(minLength: 0)
                    Text(noteOfTheDay)
                        .font(.system(size: 13))
                        .foregroundStyle(PaperPalette.textSecondary(scheme))
                        .multilineTextAlignment(.leading)
                        .lineSpacing(3)
                        .frame(maxWidth: 190, alignment: .leading)
                }
            }
            .padding(18)
            .frame(maxWidth: .infinity, alignment: .leading)
            .paperCard(radius: 24)
        }
        .buttonStyle(.plain)
        .padding(.top, 26)
    }

    /// 不足 1 分鐘 / 12 分鐘 — the count is the one number on the page that should be large.
    private var todayReadingValue: some View {
        let seconds = todaySeconds
        let minutes = seconds / 60
        return HStack(alignment: .firstTextBaseline, spacing: 4) {
            if seconds == 0 {
                Text("0")
                    .font(PaperFont.serif(34))
                    .foregroundStyle(PaperPalette.textPrimary(scheme))
                Text(localized("分鐘"))
                    .font(.system(size: 11.5))
                    .foregroundStyle(PaperPalette.textSecondary(scheme))
            } else if minutes == 0 {
                Text(localized("不足"))
                    .font(.system(size: 12))
                    .foregroundStyle(PaperPalette.textSecondary(scheme))
                Text("1")
                    .font(PaperFont.serif(34))
                    .foregroundStyle(PaperPalette.textPrimary(scheme))
                Text(localized("分鐘"))
                    .font(.system(size: 11.5))
                    .foregroundStyle(PaperPalette.textSecondary(scheme))
            } else {
                Text("\(minutes)")
                    .font(PaperFont.serif(34))
                    .foregroundStyle(PaperPalette.textPrimary(scheme))
                    .monospacedDigit()
                Text(localized("分鐘"))
                    .font(.system(size: 11.5))
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

    // MARK: 書架裡，還有故事

    private var shelfSection: some View {
        VStack(alignment: .leading, spacing: 14) {
            PaperSectionHeader(localized("書架裡，還有故事"), symbol: "books.vertical") {
                Button {
                    onOpenBookshelf()
                } label: {
                    HStack(spacing: 3) {
                        Text(localized("查看書架"))
                        Image(systemName: "arrow.up.right")
                            .font(.system(size: 9, weight: .semibold))
                    }
                    .font(.system(size: 12))
                    .foregroundStyle(PaperPalette.textTertiary(scheme))
                }
                .buttonStyle(.plain)
            }

            if otherBooks.isEmpty {
                Text(localized("書架上還只有這一本。"))
                    .font(.system(size: 12.5))
                    .foregroundStyle(PaperPalette.textTertiary(scheme))
                    .padding(.vertical, 4)
            } else {
                ScrollView(.horizontal) {
                    HStack(alignment: .bottom, spacing: 14) {
                        ForEach(otherBooks.prefix(8)) { book in
                            Button {
                                readingBookID = book.id
                            } label: {
                                VStack(alignment: .leading, spacing: 7) {
                                    cover(book, width: 84, height: 122)
                                    Text(book.title)
                                        .font(.system(size: 11.5))
                                        .foregroundStyle(PaperPalette.textSecondary(scheme))
                                        .lineLimit(1)
                                        .frame(width: 84, alignment: .leading)
                                }
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    .padding(.vertical, 4)
                    .padding(.trailing, 8)
                }
                .scrollIndicators(.hidden)
            }
        }
        .padding(.top, 28)
    }

    // MARK: Pieces

    /// A book lying on the page: the cover, a darker spine down its left edge, and the shadow
    /// it casts to its right, so 3-D rather than a flat rectangle (`rotation3DEffect`).
    private func cover(_ book: ReadingBook, width: CGFloat, height: CGFloat) -> some View {
        BookCoverImage(readingBook: book)
            .frame(width: width, height: height)
            .clipShape(RoundedRectangle(cornerRadius: 4, style: .continuous))
            .overlay(alignment: .leading) {
                LinearGradient(
                    colors: [Color.black.opacity(0.26), .clear],
                    startPoint: .leading,
                    endPoint: .trailing
                )
                .frame(width: width * 0.12)
                .clipShape(RoundedRectangle(cornerRadius: 4, style: .continuous))
                .allowsHitTesting(false)
            }
            .rotation3DEffect(.degrees(7), axis: (x: 0, y: 1, z: 0), anchor: .leading, perspective: 0.32)
            .shadow(color: Color.black.opacity(0.26), radius: 14, x: 9, y: 12)
            .accessibilityHidden(true)
    }

    /// 第三章 · 未寄出的信 — from the table of contents where the book has one.
    private func chapterTitle(of book: ReadingBook) -> String? {
        guard let chapters = book.onlineChapters, !chapters.isEmpty else { return nil }
        let position = min(max(book.currentPosition, 0), 1)
        let index = min(chapters.count - 1, max(0, Int(position * Double(chapters.count))))
        return chapters[index].title
    }

    private var stampFormatter: DateFormatter {
        let formatter = DateFormatter()
        formatter.setLocalizedDateFormatFromTemplate("Md HH:mm")
        return formatter
    }

    private func stamp(for date: Date) -> String {
        stampFormatter.string(from: date)
    }
}
