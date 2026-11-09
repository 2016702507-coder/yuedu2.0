import Combine
import SwiftUI

/// 封面搜索 — covers found on the web, independent of the installed book sources.
///
/// Legado's equivalent (封面规则) returns a single cover and drops it into the
/// change-cover grid; `OnlineCoverSearchService` queries the same two sites and
/// keeps every distinct match so this screen can offer a choice.
@MainActor
final class OnlineCoverSearchViewModel: ObservableObject {
    @Published private(set) var candidates: [CoverCandidate] = []
    @Published private(set) var isSearching = false
    @Published private(set) var hasSearched = false

    private var searchTask: Task<Void, Never>?

    func start(title: String, author: String) {
        guard !isSearching else { return }
        candidates = []
        hasSearched = true
        isSearching = true
        searchTask?.cancel()
        searchTask = Task { [weak self] in
            let found = await OnlineCoverSearchService.searchCovers(name: title, author: author)
            guard let self, !Task.isCancelled else { return }
            self.candidates = found.map { result in
                CoverCandidate(
                    coverUrl: result.coverUrl,
                    // No book source behind a web cover: it downloads with the
                    // default browser headers.
                    sourceId: nil,
                    providerName: result.providerName
                )
            }
            self.isSearching = false
        }
    }

    func stop() {
        searchTask?.cancel()
        searchTask = nil
        isSearching = false
    }
}

/// The 封面搜索 screen. Picking a cover hands it back to 书籍资讯.
struct OnlineCoverSearchView: View {
    let title: String
    let author: String
    let onSelect: (CoverCandidate) -> Void
    /// 从相簿/档案导入的图片数据。调用方持有该书的 id 与 store，由它落盘并提示；
    /// 这一页不引入 EnvironmentObject，避免调用链上漏注入时崩溃。
    /// 不传就不显示「导入封面」按钮。
    var onImportImage: ((Data) -> Void)? = nil

    @StateObject private var model = OnlineCoverSearchViewModel()
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        AdaptiveSheetContainer(maxWidth: DSLayout.readableListWidth) {
            CoverCandidateGrid(
                bookTitle: title,
                candidates: model.candidates,
                isSearching: model.isSearching,
                hasSearched: model.hasSearched,
                emptyHint: localized("可以改用「换封面」在来源配置里找，或从相簿选一张图片。"),
                onSelect: { candidate in
                    model.stop()
                    onSelect(candidate)
                    dismiss()
                },
                onImportImage: onImportImage
            )
        }
        .navigationTitle(localized("封面搜索"))
        .toolbarTitleDisplayMode(.inline)
        .themedAppSurface(for: .bookshelf)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button {
                    if model.isSearching {
                        model.stop()
                    } else {
                        model.start(title: title, author: author)
                    }
                } label: {
                    Image(systemName: model.isSearching ? "stop.circle" : "arrow.clockwise")
                }
                .accessibilityLabel(
                    model.isSearching ? localized("停止搜索") : localized("重新搜寻")
                )
            }
        }
        .onAppear { model.start(title: title, author: author) }
        .onDisappear { model.stop() }
    }
}

#Preview {
    NavigationStack {
        OnlineCoverSearchView(
            title: "红楼梦",
            author: "曹雪芹",
            onSelect: { _ in }
        )
    }
}
