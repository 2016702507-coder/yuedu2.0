import SwiftUI

struct SearchView: View {
    var initialQuery: String = ""
    var sessionScope: SearchSourceScope?
    /// The 搜索 tab's own root, which carries a tab root's title.
    var isTabRoot = false

    var body: some View {
        BookSearchView(initialQuery: initialQuery, sessionScope: sessionScope, isTabRoot: isTabRoot)
    }
}

/// The 搜索 tab's stack, for the pages on it that push by value: 作品详情 and 青空文库's full
/// list. One path for every page past the root, so back pops one page (postmortem guardrail
/// 11: an item-based push under a bound path lost its place, and back from 作品详情 on
/// Gutenberg's results returned to the root). A reference that never changes, so the search
/// page can hold it without its body depending on the path (guardrail 13).
@MainActor @Observable
final class SearchTabNavigation {
    var path = NavigationPath()
}

extension EnvironmentValues {
    /// The 搜索 tab's stack; nil anywhere else.
    @Entry var searchTabNavigation: SearchTabNavigation?
}

/// The 搜索 tab: its stack, with the store's pages for the public libraries it searches
/// (unified library 5d-1b, Phase 5 plan decision 17). A public-library book opens 作品详情, as
/// on 探索; the card carousel is off here too (decision 27, extended to 搜索 after 5f-2).
struct SearchTabRoot: View {
    @State private var navigation = SearchTabNavigation()

    var body: some View {
        @Bindable var navigation = navigation
        NavigationStack(path: $navigation.path) {
            SearchView(isTabRoot: true)
                .remoteLibraryDestinations()
                .publicLibraryDestinations()
                // 搜索页下半页的来源配置目录用 资源库 的路由（所有来源 / 某个分组）。
                // 少了这一行，卡片点下去没有目的地。
                .exploreRouteDestinations(openBrowser: { _ in })
        }
        .environment(\.searchTabNavigation, navigation)
        .environment(\.openPublicLibraryBooks) { [navigation] selection in
            if let book = selection.selectedBook { navigation.path.append(WorkDetailRoute(book)) }
        }
    }
}

#Preview("搜索 tab") {
    SearchTabRoot()
        .environmentObject(BookStore())
}
