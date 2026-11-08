import Foundation

/// The official modules that are the app's own code, not module files: AI 推荐 (AI 推荐 plan 8c),
/// then 古腾堡 and 青空文库 (M2b, maintainer 2026-10-17: 「公有书库都算是官方模块」) where the
/// storefront offers them (`LibraryKeys.available`). 资源库's 模组 and 模组 → 官方模组 both list them
/// from here, in this order, before the bundled module files (`RuleModuleLibrary.official`): until
/// 2026-10-27 官方模组 listed the files alone, and the maintainer found all three missing.
enum AppOfficialModule: Hashable, Identifiable {
    case aiRecommendations
    case library(SourceInstanceKey)

    static func available(librariesAvailable: Bool) -> [AppOfficialModule] {
        [.aiRecommendations]
            + LibraryKeys.available(connections: [], librariesAvailable: librariesAvailable).map { .library($0) }
    }

    var id: String {
        switch self {
        case .aiRecommendations: "aiRecommendations"
        case .library(let key): key.id
        }
    }

    var title: String {
        switch self {
        case .aiRecommendations: localized("AI 推荐")
        case .library(let key): key.type == .aozora ? localized("青空文库") : localized("Project Gutenberg")
        }
    }

    /// What it is, in a line: AI 推荐's purpose, a library's site.
    var summary: String {
        switch self {
        case .aiRecommendations: localized("依你最近读的书推荐作品")
        case .library(let key): key.type == .aozora ? "aozora.gr.jp" : "gutenberg.org"
        }
    }

    /// Its page: what it gives 首页 and 搜索, and the sites it reaches.
    var route: ExploreNavigationRoute {
        switch self {
        case .aiRecommendations: .aiRecommendations
        case .library(let key): .library(key)
        }
    }
}
