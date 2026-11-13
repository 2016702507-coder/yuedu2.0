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

    /// 面板头：居中「段评」+ 段落原文引用框。
    ///
    /// 不再显示「N 条」评论总数：那个数来自书源页面自己的计数，和实际抓到的
    /// 评论条数经常对不上（反馈「评论数严重不符」），这里一个数字都不显示。
    private var header: some View {
        VStack(spacing: 11) {
            Text(localized("段评"))
                .font(.system(size: 16.5, weight: .bold))
                .foregroundStyle(DSColor.textPrimary)
                .frame(maxWidth: .infinity)

            if !quoteText.isEmpty {
                Text(quoteText)
                    .font(.system(size: 13))
                    .italic()
                    .foregroundStyle(DSColor.textSecondary)
                    .lineSpacing(2)
                    .lineLimit(3)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 11)
                    .background {
                        // 引用原文框也用玻璃：跟面板同一套設定驅動，比面板略實並留一圈
                        // 細白描邊，做出參考圖那種淡玻璃卡片，不再是白底實心方塊。
                        ReviewQuoteGlass(cornerRadius: 14)
                    }
            }
        }
        .padding(.top, DSSpacing.sm)
        .padding(.bottom, 8)
    }

    /// 引用框里显示点开的那段原文。书源把原文放在 title 里；没给就用段号兜底。
    private var quoteText: String {
        let trimmed = title.trimmingCharacters(in: .whitespacesAndNewlines)
        if !trimmed.isEmpty, trimmed != localized("段评") { return trimmed }
        return paragraphLabel?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
    }
}

// MARK: - 引用原文框玻璃

/// 引用原文框也用玻璃：跟 `ReviewSheetGlassBackground` 同一套設定驅動（兩個透明度
/// 滑桿），但比面板底略實一點並留一圈細白描邊，做出參考圖那種「淡玻璃卡片」的
/// 層次。以前這裡是 `Color.white.opacity(0.66)` 白底實心方塊，面板改成玻璃後它
/// 仍是白的，正是「引用的正文那裡也要玻璃」要修的地方。
private struct ReviewQuoteGlass: View {
    @Bindable private var settings = GlobalSettings.shared
    @Environment(\.colorScheme) private var colorScheme

    var cornerRadius: CGFloat = 14

    /// 濃度 0 = 最透、1 = 最實，公式與面板玻璃完全一致。
    private var level: Double {
        let sheet = min(max(settings.reviewSheetOpacity, 0), 1)
        let global = 1 - min(max(settings.interfaceGlassTransparency, 0), 1)
        return min(max(0.7 * sheet + 0.3 * global, 0), 1)
    }

    /// 比面板底略實：0 → 0.20（仍能透出背後書頁）、1 → 0.90。
    private var materialOpacity: Double { 0.20 + 0.70 * level }

