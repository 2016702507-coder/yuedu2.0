import Foundation

/// What the tour says, worked out from the app in front of the reader: a tab they hid is not
/// walked through or offered as a start, a storefront without the public libraries is not
/// promised them, a home made without rankings is not said to have them, and a 阅读Pro feature
/// they do not have yet says so.
struct OnboardingContent: Equatable {
    /// A line of a page's list: a feature, by the name it has in the app, and its sentence.
    struct Row: Equatable, Identifiable {
        let titleKey: String
        let textKey: String
        /// A 阅读Pro feature this reader does not have yet: the title carries the Pro lock.
        var isLocked = false

        var id: String { titleKey + textKey }
    }

    /// A page's sentence under its title, where it depends on the reader, and its list.
    struct Copy: Equatable {
        let textKey: String
        let rows: [Row]
    }

    /// 从探索找书; nil while 探索 is hidden, and the page is then left out.
    let explore: Copy?
    /// 一部作品，一个页面.
    let works: [Row]
    /// 连接你的所有资源.
    let sources: Copy
    /// 长时间阅读也舒服: how the reader reads, then the looks the reader makes their own.
    let reading: [Row]
    /// 选一个起点: the starts whose tab is shown.
    let starts: [OnboardingStart]

    /// The pages shown: 从探索找书 only while 探索 is, 选一个起点 only while it has a start.
    var pages: [OnboardingPage] {
        OnboardingPage.allCases.filter { page in
            switch page {
            case .explore: return explore != nil
            case .start: return !starts.isEmpty
            case .welcome, .works, .sources, .reading: return true
            }
        }
    }

    /// - Parameters:
    ///   - visibleTabs: The tabs the reader shows.
    ///   - librariesAvailable: Whether the storefront is known and offers the public libraries.
    ///   - languages: 中继资料语言偏好推荐's languages, which choose a new home's rankings.
    ///   - lockedFeatures: The 阅读Pro features the reader does not have.
    init(visibleTabs: [RootTabItem], librariesAvailable: Bool, languages: [String],
         lockedFeatures: Set<PremiumFeature>) {
        if visibleTabs.contains(.explore) {
            // The rankings a new home is made with (`HomePageDefaults`): none yet for Korean, nor
            // for Japanese where なろう is hidden.
            let hasRankings = !HomePageDefaults.officialModuleLists(
                languages: languages, publicLibrariesAvailable: librariesAvailable
            ).isEmpty
            explore = Copy(
                textKey: hasRankings
                    ? "打开探索，就有依你的语言排好的排行。各处的书排在同一页，不分本机或线上。"
                    : "探索是你的首页，各处的书排在同一页，不分本机或线上。",
                rows: [
                    Row(titleKey: "最新", textKey: "你连接的书库一有新书，就会出现在这里"),
                    Row(titleKey: "编辑首页", textKey: "在右上角的选单里排栏目和呈现方式，还能存成好几套首页配置"),
                ]
            )
        } else {
            explore = nil
        }

        var works: [Row] = []
        // A tab of its own, which the reader can hide.
        if visibleTabs.contains(.search) {
            works.append(Row(titleKey: RootTabItem.search.titleKey, textKey: "输入书名或作者，各处的结果依作品合并成一份清单"))
        }
        works += [
            Row(titleKey: "作品详情", textKey: "同一部作品在各处的版本列在一起，用「换源」挑要读哪一个"),
            Row(titleKey: "自动补齐书籍资料", textKey: "你的书缺封面、简介或分类，会在 Wi-Fi 下自动补上"),
            Row(titleKey: "聚合设置", textKey: "要搜寻哪些地方、先用哪里的资料，都能自己选"),
        ]
        self.works = works

        sources = Copy(
            textKey: visibleTabs.contains(.library)
                ? "来源配置、模组和远端书库都在资源库，加进来就跟内建的一起用。"
                : "加进来的来源配置、模组和远端书库，跟内建的一起用。",
            rows: [
                Row(titleKey: "来源配置", textKey: "汇入或手动新增，搜寻和换源就会用上，它的分类也能加进首页"),
                Row(titleKey: "模组", textKey: librariesAvailable
                    ? "內建 Project Gutenberg、青空文庫、Open Library、小説家になろう、Bangumi、AniList 等官方模組，也能自己加入更多"
                    : "内建 Open Library、Bangumi、AniList、openBD 等官方模组，也能自己加入更多"),
                Row(titleKey: "远端书库", textKey: "连接 WebDAV、OPDS 或 Calibre，新书会出现在首页的最新"),
                Row(titleKey: "本机档案", textKey: "TXT、EPUB、PDF、漫画和有声书，也能用电脑传书从 Calibre 传过来"),
                Row(titleKey: "iCloud 同步", textKey: "书籍、阅读进度、来源配置和阅读设置，在你的装置之间同步"),
            ]
        )

        reading = [
            Row(titleKey: "划线与书签", textKey: "选取文字就能划线，重要的页面加上书签"),
            Row(titleKey: "听书", textKey: "把书念给你听"),
            Row(titleKey: "自动阅读", textKey: "自动往下读，速度和翻页方式都能调"),
            // By the names their rows have in 设置.
            Row(titleKey: "外观主题", textKey: "在设置里自己调 App 与阅读的配色，还有每一页的背景",
                isLocked: lockedFeatures.contains(.readerThemePacks)),
            Row(titleKey: "底部 Tab", textKey: "在外观主题里选要显示哪些分页，还有大小和图示",
                isLocked: lockedFeatures.contains(.bottomBarCustomization)),
        ]

        starts = OnboardingStart.allCases.filter { visibleTabs.contains($0.tab) }
    }
}
