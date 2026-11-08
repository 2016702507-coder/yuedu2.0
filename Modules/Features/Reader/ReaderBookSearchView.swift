import SwiftUI

/// 全书搜寻's sheet: the searches made in this book, the search running now, and its hits
/// by chapter. The search itself belongs to `ReaderBookSearchSession`, which the reader keeps,
/// so the last results are still here when the sheet opens again.
struct ReaderBookSearchView: View {
    @Bindable var session: ReaderBookSearchSession
    /// The selection's words when 搜寻 came from the text menu; searched as soon as it opens.
    let initialQuery: String
    /// Whether 替换规则 change this book's text, so turning them off can find anything.
    let offersReplaceRules: Bool
    let onSearch: (String) -> Void
    /// The sheet opened without words of its own: the reader refreshes stale results.
    let onReopen: () -> Void
    let onSelect: (Int) -> Void
    let onClose: () -> Void

    @State private var query: String
    @AppStorage private var history: RecentSearchQueries

    init(
        session: ReaderBookSearchSession,
        historyKey: String,
        initialQuery: String = "",
        offersReplaceRules: Bool,
        onSearch: @escaping (String) -> Void,
        onReopen: @escaping () -> Void,
        onSelect: @escaping (Int) -> Void,
        onClose: @escaping () -> Void
    ) {
        self.session = session
        self.initialQuery = initialQuery
        self.offersReplaceRules = offersReplaceRules
        self.onSearch = onSearch
        self.onReopen = onReopen
        self.onSelect = onSelect
        self.onClose = onClose
        _query = State(initialValue: initialQuery.isEmpty ? session.query : initialQuery)
        _history = AppStorage(wrappedValue: RecentSearchQueries(), historyKey)
    }

