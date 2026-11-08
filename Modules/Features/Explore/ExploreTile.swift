import SwiftUI

// MARK: - 资源库 cards

// 资源库's entries (Phase 5 plan, 5h). The old 探索 root's 格状 and 列表 choice, restored from
// before 5d-1b; each entry is a card as the maintainer's reference draws its media servers and
// modules (2026-10-13): a small square picture top leading, a count or a time top trailing,
// then the name, a line about it and a line of detail. A source has no picture of its own, so
// every source shows the same symbol, as the reference's modules do.

/// What a card shows in its square.
enum ExploreArtwork: Equatable {
    /// A library's or a page's symbol, in the theme's tint.
    case symbol(String)
    /// A symbol on grey, the same for every entry of its kind: a source, a group of sources.
    case neutral(String)

    /// Every source's picture (maintainer, 2026-10-13: one symbol for a source without one).
    static let source = ExploreArtwork.neutral("square.grid.2x2.fill")
}

/// How many cards share a row of the grid. Narrower cards drop their lower lines.
enum ExploreGridDensity: Int, CaseIterable, Identifiable, Comparable {
    case two = 2
    case three = 3
    case four = 4

    static let `default` = ExploreGridDensity.two

    var id: Int { rawValue }

    static func < (lhs: Self, rhs: Self) -> Bool { lhs.rawValue < rhs.rawValue }

    /// The density the reader chose, a column narrower as the text grows so a name
    /// still fits its card. Accessibility sizes don't use the grid at all.
    static func fitting(_ chosen: Int, dynamicTypeSize: DynamicTypeSize) -> ExploreGridDensity {
        let density = ExploreGridDensity(rawValue: chosen) ?? .default
        switch dynamicTypeSize {
        case .xLarge: return min(density, .three)
        case .xxLarge, .xxxLarge: return .two
        default: return density
        }
    }

    /// The lines under the name a card this wide has room for.
    var lineCount: Int {
        switch self {
        case .two: 2
        case .three: 1
        case .four: 0
        }
    }

    var padding: CGFloat { self == .four ? DSSpacing.sm : DSSpacing.md }
}

/// One entry, a card in the grid or a card across the page in the list.
struct ExploreEntryLabel: View {
    enum Layout: Equatable {
        case grid(ExploreGridDensity)
        case list
    }

    /// The card's top trailing corner.
    enum Corner: Equatable {
        /// A count in a small pill: RSS 订阅's unread articles, a group's sources.
        case count(Int)
    }

    let title: String
    /// The card's square. `nil` draws a card with no picture at all — just the name, its
    /// count and its surface (the 搜索 tab's source directory, whose cards read as glass).
    let artwork: ExploreArtwork?
    let layout: Layout
    var subtitle: String?
    var detail: String?
    var corner: Corner?
    /// Drawn in 资源库's paper look rather than the app's cards: 宋体-adjacent colours, a warm
    /// symbol tile and a sheet-like surface. 探索 and the rest keep the default.
    var paper: Bool = false
    /// Unconditional glass, the same pane 设置's rows are made of. `paper` wins where both are
    /// set; the 分组卡片 switch still decides for cards that ask for neither.
    var glass: Bool = false

    init(title: String, artwork: ExploreArtwork?, layout: Layout,
         subtitle: String? = nil, detail: String? = nil, corner: Corner? = nil,
         paper: Bool = false, glass: Bool = false) {
        self.title = title
        self.artwork = artwork
        self.layout = layout
        self.subtitle = subtitle
        self.detail = detail
        self.corner = corner
        self.paper = paper
        self.glass = glass
    }

    /// A source's entry: its groups, and the site it reads.
    init(source: BookSource, layout: Layout, paper: Bool = false) {
        let groups = DiscoverViewModel.groupNames(of: source)
        self.init(title: source.bookSourceName, artwork: .source, layout: layout,
                  subtitle: groups.isEmpty ? nil : groups.joined(separator: localized("、")),
                  detail: URL(string: source.bookSourceUrl)?.host(),
                  paper: paper)
    }

    /// How many lines under the name: what the card has room for in the grid, where every card
    /// of a row keeps them so the row lines up; only the lines it has in the list.
    private var lineCount: Int? {
        switch layout {
        case .grid(let density): density.lineCount
        case .list: nil
        }
    }

    private var padding: CGFloat {
        switch layout {
        case .grid(let density): density.padding
        case .list: DSSpacing.md
        }
    }

    @ScaledMetric(relativeTo: .headline) private var artworkSide = DSLayout.exploreCardArtworkSide
    @ScaledMetric(relativeTo: .headline) private var artworkSize = DSLayout.exploreCardArtworkSize
    @Environment(\.colorScheme) private var scheme