    /// 極淡 tint 給玻璃一點厚度；暗色用黑，避免夜間發白。
    private var tintOpacity: Double {
        (colorScheme == .dark ? 0.05 : 0.03) + 0.42 * level
    }

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                .fill(.ultraThinMaterial)
                .opacity(materialOpacity)
            RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                .fill(colorScheme == .dark ? Color.black : Color.white)
                .opacity(tintOpacity)
        }
        .overlay(
            RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                .strokeBorder(
                    Color.white.opacity(colorScheme == .dark ? 0.16 : 0.72),
                    lineWidth: 0.8
                )
        )
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
        .padding(.horizontal, 2)
        .padding(.vertical, isNested ? 8 : 13)
        // 照参考图：评论直接排在玻璃底上，不铺卡片实底、不描边、不加阴影，
        // 只留一条极淡的细分隔线；半屏和全屏都是同一块玻璃。
        .overlay(alignment: .bottom) {
            if !isNested {
                Rectangle()
                    .fill(Color.secondary.opacity(colorScheme == .dark ? 0.14 : 0.09))
                    .frame(height: 0.5)
            }
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
                .foregroundStyle(DSColor.textPrimary)
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

            // 点赞挪到昵称行右侧（参考图的 👍240 位），底部只留时间和回复入口。
            if style.showsLikes, let likes = comment.likes, likes > 0 {
                HStack(spacing: 3) {
                    Image(systemName: "hand.thumbsup")
                    Text("\(likes)")
                }
                .font(typography.font(size: typography.metaSize))
                .foregroundStyle(DSColor.textSecondary)
            }
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
                    .background {
                        // 同上：评论里的引用段落也是玻璃，不再是一块灰底方块。
                        ReviewQuoteGlass(cornerRadius: 8)
                    }
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

            // 回复入口不再写「N 条回复」：书源给的计数和真实楼中楼条数常对不上，
            // 一律改成不带数字的文字按钮，展开/收起功能不变。
            if hasInlineReplies {
                Button {
                    toggleReplies()
                } label: {
                    HStack(spacing: 3) {
                        Text(repliesExpanded ? localized("收起回复") : localized("查看回复"))
                            .font(typography.font(size: typography.metaSize))
                        Image(systemName: "chevron.down")
                            .font(.system(size: 9, weight: .semibold))
                            .rotationEffect(.degrees(repliesExpanded ? 180 : 0))
                    }
                    .foregroundStyle(DSColor.accent)
                }
                .buttonStyle(.plain)
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
                    replyCapsule(reply)
                }
                if hiddenReplyCount > 0 {
                    Button {
                        toggleReplies()
                    } label: {
                        HStack(spacing: 3) {
                            Text(localized("展开更多回复"))
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

    /// 楼中楼：一条灰色圆角胶囊，小圆头像 +「昵称：内容」，对齐参考图。
    private func replyCapsule(_ reply: ReviewComment) -> some View {
        HStack(alignment: .top, spacing: 6) {
            Group {
                if let raw = reply.avatar, !raw.isEmpty, let url = URL(string: raw) {
                    AsyncImage(url: url) { phase in
                        switch phase {
                        case .success(let image): image.resizable().scaledToFill()
                        default: Circle().fill(Color.primary.opacity(0.08))
                        }
                    }
                } else {
                    Circle().fill(Color.primary.opacity(0.08))
                }
            }
            .frame(width: 20, height: 20)
            .clipShape(Circle())

            Text(replyLine(reply))
                .font(typography.font(size: typography.metaSize + 0.5))
                .foregroundStyle(DSColor.textSecondary)
                .lineSpacing(2)
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 7)
        .background(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(Color.secondary.opacity(colorScheme == .dark ? 0.14 : 0.075))
        )
    }

    private func replyLine(_ reply: ReviewComment) -> String {
        let name = reply.user.isEmpty ? localized("书友") : reply.user
        if let replyTo = reply.replyTo, !replyTo.isEmpty {
            return "\(name)：回复 @\(replyTo)：\(reply.content)"
        }
        return "\(name)：\(reply.content)"
    }

    // MARK: 楼中楼展开

    private var hasInlineReplies: Bool {
        !(comment.replies ?? []).isEmpty
    }

    private var visibleReplies: [ReviewComment] {
        let all = comment.replies ?? []
        guard !all.isEmpty else { return [] }
        if repliesExpanded { return all }
        // 只有一层（≤ 2 条）回复时，折叠态必须真的收成空。
        // 旧实现在这里直接 `return all`，导致折叠态和展开态长得一模一样：
        // 点「收回」看不出任何变化，就是用户说的「一层楼中楼收不回去」。
        // 现在统一交给 footer 的「查看回复」展开，展开后底部再给「收起回复」。
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
                Image(systemName: isPlaying ? "waveform.circle.fill" : "waveform")
                    .font(.system(size: 15, weight: .medium))
                    .foregroundStyle(Color.primary.opacity(0.7))
                    .symbolEffect(.variableColor, isActive: isPlaying)
                    .frame(width: 34, height: 34)
                    .background(
                        Circle()
                            .fill(.ultraThinMaterial)
                            .overlay(
                                Circle().strokeBorder(Color.white.opacity(colorScheme == .dark ? 0.14 : 0.75), lineWidth: 0.7)
                            )
                            .shadow(color: Color.black.opacity(0.08), radius: 3, y: 1)
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
            Capsule()
                .fill(Color.gray.opacity(colorScheme == .dark ? 0.26 : 0.16))
                .overlay(
                    Capsule().strokeBorder(Color.white.opacity(colorScheme == .dark ? 0.08 : 0.5), lineWidth: 0.6)
                )
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