    var body: some View {
        NavigationStack {
            content
                .background(PageBackgroundView(scope: .settings).ignoresSafeArea())
                .pageBackgroundToolbar(for: .settings)
                .navigationTitle(localized("搜寻书籍"))
                .toolbarTitleDisplayMode(.inline)
                .toolbar { toolbarContent }
        }
        .searchable(text: $query, prompt: Text(localized("Search Book")))
        .onSubmit(of: .search) { submit(query) }
        .onChange(of: query) { _, newValue in
            // The field's own clear button: back to the recent searches.
            if newValue.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { session.clear() }
        }
        .onChange(of: session.options) {
            guard !session.query.isEmpty else { return }
            onSearch(session.query)
        }
        .task {
            if initialQuery.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                onReopen()
            } else {
                submit(initialQuery)
            }
        }
    }

    // MARK: - Content

    @ViewBuilder
    private var content: some View {
        if session.query.isEmpty {
            recentSearches
        } else {
            switch session.phase {
            case .failed(let error):
                failure(error)
            case .finished where session.hits.isEmpty:
                ContentUnavailableView {
                    UnavailableLabel(localized("无搜寻结果"), systemImage: "doc.text.magnifyingglass")
                } description: {
                    Text(noResultsDescription).font(DSFont.unavailableDescription).foregroundStyle(DSColor.textSecondary)
                }
            case .idle, .searching, .finished:
                results
            }
        }
    }

    @ViewBuilder
    private var recentSearches: some View {
        if history.queries.isEmpty {
            ContentUnavailableView {
                UnavailableLabel(localized("搜寻书籍"), systemImage: "magnifyingglass")
            } description: {
                Text(localized("输入关键字搜寻整本书。")).font(DSFont.unavailableDescription).foregroundStyle(DSColor.textSecondary)
            }
        } else {
            List {
                Section {
                    ForEach(history.queries, id: \.self) { recent in
                        Button {
                            query = recent
                            submit(recent)
                        } label: {
                            Label(recent, systemImage: "clock.arrow.circlepath")
                                .foregroundStyle(DSColor.textPrimary)
                        }
                        .interfaceSectionSurface()
                    }
                    .onDelete { history = history.removing(atOffsets: $0) }
                } header: {
                    HStack {
                        Text(localized("最近搜索"))
                        Spacer()
                        Button(localized("清除")) { history = RecentSearchQueries() }
                            .font(DSFont.footnote)
                    }
                }
            }
            .softScrollEdges()
            .listStyle(.insetGrouped)
            // Hiding the list background alone leaves each row painting its own
            // opaque system fill over the `PageBackgroundView` below. docs/design.md §4.1.
            .scrollContentBackground(.hidden)
        }
    }

    private var results: some View {
        List {
            Section {
                status
                    .interfaceSectionSurface()
            } footer: {
                if let note = resultsNote {
                    Text(note).dsSectionFooter()
                }
            }
            ForEach(session.sections) { section in
                Section {
                    ForEach(section.rows) { row in
                        hitRow(row.hit, index: row.index)
                    }
                } header: {
                    Text(section.title)
                }
            }
        }
        .softScrollEdges()
        .listStyle(.insetGrouped)
        .scrollContentBackground(.hidden)
    }

    @ViewBuilder
    private var status: some View {
        if session.phase == .searching {
            ProgressView(
                value: Double(session.searchedChapterCount),
                total: Double(max(session.totalChapterCount, 1))
            ) {
                Text(localized("正在搜寻…"))
                    .font(DSFont.subheadline)
                    .foregroundStyle(DSColor.textPrimary)
            } currentValueLabel: {
                Text(String(format: localized("已搜寻 %d／%d 章"),
                            session.searchedChapterCount, session.totalChapterCount))
                    .font(DSFont.caption)
                    .foregroundStyle(DSColor.textSecondary)
                    .monospacedDigit()
            }
        } else {
            Text(String(format: localized("共 %d 个结果"), session.hits.count))
                .font(DSFont.subheadline)
                .foregroundStyle(DSColor.textPrimary)
                .monospacedDigit()
        }
    }

    private func hitRow(_ hit: ReaderBookSearchHit, index: Int) -> some View {
        Button {
            onSelect(index)
        } label: {
            Text(attributedSnippet(hit.snippet))
                .font(DSFont.subheadline)
                .foregroundStyle(DSColor.textPrimary)
                .lineLimit(2)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .interfaceSectionSurface()
    }

    private func failure(_ error: ReaderBookSearchError) -> some View {
        let title: String, message: String
        switch error {
        case .invalidPattern:
            title = localized("正规表示式有误")
            message = localized("检查表示式的写法后再试一次。")
        case .timedOut:
            title = localized("搜寻已停止")
            message = localized("这个正规表示式运算太久，换个写法再试一次。")
        case .unsupported:
            title = localized("无法搜寻")
            message = localized("这本书没有可以搜寻的文字。")
        }
        return ContentUnavailableView {
            UnavailableLabel(title, systemImage: "exclamationmark.magnifyingglass")
        } description: {
            Text(message).font(DSFont.unavailableDescription).foregroundStyle(DSColor.textSecondary)
        }
    }

    // MARK: - Toolbar

    @ToolbarContentBuilder
    private var toolbarContent: some ToolbarContent {
        ToolbarItem(placement: .topBarLeading) {
            Button(action: onClose) {
                Image(systemName: "xmark")
            }
            .accessibilityLabel(localized("关闭"))
        }
        ToolbarItemGroup(placement: .topBarTrailing) {
            if session.phase == .searching {
                Button(localized("停止")) { session.stop() }
            }
            Menu {
                Toggle(localized("正则表达式"), isOn: $session.options.isRegex)
                if offersReplaceRules {
                    Toggle(localized("套用替换规则"), isOn: $session.options.appliesReplaceRules)
                }
            } label: {
                Image(systemName: "line.3.horizontal.decrease.circle")
            }
            .accessibilityLabel(localized("搜寻选项"))
        }
    }

    // MARK: - Text

    private var unsearchedNote: String? {
        let count = session.notDownloadedChapterCount
        return count > 0 ? String(format: localized("有 %d 章尚未下载，未搜寻。"), count) : nil
    }

    /// What the count leaves out: chapters not on the device, and hits past the limit.
    private var resultsNote: String? {
        var parts: [String] = []
        if let unsearchedNote { parts.append(unsearchedNote) }
        if session.reachedHitLimit {
            parts.append(String(format: localized("只列出前 %d 个结果。"), ReaderBookSearchSession.hitLimit))
        }
        return parts.isEmpty ? nil : parts.joined(separator: " ")
    }

    private var noResultsDescription: String {
        [localized("换个关键字再试一次。"), unsearchedNote].compactMap { $0 }.joined(separator: "\n")
    }

    private func attributedSnippet(_ snippet: ReaderBookSearchSnippet) -> AttributedString {
        var text = AttributedString((snippet.continuesBefore ? "…" : "") + snippet.leading)
        var match = AttributedString(snippet.match)
        match.font = DSFont.subheadline.weight(.semibold)
        match.foregroundColor = DSColor.accent
        text.append(match)
        text.append(AttributedString(snippet.trailing + (snippet.continuesAfter ? "…" : "")))
        return text
    }

    private func submit(_ text: String) {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        history = history.recording(trimmed)
        onSearch(trimmed)
    }
}

#Preview {
    ReaderBookSearchView(
        session: ReaderBookSearchSession(),
        historyKey: "preview_reader_search_history",
        offersReplaceRules: true,
        onSearch: { _ in },
        onReopen: {},
        onSelect: { _ in },
        onClose: {}
    )
}

#Preview("Results") {
    let session = ReaderBookSearchSession()
    let chapters = ["风起了，风停了，天色渐暗。", "没有那个字。", "又起风了，吹过山岗。"]
    return ReaderBookSearchView(
        session: session,
        historyKey: "preview_reader_search_history",
        initialQuery: "风",
        offersReplaceRules: false,
        onSearch: { query in
            session.search(
                query,
                chapterTitles: ["第一章", "第二章", "第三章"],
                signature: .init(source: ReaderAISourceIdentity(bookID: UUID(), sourceID: nil, source: "preview", chapters: []),
                                 conversion: .original, rulesRevision: 0)
            ) { index, _ in .init(text: chapters[index], status: .available) }
        },
        onReopen: {},
        onSelect: { _ in },
        onClose: {}
    )
}
