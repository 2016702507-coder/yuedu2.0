import SwiftUI
import AVFoundation
import Combine

// MARK: - 段评语音播放器

/// 段评里语音评论的播放器（单例）。
///
/// 全 App 共用一个 `AVPlayer`，保证**同时只放一段语音**：
/// 点正在播放的那条 → 暂停；点另一条 → 自动接管。
/// 之前语音按钮直接 `openURL`，只把链接丢给外部浏览器，所以「配音听不了」。
@MainActor
final class ReviewVoicePlayer: NSObject, ObservableObject {
    static let shared = ReviewVoicePlayer()

    @Published private(set) var playingURL: URL?
    @Published private(set) var isPlaying = false

    private var player: AVPlayer?
    private var item: AVPlayerItem?

    private override init() {
        super.init()
    }

    /// 点同一条切换播放/暂停，点另一条接管播放。
    func toggle(_ url: URL) {
        if isPlaying, playingURL == url {
            stop()
        } else {
            play(url)
        }
    }

    func play(_ url: URL) {
        if playingURL != url || item == nil {
            stop()
            let newItem = AVPlayerItem(url: url)
            item = newItem
            player = AVPlayer(playerItem: newItem)
            playingURL = url
            NotificationCenter.default.addObserver(
                self,
                selector: #selector(didEnd(_:)),
                name: .AVPlayerItemDidPlayToEndTime,
                object: newItem
            )
            // 让静音键不中断播放，并兼容系统音乐被打断时自动让路。
            try? AVAudioSession.sharedInstance().setCategory(.playback, mode: .default)
            try? AVAudioSession.sharedInstance().setActive(true)
        } else {
            player?.seek(to: .zero)
        }
        player?.play()
        isPlaying = true
    }

    func stop() {
        player?.pause()
        if let it = item {
            NotificationCenter.default.removeObserver(
                self, name: .AVPlayerItemDidPlayToEndTime, object: it
            )
        }
        isPlaying = false
        playingURL = nil
    }

    @objc private func didEnd(_ note: Notification) {
        stop()
    }
}

// MARK: - 数据模型

/// 一条段评 / 本章说。
///
/// 字段与 Cay 书源 `comments` 系列函数返回的 JSON **一一对应**
/// （`gyParaList` / `gyChapterComments` / `gyReplies` 的产物）：
///
/// ```json
/// {"id":"...","user":"...","avatar":"https://...","content":"...",
///  "likes":51,"replyCount":7,"time":1766307000,
///  "images":["https://..."],"replyTo":"...","isAuthor":true,
///  "replies":[ ... ]}
/// ```
///
/// `time` 是**秒级**时间戳（书源脚本里已经统一过，
/// 毫秒值在 `gyMapShuqiComment` 里除过 1000）。
struct ReviewComment: Identifiable, Codable, Hashable, Sendable {
    var id: String
    var user: String
    var avatar: String?
    var content: String
    var likes: Int?
    var replyCount: Int?
    var time: Double?
    var images: [String]?
    /// 楼中楼里「回复 @某人」的那个人。
    var replyTo: String?
    /// 作者本人的评论，卡片上标一个「作者」。
    var isAuthor: Bool?
    var replies: [ReviewComment]?

    // MARK: 书源段评页抓下来的补充字段
    //
    // 这四项在书源页面里本来就存在（起点系页面：`.p1 .tag` 等级徽章、
    // `.p3-left` 的「时间 · IP」、`.zw` 段落原文、`audio` 语音），
    // 抓取器把它们一并带回来，卡片就按书源原样显示，不再自己编。

    /// 等级 / 头衔文字，例如「见习」「舵主」。
    var levelText: String?
    /// 「11-11 22:10 · 江苏」这种书源写好的副行，比时间戳更贴近原页面。
    var meta: String?
    /// 本段原文引用（`.zw`）。
    var quote: String?
    /// 语音评论（`audio[src]`）。
    var voice: String?
    /// 所属段落标题，例如「第 12 段」「整章章末讨论」。
    var segment: String?

