import SwiftUI

// 大图卡片 is a 分类卡 (maintainer, 2026-10-27: 「大图卡片应该是分类或宣传用的…可以拿来当分类卡」,
// 「我们肯定要根据分类作默认的图片设计」): a card per list, its face designed from the list's name
// as Apple Books' More to Explore draws Romance — a drawing for the kind of book on a ground —
// with no covers. A name that says no kind gets a book on a ground the name picks, so a card
// looks the same every time it is drawn.

/// What a list's designed face draws: the symbol for the kind of book its name says, and the
/// ground (`DSColor.categoryArtPalette`) it stands on.
struct HomeCategoryFace: Equatable {
    let symbol: String
    let palette: Int

    init(name: String) {
        let lowered = name.lowercased()
        // Latin keywords are whole words ("war" is not in "software"); the others are found
        // anywhere in the name, which has no spaces to split on.
        let words = Set(lowered.split { !$0.isLetter && $0 != "-" && $0 != "'" }.map(String.init))
        let kind = Self.kinds.first { kind in
            kind.keywords.contains { keyword in
                keyword.allSatisfy(\.isASCII)
                    ? (keyword.contains(" ") ? lowered.contains(keyword) : words.contains(keyword))
                    : lowered.contains(keyword)
            }
        }
        if let kind {
            symbol = kind.symbol
            palette = kind.palette
        } else {
            symbol = "book.closed.fill"
            // A sum of the name's scalars: the same across launches, as `hashValue` is not.
            palette = name.unicodeScalars.reduce(0) { $0 &+ Int($1.value) } % DSColor.categoryArtPalette.count
        }
    }

    /// Kinds of book by the words their names use in the app's five languages, the more
    /// particular first (玄幻 before a bare 幻 would be). Palette: 0 rose, 1 coral, 2 plum,
    /// 3 indigo, 4 slate, 5 teal, 6 forest, 7 amber.
    private static let kinds: [(keywords: [String], symbol: String, palette: Int)] = [
        (["耽美", "百合", "ボーイズラブ", "boys' love"], "heart.circle.fill", 2),
        (["言情", "爱情", "爱情", "恋爱", "恋爱", "恋爱", "纯爱", "纯爱", "romance", "ロマンス", "로맨스", "연애"], "heart.fill", 0),
        (["轻小说", "轻小说", "ライトノベル", "ラノベ", "light novel", "light novels", "라노벨"], "sparkles", 0),
        (["漫画", "漫画", "comic", "comics", "manga", "マンガ", "まんが", "만화", "웹툰", "webtoon"],
         "bubble.left.and.bubble.right.fill", 1),
        (["科幻", "sci-fi", "science fiction", "星际", "星际", "末世", "ＳＦ", "공상과학"], "atom", 3),
        (["玄幻", "奇幻", "魔幻", "魔法", "异世界", "异世界", "fantasy", "ファンタジー", "판타지"], "wand.and.stars", 2),
        (["仙侠", "仙侠", "修真", "修仙", "洪荒", "神话", "神话", "mythology"], "mountain.2.fill", 5),
        (["武侠", "武侠", "功夫", "martial", "무협"], "figure.martial.arts", 1),
        (["悬疑", "悬疑", "推理", "侦探", "侦探", "探侦", "mystery", "mysteries", "detective", "crime", "ミステリ",
          "ミステリー", "미스터리", "추리"], "magnifyingglass", 4),
        (["恐怖", "惊悚", "惊悚", "灵异", "灵异", "怪谈", "怪谈", "horror", "thriller", "thrillers", "ホラー", "호러", "공포"],
         "moon.stars.fill", 3),
        (["历史", "历史", "歴史", "时代", "时代", "history", "historical", "역사"], "building.columns.fill", 7),
        (["军事", "军事", "战争", "战争", "military", "war", "戦记", "전쟁"], "shield.fill", 4),
        (["游戏", "游戏", "电竞", "电竞", "网游", "网游", "竞技", "竞技", "game", "games", "gaming", "ゲーム", "게임"],
         "gamecontroller.fill", 5),
        (["体育", "体育", "运动", "运动", "sport", "sports", "スポーツ", "스포츠"], "figure.run", 6),
        (["校园", "校园", "青春", "学园", "学园", "学园", "school", "campus", "학원"], "graduationcap.fill", 4),
        (["都市", "现代", "现代", "现实", "现实", "职场", "职场", "urban", "contemporary", "현대"], "building.2.fill", 4),
        (["诗", "诗", "poetry", "poems", "poem", "시집"], "quote.opening", 3),
        (["儿童", "儿童", "童话", "童话", "童书", "童书", "絵本", "children", "kids", "juvenile", "동화"], "teddybear.fill", 7),
        (["美食", "料理", "グルメ", "cooking", "food", "요리"], "fork.knife", 7),
        (["旅行", "旅游", "旅游", "游记", "游记", "travel", "여행"], "airplane", 4),
        (["科学", "科学", "科普", "science", "과학"], "flask.fill", 5),
        (["哲学", "哲学", "思想", "philosophy", "철학"], "brain.head.profile", 2),
        (["经济", "经济", "商业", "商业", "财经", "财经", "经管", "经管", "business", "economics", "ビジネス", "경제"],
         "chart.line.uptrend.xyaxis", 6),
        (["音乐", "音乐", "music", "음악"], "music.note", 0),
        (["艺术", "艺术", "设计", "设计", "art", "arts", "design", "アート", "예술"], "paintpalette.fill", 1),
        (["戏剧", "戏剧", "剧本", "剧本", "演剧", "drama", "plays", "희곡"], "theatermasks.fill", 1),
        (["冒险", "冒险", "探险", "探险", "adventure", "adventures", "모험"], "map.fill", 5),
        (["自然", "园艺", "园艺", "植物", "nature", "gardening", "자연"], "leaf.fill", 6),
        (["动物", "动物", "宠物", "宠物", "animals", "pets", "동물"], "pawprint.fill", 7),
        (["排行", "榜", "人气", "人气", "人気", "热门", "热门", "ranking", "rankings", "popular", "trending", "top", "ランキング",
          "인기"], "trophy.fill", 7),
        (["完结", "完结", "完本", "completed", "finished", "완결"], "checkmark.seal.fill", 6),
        (["新书", "新书", "最新", "新作", "新刊", "新着", "new", "신간"], "sparkles", 1),
        (["经典", "经典", "名著", "古典", "文学", "文学", "classic", "classics", "literature", "고전"], "scroll.fill", 7),
    ]
}