    private var titleColor: Color {
        paper ? PaperPalette.textPrimary(scheme) : DSColor.textPrimary
    }

    private var subtitleColor: Color {
        paper ? PaperPalette.textSecondary(scheme) : DSColor.textSecondary
    }

    private var detailColor: Color {
        paper ? PaperPalette.textTertiary(scheme) : DSColor.textTertiary
    }

    var body: some View {
        VStack(alignment: .leading, spacing: DSSpacing.xxs) {
            if let artwork {
                HStack(alignment: .top, spacing: DSSpacing.sm) {
                    ExploreArtworkView(artwork: artwork, side: artworkSide, size: artworkSize, paper: paper)
                    Spacer(minLength: 0)
                    if let corner {
                        // Ahead of the spacer, which would otherwise split the width with it: in
                        // four columns a count of three digits then broke a digit to a line and
                        // stood its card taller than the row (maintainer, 2026-10-17).
                        ExploreEntryCorner(corner: corner, paper: paper, glass: glass)
                            .layoutPriority(1)
                    }
                }
                .padding(.bottom, DSSpacing.sm)
                titleText
            } else {
                // No picture: the name and its count share the top line, so the card stays as
                // short as its content and the grid rows still line up.
                HStack(alignment: .firstTextBaseline, spacing: DSSpacing.xs) {
                    titleText
                    Spacer(minLength: 0)
                    if let corner {
                        ExploreEntryCorner(corner: corner, paper: paper, glass: glass)
                            .layoutPriority(1)
                    }
                }
            }
            line(subtitle, at: 1, font: paper ? .system(size: 12) : DSFont.subheadline, color: subtitleColor)
            line(detail, at: 2, font: paper ? .system(size: 11) : DSFont.caption, color: detailColor)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(padding)
        .modifier(ExploreEntrySurface(paper: paper, glass: glass, shape: exploreEntryShape))
        .contentShape(exploreEntryShape)
        .contentShape(.contextMenuPreview, exploreEntryShape)
    }

    private var titleText: some View {
        Text(title)
            .font(paper ? .system(size: 15, weight: .semibold) : DSFont.headline)
            .foregroundStyle(titleColor)
            .lineLimit(1)
    }

    /// A line under the name. In the grid an empty one keeps its height, so the cards of a row
    /// end together.
    @ViewBuilder
    private func line(_ text: String?, at index: Int, font: Font, color: Color) -> some View {
        if artwork == nil {
            // A card without a picture has nothing to balance against, so an empty line would
            // only stand it taller than its content.
            if let text {
                Text(text)
                    .font(font)
                    .foregroundStyle(color)
                    .lineLimit(1)
            }
        } else if let lineCount {
            if index <= lineCount {
                Text(text ?? " ")
                    .font(font)
                    .foregroundStyle(color)
                    .lineLimit(1)
                    .accessibilityHidden(text == nil)
            }
        } else if let text {
            Text(text)
                .font(font)
                .foregroundStyle(color)
                .lineLimit(1)
        }
    }
}

private var exploreEntryShape: RoundedRectangle {
    RoundedRectangle(cornerRadius: DSRadius.xl, style: .continuous)
}

/// The card's ground: 资源库's paper sheet, the app's themed card elsewhere, or an
/// unconditional pane of glass.
private struct ExploreEntrySurface: ViewModifier {
    let paper: Bool
    let glass: Bool
    let shape: RoundedRectangle

    @Environment(\.colorScheme) private var scheme

    @ViewBuilder
    func body(content: Content) -> some View {
        if paper {
            content.paperCard(radius: 22)
        } else if glass {
            content
                .floatingSurfaceBackground(in: shape)
                // The lit edge that makes a pane read as glass rather than a washed-out fill.
                .overlay(
                    shape.strokeBorder(
                        .white.opacity(scheme == .dark ? 0.14 : 0.5),
                        lineWidth: 0.8
                    )
                )
                .shadow(color: DSColor.shadow, radius: DSLayout.exploreCardShadowRadius,
                        y: DSLayout.exploreCardShadowY)
        } else {
            content
                .interfaceCardSurface(in: shape)
                .shadow(color: DSColor.shadow, radius: DSLayout.exploreCardShadowRadius,
                        y: DSLayout.exploreCardShadowY)
        }
    }
}

// MARK: - Corner

/// A card's count or time. The entry's link says it to VoiceOver as its value, so it is hidden.
private struct ExploreEntryCorner: View {
    let corner: ExploreEntryLabel.Corner
    var paper: Bool = false
    /// On a glass card the bubble is glass too: a pane a shade lighter than the card, with the
    /// same lit edge. A tinted pill read as a sticker on top of the glass (maintainer, 2026-11-05).
    var glass: Bool = false
    @Environment(\.colorScheme) private var scheme