    init(
        id: String,
        user: String,
        avatar: String? = nil,
        content: String,
        likes: Int? = nil,
        replyCount: Int? = nil,
        time: Double? = nil,
        images: [String]? = nil,
        replyTo: String? = nil,
        isAuthor: Bool? = nil,
        replies: [ReviewComment]? = nil,
        levelText: String? = nil,
        meta: String? = nil,
        quote: String? = nil,
        voice: String? = nil,
        segment: String? = nil
    ) {
        self.id = id
        self.user = user
        self.avatar = avatar
        self.content = content
        self.likes = likes
        self.replyCount = replyCount
        self.time = time
        self.images = images
        self.replyTo = replyTo
        self.isAuthor = isAuthor
        self.replies = replies
        self.levelText = levelText
        self.meta = meta
        self.quote = quote
        self.voice = voice
        self.segment = segment
    }
}

/// 一页段评：书源返回 `{ items, hasMore, cursor }`，这里只取面板要用的部分。
struct ReviewCommentPage: Codable, Sendable {
    var items: [ReviewComment]
    var hasMore: Bool?
    var cursor: String?

    init(items: [ReviewComment], hasMore: Bool? = nil, cursor: String? = nil) {
        self.items = items
        self.hasMore = hasMore
        self.cursor = cursor
    }
}

// MARK: - 面板

/// 原生段评面板。
///
/// 这条路和「把书源网页重排一遍」是两件事：
/// 卡片由 SwiftUI 画，数据是书源脚本直接给出的 JSON，
/// 没有 DOM、没有 CSS 继承、没有「这张图到底是不是头像」的猜测。
/// 字段缺失最多是那一块不显示，不会把整张卡片挤乱。
///
/// 目前只接了展示层与数据模型，数据来源等 `.cay` 书源运行时接上后直接喂 `[ReviewComment]`。
struct NativeReviewPanelView: View {
    let title: String
    /// 段号，例如「第 109 段」；整章本章说传 nil。
    let paragraphLabel: String?
    let comments: [ReviewComment]

    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: DSSpacing.sm) {
                header

                // 本章说页会把多段评论一次给全（每段一个 `.segment-block`）。
                // 有分段信息时按段落分组，段标题用书源写的那行字（「第 12 段」），
                // 没分段就平铺 —— 段评本来就只有一段。
                ForEach(Array(sections.enumerated()), id: \.offset) { _, section in
                    if let label = section.label {
                        Text(label)
                            .font(.system(size: 12, weight: .medium))
                            .foregroundStyle(DSColor.textSecondary)
                            .padding(.horizontal, 2)
                            .padding(.top, DSSpacing.sm)
                    }
                    ForEach(section.comments) { comment in
                        ReviewCommentCard(comment: comment, isNested: false)
                    }
                }

                if comments.isEmpty {
                    Text(localized("暂无评论"))
                        .font(DSFont.footnote)
                        .foregroundStyle(DSColor.textSecondary)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, DSSpacing.xl)
                }
            }
            .padding(.horizontal, DSSpacing.md)
            .padding(.bottom, DSSpacing.xl)
        }
        .scrollIndicators(.hidden)
        .background(Color.clear)
    }

    private struct CommentSection {
        let label: String?
        let comments: [ReviewComment]
    }

    /// 按 `segment` 分组；只有一个分段时去掉标题，保持清爽。
    private var sections: [CommentSection] {
        var order: [String] = []
        var bucket: [String: [ReviewComment]] = [:]
        for comment in comments {
            let key = comment.segment?.trimmingCharacters(in: .whitespaces) ?? ""
            if bucket[key] == nil { order.append(key) }
            bucket[key, default: []].append(comment)
        }
        guard order.count > 1 else {
            return [CommentSection(label: nil, comments: comments)]
        }
        return order.map { key in
            CommentSection(label: key.isEmpty ? nil : key, comments: bucket[key] ?? [])
        }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: DSSpacing.sm) {
                Text(title)
                    .font(DSFont.headline)
                    .foregroundStyle(DSColor.textPrimary)
                Text(String(format: localized("%d 条"), comments.count))
                    .font(DSFont.caption)
                    .foregroundStyle(DSColor.textSecondary)
                Spacer()
            }
            if let paragraphLabel, !paragraphLabel.isEmpty {
                Text(paragraphLabel)
                    .font(DSFont.caption)
                    .foregroundStyle(DSColor.textSecondary)
            }
        }
        .padding(.top, DSSpacing.sm)
        .padding(.bottom, 2)
    }
}