/// A list's designed face: its ground, and its drawing large at the trailing side, where
/// Romance's heart is, turned a little. Decoration: VoiceOver reads the card's name, not this.
/// In a loading row, the skeleton's grey.
struct HomeCategoryArt: View {
    let name: String

    @Environment(\.redactionReasons) private var redactionReasons

    var body: some View {
        let face = HomeCategoryFace(name: name)
        let palette = DSColor.categoryArtPalette[face.palette]
        if redactionReasons.contains(.placeholder) {
            DSColor.neutralControlFill
        } else {
            palette.ground
                .overlay {
                    GeometryReader { proxy in
                        let side = proxy.size.height * DSLayout.homeCategoryArtGlyphShare
                        let center = DSLayout.homeCategoryArtCenter
                        Image(systemName: face.symbol)
                            .resizable()
                            .scaledToFit()
                            .foregroundStyle(palette.art)
                            .frame(width: side, height: side)
                            .rotationEffect(.degrees(DSLayout.homeCategoryArtRotation))
                            .position(x: proxy.size.width * center.x, y: proxy.size.height * center.y)
                    }
                }
                .accessibilityHidden(true)
        }
    }
}

#if DEBUG
#Preview("分类卡的预设图") {
    ScrollView {
        VStack(spacing: DSSpacing.lg) {
            ForEach(["玄幻", "言情", "悬疑推理", "科幻", "历史", "Romance", "ミステリー", "本周精选"], id: \.self) { name in
                HomeCategoryArt(name: name)
                    .aspectRatio(DSLayout.homeBannerAspect, contentMode: .fit)
                    .overlay(alignment: .bottomLeading) {
                        Text(name)
                            .font(DSFont.largeTitle.weight(.semibold))
                            .foregroundStyle(DSColor.textOnFixedFill)
                            .padding(.leading, DSSpacing.xxl)
                            .padding(.bottom, DSSpacing.xl)
                    }
                    .clipShape(RoundedRectangle(cornerRadius: DSRadius.xxl, style: .continuous))
            }
        }
        .padding(DSSpacing.lg)
    }
}
#endif