    private var shape: RoundedRectangle {
        RoundedRectangle(cornerRadius: DSRadius.sm, style: .continuous)
    }

    var body: some View {
        switch corner {
        case .count(let count):
            Text(count, format: .number)
                .font((paper || glass
                       ? Font.system(size: 11, weight: .medium)
                       : DSFont.caption.weight(.semibold)))
                .monospacedDigit()
                .lineLimit(1)
                .foregroundStyle(paper ? PaperPalette.textSecondary(scheme) : DSColor.textSecondary)
                .padding(.horizontal, DSSpacing.xs)
                .padding(.vertical, DSSpacing.xxs)
                .background(bubbleFill, in: shape)
                .overlay {
                    if glass {
                        shape.strokeBorder(
                            .white.opacity(scheme == .dark ? 0.16 : 0.9),
                            lineWidth: 0.8
                        )
                    }
                }
                .overlay {
                    if glass {
                        shape.strokeBorder(DSColor.separator.opacity(0.45), lineWidth: 0.5)
                    }
                }
                .accessibilityHidden(true)
        }
    }

    private var bubbleFill: Color {
        if paper { return PaperPalette.iconTile(scheme) }
        if glass { return .white.opacity(scheme == .dark ? 0.10 : 0.58) }
        return DSColor.neutralControlFill
    }
}

// MARK: - Artwork

/// The card's square: a library's symbol in the theme's tint on a tinted ground, or a
/// source's in the text colour on grey.
private struct ExploreArtworkView: View {
    let artwork: ExploreArtwork
    let side: CGFloat
    let size: CGFloat
    var paper: Bool = false
    @Environment(\.colorScheme) private var scheme

    private var shape: RoundedRectangle {
        RoundedRectangle(cornerRadius: DSRadius.md, style: .continuous)
    }

    var body: some View {
        Group {
            switch artwork {
            case .symbol(let name):
                if paper {
                    symbol(name)
                        .foregroundStyle(PaperPalette.ink(scheme))
                        .background(PaperPalette.iconTile(scheme), in: shape)
                } else {
                    symbol(name)
                        .foregroundStyle(.tint)
                        .background(DSColor.accentLight, in: shape)
                }
            case .neutral(let name):
                if paper {
                    symbol(name)
                        .foregroundStyle(PaperPalette.ink(scheme))
                        .background(PaperPalette.iconTile(scheme), in: shape)
                } else {
                    symbol(name)
                        .foregroundStyle(DSColor.textPrimary)
                        .background(DSColor.neutralControlFill, in: shape)
                }
            }
        }
        .accessibilityHidden(true)
    }

    private func symbol(_ name: String) -> some View {
        Image(systemName: name)
            .font(DSFont.fixed(size: size, weight: .semibold))
            .frame(width: side, height: side)
    }
}

#Preview("资源库 grid") {
    ScrollView {
        ForEach(ExploreGridDensity.allCases) { density in
            LazyVGrid(
                columns: Array(repeating: GridItem(.flexible(), spacing: DSSpacing.md), count: density.rawValue),
                spacing: DSSpacing.md
            ) {
                ExploreEntryLabel(title: "Project Gutenberg", artwork: .symbol("building.columns"), layout: .grid(density),
                                  subtitle: "gutenberg.org")
                ExploreEntryLabel(title: "RSS 订阅", artwork: .symbol("newspaper"), layout: .grid(density),
                                  subtitle: "12 个订阅源", corner: .count(8))
                ExploreEntryLabel(title: "📚书山聚合", artwork: .source, layout: .grid(density),
                                  subtitle: "男频、精品", detail: "shushan.example")
                ExploreEntryLabel(title: "男频", artwork: .neutral("folder.fill"), layout: .grid(density), corner: .count(42))
            }
            .padding()
        }
    }
    .background(DSColor.groupedBackground)
}

#Preview("资源库 list") {
    ScrollView {
        LazyVStack(spacing: DSSpacing.md) {
            ExploreEntryLabel(title: "RSS 订阅", artwork: .symbol("newspaper"), layout: .list,
                              subtitle: "12 个订阅源", corner: .count(8))
            ExploreEntryLabel(title: "📚书山聚合", artwork: .source, layout: .list,
                              subtitle: "男频、精品", detail: "shushan.example")
            ExploreEntryLabel(title: "番茄小说", artwork: .source, layout: .list)
        }
        .padding()
    }
    .background(DSColor.groupedBackground)
}