// MARK: - 卡片

private struct ReviewCommentCard: View {
    let comment: ReviewComment
    let isNested: Bool

    @Environment(\.colorScheme) private var colorScheme

    /// 设置页可调的参数。@Observable，拖动滑杆时卡片会即时重画。
    private var style: NativeReviewPanelStyleStore { .shared }
    private var typography: NativeReviewTypography { style.typography() }

    /// 用户手动点过展开/收起就记住用户的，否则跟随设置里的默认值。
    /// 不在 @State(initialValue:) 里读单例，避开 Swift 6 的主 actor 隔离限制，
    /// 也避免列表复用时被反复重置成默认值。
    @State private var repliesOverride: Bool?
    private var repliesExpanded: Bool {
        repliesOverride ?? style.repliesDefaultExpanded
    }

    /// 点开的配图（全屏查看器）。nil = 没开。
    @State private var viewerImage: ReviewViewerImageItem?

    private var avatarSide: CGFloat {
        isNested ? max(18, CGFloat(style.avatarSize) * 0.63) : CGFloat(style.avatarSize)
    }

    /// 折叠时最多直接展示几条（设置页可调）。
    private var collapsedLimit: Int { max(0, style.collapsedReplyLimit) }

    var body: some View {
        HStack(alignment: .top, spacing: isNested ? 8 : 10) {
            avatar

            VStack(alignment: .leading, spacing: 6) {
                nameRow
                content
                voiceBar
                images
                footer
                replies
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(isNested ? 10 : 12)
        .background {
            let radius = isNested
                ? max(6, CGFloat(style.cornerRadius) - 4)
                : CGFloat(style.cornerRadius)
            let shape = RoundedRectangle(cornerRadius: radius, style: .continuous)
            // 夜色模式下不再描白边：白边在暗色背景上会画出一圈明显的「框」。
            // 暗色下直接无描边，卡片区分交给极淡底色 + 阴影；亮色下保留细高光。
            let stroke: Color = colorScheme == .dark
                ? Color.clear
                : Color.white.opacity(0.30)
            shape
                .fill(cardFill)
                .overlay(
                    shape.strokeBorder(stroke, lineWidth: 0.5)
                )
                .shadow(
                    color: .black.opacity(isNested ? 0 : (colorScheme == .dark ? 0.18 : 0.05)),
                    radius: isNested ? 0 : 10,
                    y: isNested ? 0 : 2
                )
        }
        // 配图点击 → 全屏查看器（黑底、缩放、GIF 照常播放）。
        .fullScreenCover(item: $viewerImage) { item in
            ReviewImageViewer(url: item.url)
        }
    }

    // MARK: 头像

    private var avatar: some View {
        Group {
            if let url = comment.avatar.flatMap(URL.init(string:)), !comment.avatar!.isEmpty {
                AsyncImage(url: url) { phase in
                    switch phase {
                    case .success(let image):
                        image.resizable().scaledToFill()
                    default:
                        avatarPlaceholder
                    }
                }
            } else {
                avatarPlaceholder
            }
        }
        .frame(width: avatarSide, height: avatarSide)
        .clipShape(Circle())
        .overlay(Circle().strokeBorder(Color.primary.opacity(0.06), lineWidth: 0.5))
    }

    private var avatarPlaceholder: some View {
        ZStack {
            Color.primary.opacity(0.07)
            Text(initial)
                .font(.system(size: avatarSide * 0.42, weight: .medium))
                .foregroundStyle(DSColor.textSecondary)
        }
    }

    private var initial: String {
        String(comment.user.trimmingCharacters(in: .whitespaces).prefix(1))
    }

    // MARK: 昵称

    private var nameRow: some View {
        HStack(spacing: 6) {
            Text(comment.user.isEmpty ? localized("书友") : comment.user)
                .font(typography.font(size: typography.nameSize - (isNested ? 1 : 0), weight: .medium))
                .foregroundStyle(DSColor.textSecondary)
                .lineLimit(1)

            if style.showsLevel, let level = comment.levelText, !level.isEmpty {
                Text(level)
                    .font(typography.font(size: max(9, typography.metaSize - 1.5), weight: .medium))
                    .foregroundStyle(DSColor.accent)
                    .lineLimit(1)
                    .padding(.horizontal, 5)
                    .padding(.vertical, 1)
                    .background(DSColor.accent.opacity(0.12), in: RoundedRectangle(cornerRadius: 4, style: .continuous))
            }

            if comment.isAuthor == true {
                Text(localized("作者"))
                    .font(typography.font(size: max(9, typography.metaSize - 1.5), weight: .medium))
                    .foregroundStyle(DSColor.accent)
                    .padding(.horizontal, 5)
                    .padding(.vertical, 1)
                    .background(DSColor.accent.opacity(0.12), in: RoundedRectangle(cornerRadius: 4, style: .continuous))
            }

            Spacer(minLength: 0)
        }
    }

    // MARK: 正文

    private var content: some View {
        VStack(alignment: .leading, spacing: 6) {
            if style.showsQuote, !isNested, let quote = comment.quote, !quote.isEmpty {
                Text(quote)
                    .font(typography.font(size: typography.metaSize + 0.5))
                    .foregroundStyle(DSColor.textSecondary)
                    .lineSpacing(max(1, typography.lineSpacing - 1))
                    .lineLimit(4)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 6)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(
                        // 用中性灰而非 primary（暗色下 primary=白），避免在夜色模式
                        // 给引用段落画出一块发白的方框。
                        Color.secondary.opacity(colorScheme == .dark ? 0.12 : 0.06),
                        in: RoundedRectangle(cornerRadius: 8, style: .continuous)
                    )
            }
            Text(bodyText)
            .font(typography.font(size: typography.contentSize - (isNested ? 1.5 : 0)))
            // tracking 是 Text 的方法，必须在 foregroundStyle（返回 some View）之前。
            .tracking(typography.letterSpacing ?? 0)
            .foregroundStyle(DSColor.textPrimary)
            .lineSpacing(typography.lineSpacing)
            .fixedSize(horizontal: false, vertical: true)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private var bodyText: String {
        if let replyTo = comment.replyTo, !replyTo.isEmpty {
            return String(format: localized("回复 @%@：%@"), replyTo, comment.content)
        }
        return comment.content
    }

    // MARK: 语音条

    /// 段评里的语音评论胶囊条。无语音或设置页关闭时不显示。
    @ViewBuilder
    private var voiceBar: some View {
        if style.showsVoice,
           let voice = comment.voice, !voice.isEmpty,
           let url = URL(string: voice) {
            VoiceCapsuleBar(url: url)
        }
    }

    // MARK: 配图

    @ViewBuilder
    private var images: some View {
        let urls = style.showsImages
            ? (comment.images ?? []).compactMap { URL(string: $0) }
            : []
        if !urls.isEmpty {
            if urls.count == 1 {
                singleImage(urls[0])
            } else {
                LazyVGrid(
                    columns: Array(repeating: GridItem(.flexible(), spacing: 6), count: 3),
                    spacing: 6
                ) {
                    ForEach(Array(urls.enumerated()), id: \.offset) { _, url in
                        // GIF 动图在九宫格里也要动起来；点开进全屏查看器。
                        ReviewAnimatedImageView(url: url, fills: true, placeholderHeight: 84)
                            .frame(height: 84)
                            .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                            .clipped()
                            .contentShape(Rectangle())
                            .onTapGesture { viewerImage = ReviewViewerImageItem(url: url) }
                    }
                }
            }
        }
    }

    private func singleImage(_ url: URL) -> some View {
        ReviewAnimatedImageView(url: url, fills: false, placeholderHeight: 200)
            .frame(maxWidth: 220, maxHeight: 220, alignment: .leading)
            .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
            .contentShape(Rectangle())
            .onTapGesture { viewerImage = ReviewViewerImageItem(url: url) }
    }

    // MARK: 底部

    private var footer: some View {
        HStack(spacing: DSSpacing.md) {
            if style.showsMeta,
               let caption = comment.meta?.trimmingCharacters(in: .whitespaces), !caption.isEmpty {
                Text(caption)
                    .font(typography.font(size: typography.metaSize))
                    .foregroundStyle(DSColor.textSecondary)
                    .lineLimit(1)
            } else if style.showsMeta, let timeText {
                Text(timeText)
                    .font(typography.font(size: typography.metaSize))
                    .foregroundStyle(DSColor.textSecondary)
            }

            Spacer(minLength: 0)

            if style.showsLikes, let likes = comment.likes, likes > 0 {
                Label("\(likes)", systemImage: "hand.thumbsup")
                    .labelStyle(.titleAndIcon)
                    .font(typography.font(size: typography.metaSize))
                    .foregroundStyle(DSColor.textSecondary)
            }

            if totalReplyCount > 0 {
                Button {
                    toggleReplies()
                } label: {
                    HStack(spacing: 3) {
                        // 展开态直接写成「收起回复」：一层回复也能一眼看到收回入口，
                        // 不用去猜那个「N 条回复」到底能不能再点一次。
                        Text(
                            repliesExpanded && hasInlineReplies
                                ? localized("收起回复")
                                : String(format: localized("%d 条回复"), totalReplyCount)
                        )
                        .font(typography.font(size: typography.metaSize))
                        if hasInlineReplies {
                            Image(systemName: "chevron.down")
                                .font(.system(size: 9, weight: .semibold))
                                .rotationEffect(.degrees(repliesExpanded ? 180 : 0))
                        }
                    }
                    .foregroundStyle(hasInlineReplies ? DSColor.accent : DSColor.textSecondary)
                }
                .buttonStyle(.plain)
                .disabled(!hasInlineReplies)
            }
        }
        .padding(.top, 2)
    }

    private var timeText: String? {
        guard let time = comment.time, time > 0 else { return nil }
        return Self.timeFormatter.string(from: Date(timeIntervalSince1970: time))
    }

    private static let timeFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "MM-dd HH:mm"
        return formatter
    }()

    // MARK: 楼中楼

    @ViewBuilder
    private var replies: some View {
        if !isNested, !visibleReplies.isEmpty {
            VStack(alignment: .leading, spacing: 6) {
                ForEach(visibleReplies) { reply in
                    ReviewCommentCard(comment: reply, isNested: true)
                }
                if hiddenReplyCount > 0 {
                    Button {
                        toggleReplies()
                    } label: {
                        HStack(spacing: 3) {
                            Text(String(format: localized("展开其余 %d 条回复"), hiddenReplyCount))
                                .font(typography.font(size: typography.metaSize + 0.5))
                            Image(systemName: "chevron.down")
                                .font(.system(size: 9, weight: .semibold))
                        }
                        .foregroundStyle(DSColor.accent)
                        .padding(.leading, 32)
                        .padding(.top, 2)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                } else if repliesExpanded, hasInlineReplies {
                    Button {
                        toggleReplies()
                    } label: {
                        Text(localized("收起回复"))
                            .font(typography.font(size: typography.metaSize + 0.5))
                            .foregroundStyle(DSColor.textSecondary)
                            .padding(.leading, 32)
                            .padding(.top, 2)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.top, 2)
        }
    }

    // MARK: 楼中楼展开

    private var hasInlineReplies: Bool {
        !(comment.replies ?? []).isEmpty
    }

    /// 书源给的数量（replyCount）和内联回复条数取大值，避免「显示 0 条却有回复」。
    private var totalReplyCount: Int {
        max(comment.replyCount ?? 0, (comment.replies ?? []).count)
    }

    private var visibleReplies: [ReviewComment] {
        let all = comment.replies ?? []
        guard !all.isEmpty else { return [] }
        if repliesExpanded { return all }
        // 只有一层（≤ 2 条）回复时，折叠态必须真的收成空。
        // 旧实现在这里直接 `return all`，导致折叠态和展开态长得一模一样：
        // 点「收回」看不出任何变化，就是用户说的「一层楼中楼收不回去」。
        // 现在统一交给 footer 的「N 条回复」展开，展开后底部再给「收起回复」。
        if all.count <= collapsedLimit { return [] }
        return Array(all.prefix(collapsedLimit))
    }

    private var hiddenReplyCount: Int {
        let all = comment.replies ?? []
        guard !repliesExpanded, all.count > collapsedLimit else { return 0 }
        return all.count - collapsedLimit
    }

    private func toggleReplies() {
        guard hasInlineReplies else { return }
        withAnimation(.easeInOut(duration: 0.18)) {
            // 只写「用户覆盖值」，默认值仍由设置页决定；列表复用时也不会被重置。
            repliesOverride = !(repliesOverride ?? style.repliesDefaultExpanded)
        }
    }

    /// 卡片只上一层「很薄的高光」，不再铺任何实底，也不再叠第二层模糊。
    ///
    /// 面板底已经是 `ultraThinMaterial`（系统模糊），卡片再盖 material 等于
    /// 在同一处糊两次，越糊越白、越糊越不透 —— 看着就是一块白底。
    /// 现在卡片只剩 12% 的白 + 一条高光描边，正文的明暗能直接透到卡片上，
    /// 卡片与面板的区分靠边框和极淡阴影，而不是靠一块白色。
    private var cardFill: AnyShapeStyle {
        let base = CGFloat(style.cardOpacity)
        if isNested {
            return AnyShapeStyle(Color.primary.opacity(base * (colorScheme == .dark ? 1.15 : 0.7)))
        }
        return AnyShapeStyle(Color.white.opacity(base * (colorScheme == .dark ? 0.7 : 1)))
    }
}

// MARK: - 语音条

/// 段评语音条：灰色圆角胶囊 + 玻璃质感播放钮 + 波纹图标 + 时长。
///
/// 设计对齐要求：胶囊为灰色半透明圆角；播放钮是「透明玻璃感」的圆形，
/// 内部一个 `waveform` 波纹图标；右侧显示语音时长（秒，形如 `16''`）。
/// 点按交给单例 `ReviewVoicePlayer`，保证全 App 同时只放一段语音。
@MainActor
private struct VoiceCapsuleBar: View {
    let url: URL

    @StateObject private var player = ReviewVoicePlayer.shared
    @State private var duration: Double?
    @Environment(\.colorScheme) private var colorScheme

    private var typography: NativeReviewTypography { NativeReviewPanelStyleStore.shared.typography() }

    /// 时长按 URL 缓存，避免列表里每条语音都去远端取一次。
    private static var durationCache = [String: Double]()

    var body: some View {
        HStack(spacing: 10) {
            Button {
                player.toggle(url)
            } label: {
                Image(systemName: "waveform")
                    .font(.system(size: 15, weight: .medium))
                    .foregroundStyle(Color.primary.opacity(0.7))
                    .frame(width: 34, height: 34)
                    .background(
                        Circle()
                            .fill(.ultraThinMaterial)
                            .overlay(
                                Circle().strokeBorder(Color.primary.opacity(0.12), lineWidth: 0.5)
                            )
                    )
            }
            .buttonStyle(.plain)

            Text(durationText)
                .font(typography.font(size: typography.metaSize))
                .foregroundStyle(DSColor.textSecondary)

            Spacer(minLength: 0)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 7)
        .background(
            Capsule().fill(Color.secondary.opacity(colorScheme == .dark ? 0.18 : 0.10))
        )
        .frame(maxWidth: 220)
        .task { await loadDuration() }
    }

    private var isPlaying: Bool { player.isPlaying && player.playingURL == url }

    private var durationText: String {
        guard let d = duration, d.isFinite, d > 0 else { return "" }
        return String(format: "%d''", Int(d.rounded()))
    }

    private func loadDuration() async {
        let key = url.absoluteString
        if let cached = Self.durationCache[key] {
            duration = cached
            return
        }
        do {
            let asset = AVURLAsset(url: url)
            let seconds = try await asset.load(.duration).seconds
            Self.durationCache[key] = seconds
            duration = seconds
        } catch {
            // 取不到时长就不显示，胶囊仍可用（点按照常播放）。
        }
    }
}

// MARK: - 预览数据

/// 示例数据，只用于设置页的面板预览；字段取自书源真实返回。
enum ReviewPanelSampleData {
    static let paragraphComments: [ReviewComment] = [
        ReviewComment(
            id: "c1",
            user: "反向抽烟不带火",
            avatar: "https://picsum.photos/seed/rp1/120/120",
            content: "张伟、尔康、以及金甲战士。\n张大胆、斯内克、爱情公寓最好玩的男人。",
            likes: 51,
            replyCount: 3,
            time: 1_766_307_000,
            images: ["https://picsum.photos/seed/rp2/720/480"],
            replies: [
                ReviewComment(
                    id: "c1-1",
                    user: "书友 2048",
                    avatar: "https://picsum.photos/seed/rp3/80/80",
                    content: "这图笑死我了哈哈哈",
                    likes: 3,
                    time: 1_766_307_600
                ),
                ReviewComment(
                    id: "c1-2",
                    user: "夜航船",
                    avatar: "https://picsum.photos/seed/rp4/80/80",
                    content: "张伟永远的神",
                    likes: 1,
                    time: 1_766_308_200
                ),
                ReviewComment(
                    id: "c1-3",
                    user: "橘子汽水",
                    avatar: "https://picsum.photos/seed/rp5/80/80",
                    content: "回复 @夜航船：同感，这一段封神。",
                    likes: 0,
                    time: 1_766_309_000,
                    replyTo: "夜航船"
                )
            ]
        ),
        ReviewComment(
            id: "c2",
            user: "橘子汽水",
            avatar: "https://picsum.photos/seed/rp5/120/120",
            content: "这一段我反复看了三遍，作者是真的会写。",
            likes: 12,
            replyCount: 2,
            time: 1_766_302_000,
            replies: [
                ReviewComment(
                    id: "c2-1",
                    user: "青衫落拓",
                    avatar: "https://picsum.photos/seed/rp7/80/80",
                    content: "我也是，尤其最后那句。",
                    likes: 2,
                    time: 1_766_303_000
                ),
                ReviewComment(
                    id: "c2-2",
                    user: "南风知我意",
                    avatar: "https://picsum.photos/seed/rp8/80/80",
                    content: "准备二刷了。",
                    likes: 1,
                    time: 1_766_303_600
                )
            ]
        ),
        ReviewComment(
            id: "c3",
            user: "作者",
            avatar: "https://picsum.photos/seed/rp6/120/120",
            content: "谢谢大家，下一章会更精彩。",
            likes: 208,
            replyCount: 0,
            time: 1_766_296_000,
            isAuthor: true
        )
    ]
}
