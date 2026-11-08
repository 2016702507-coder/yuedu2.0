import Foundation

// Unified library 5d-5: 选择内容来源 (design §13.3, Rex's 「选择内容来源」; Phase 5 plan,
// decision 23). What a section can show, grouped by who serves it:
// - App 资料: 继续阅读, 最新 and 相关, which gather across sources (decision 23),
//   订阅的最新文章, the RSS subscriptions' articles (5g, decision 26), and 书架, the shelf's
//   books (feedback #24);
// - 书库: each OPDS or Calibre connection's feeds, Gutenberg's lists and feeds, 青空文库's
//   新着 and indexes. A WebDAV connection serves 最新 only, so it is not listed;
// - 来源配置: each book source's discover categories;
// - 模组: each installed module's lists (Phase 6f).
// 外部服务 waits for Phase 3 (decision 23). 最近加入书架, a 书架分组 and 阅读统计 have no binding.

/// Who serves a binding, as 选择内容来源 groups it and marks the current one 「目前」.
enum HomeContentOwner: Hashable, Sendable {
    case appData
    case connection(id: String)
    case gutenberg
    case aozora
    case bookSource(url: String)
    /// An installed module (Phase 6f).
    case module(id: String)
    /// The app's own modules: AI 推荐 (AI 推荐 plan 8c).
    case official
}

extension HomeSectionBinding {
    /// Nil for 我的书库 and a later build's binding, which the form does not offer.
    var contentOwner: HomeContentOwner? {
        switch self {
        case .continueReading, .bookshelf, .latest, .related, .nextInSeries, .subscriptionArticles: .appData
        case .opdsFeed(let connectionID, _): .connection(id: connectionID)
        case .gutenbergCollection, .gutenbergLists, .gutenbergFeed, .gutenbergShelf: .gutenberg
        case .aozoraNew, .aozoraIndex: .aozora
        case .sourceCategories(let references): references.first.map { .bookSource(url: $0.sourceURL) }
        case .module(let moduleID, _): .module(id: moduleID)
        case .aiRecommendations: .official
        // A section of lists from one source is that source's; from several, no one's.
        case .lists(let cards):
            Set(cards.map(\.binding.contentOwner)).count == 1 ? cards.first?.binding.contentOwner : nil
        case .myLibrary, .unknown: nil
        }
    }

    /// App 资料's choices, in the order they are listed.
    static let appData: [HomeSectionBinding] = [.continueReading, .bookshelf, .nextInSeries, .latest, .related,
                                                .subscriptionArticles]

    /// 官方模组's choices.
    static let official: [HomeSectionBinding] = [.aiRecommendations]

    /// 青空文库's choices: 新着, then each index.
    static let aozora: [HomeSectionBinding] = [.aozoraNew] + ["authors", "titles", "categories"].map { .aozoraIndex(kind: $0) }

    /// Gutenberg's bundled lists, which send no request: 精选书单, all of them as cards, then each
    /// list as a section of its own.
    static var gutenbergCollections: [HomeSectionBinding] {
        [.gutenbergLists] + PublicLibraryCollection.all.map { .gutenbergCollection(id: $0.id) }
    }

    /// What the 顶部轮播图 can show (maintainer, 2026-10-27): books, for its band of covers. Not
    /// lists, articles, or 青空文库's indexes, which are places to go.
    var showsBooks: Bool {
        switch self {
        case .gutenbergLists, .lists, .subscriptionArticles, .aozoraIndex: false
        default: true
        }
    }
}

extension HomeSection {
    /// `self` showing `binding`: the parameters of the binding it showed go with it. The title
    /// the reader gave stays.
    func showing(_ binding: HomeSectionBinding, parameters: [String: String]) -> HomeSection {
        var section = self
        section.binding = binding
        section.parameters = parameters
        return section
    }
}
