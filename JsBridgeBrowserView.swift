import SwiftUI
import WebKit
import Combine
import ObjectiveC
import UIKit
import CoreImage
import CoreImage.CIFilterBuiltins

/// Paragraph-review sheets deliberately use only the source page's own UI.
/// Login and other source browsers keep `JsBridgeBrowserView`'s normal toolbar.
enum ParagraphReviewBrowserPresentationPolicy {
    static let hidesToolbar = true
}

/// 段评面板的底：真正的毛玻璃。
///
/// 面板页面是全透明的，玻璃感来自 sheet 自己的 `.ultraThinMaterial`（会实时模糊背后的正文）。
/// 这里只再叠一层极淡的纯色蒙版控制浓淡：档位调低几乎只剩玻璃，调高就接近普通白/黑面板。
enum ParagraphReviewVeil {
    static func color(for scheme: ColorScheme, opacity: Double) -> Color {
        let level = min(max(opacity, 0), 1)
        switch scheme {
        case .dark: return Color.black.opacity(level)
        case .light: return Color.white.opacity(level)
        @unknown default: return Color.black.opacity(level)
        }
    }
}

/// 段評面板專用玻璃：半屏與全屏、UIKit 呈現與 SwiftUI sheet 都共用這一塊，
/// 由內容自己畫，因此不會被 clearSheetChrome 清掉，兩種檔位、兩條路徑完全一致。
///
/// 「段評面板不透明度」/「玻璃濃淡」是同一個 `reviewSheetOpacity`，現在它直接
/// 驅動這塊**玻璃本身**：0 = 最透的磨砂玻璃（背後書頁正文半清半糊地透上來），
/// 1 = 接近普通實色面板。以前這裡把材質寫死成 0.90 + 0.22 白，滑桿只改另一層
/// 純色蒙版，兩者解耦，所以使用者把不透明度拉到 0 看到的仍是一塊灰白實心板。
///
/// 不再受「全局玻璃總閘 / 系統降低透明度」一刀切成不透明純色：那條兜底會把
/// 使用者明確要的玻璃直接換成實色，正是「怎麼調都沒用」的另一半原因。
/// 真正的 `UIVisualEffectView` 毛玻璃，而不是 SwiftUI 自带的 `.ultraThinMaterial`。
///
/// 段评面板是 UIKit `present()` 出来的页面 sheet，SwiftUI 的材质在拖到 `.large` 满屏档时
/// 采样不到背后的书页、会退化成刺眼白板（半屏玻璃、全屏白底的根因）。
/// 原生 `UIVisualEffectView` 直接采窗口里背后那一层（书页），任何档位都稳定出玻璃，
/// 半屏/全屏完全一致。透明度由外层 `.opacity()` 控制，跟之前语义一致。
struct GlassBlurView: UIViewRepresentable {
    var blurStyle: UIBlurEffect.Style = .systemUltraThinMaterial

    func makeUIView(context: Context) -> UIVisualEffectView {
        UIVisualEffectView(effect: UIBlurEffect(style: blurStyle))
    }

    func updateUIView(_ uiView: UIVisualEffectView, context: Context) {
        uiView.effect = UIBlurEffect(style: blurStyle)
    }
}

struct ReviewSheetGlassBackground: View {
    /// 設定頁預覽是嵌在列表裡的小卡片，不需要鋪出安全區。
    var fillsSafeArea: Bool = true

    @Bindable private var settings = GlobalSettings.shared
    @Environment(\.colorScheme) private var colorScheme

    /// 濃度 0 = 最透、1 = 最實。
    ///
    /// 兩個設定都真正接到這塊玻璃上，不再是「拉了只改另一層蒙版」：
    /// - 「外觀 › 界面效果 › 段評面板不透明度」/「段評與互動樣式 › 玻璃濃淡」
    ///   是同一個 `reviewSheetOpacity`（主權重 0.7）；
    /// - 「外觀 › 界面效果 › 透明度」`interfaceGlassTransparency`（權重 0.3），
    ///   1 = 最透、0 = 最實，與全 App 卡片的語義一致。
    /// 任何一個往「實」的方向拉，玻璃都立刻變濃；兩邊都拉到最透就是最清透的磨砂玻璃。
    private var level: Double {
        let sheet = min(max(settings.reviewSheetOpacity, 0), 1)
        let global = 1 - min(max(settings.interfaceGlassTransparency, 0), 1)
        return min(max(0.7 * sheet + 0.3 * global, 0), 1)
    }

    /// 極淡 tint，只給玻璃一點厚度、保證評論文字對比；不是白板來源。
    private var tintOpacity: Double {
        // tint 压到 0~0.14：白纸书页上材质自带白纱，tint 再叠白就糊成白板——
        // 玻璃的辨识度靠模糊采样的文字形状，不靠白底。
        0.14 * level
    }

    /// 固定淡玻璃色：跟滑杆走、绝不变白。真正「透出书页」的玻璃由
    /// `ReviewSheetBookBackdrop` 负责（见下方 `.presentationBackground`）。
    private var glass: some View {
        ZStack {
            (colorScheme == .dark ? Color.black : Color.white)
                .opacity(0.03 + 0.30 * level)
            // tint 用中性白：孤岛实测面板 R=G=B 零色偏，玻璃颜色全部来自
            // 材质对背景的采样，自身只做轻微提亮，绝不带固定色相。
            (colorScheme == .dark ? Color.black : Color.white)
                .opacity(tintOpacity)
        }
    }

    var body: some View {
        Group {
            if fillsSafeArea {
                glass.ignoresSafeArea()
            } else {
                glass
            }
        }
    }
}

/// 段评面板的玻璃底：弹出前拍下的书页截图（已预模糊），铺在面板内容最底层。
///
/// 为什么不用「实时采样」：`UIVisualEffectView` / `.ultraThinMaterial` 依赖系统对
/// 面板背后内容的实时采样，而 sheet 拖到 `.large` 满屏档时这条采样链路拿不到书页，
/// 会退化成刺眼白板——这正是「半屏玻璃、全屏白底」反复修不掉的根因。
/// 为什么不用 `.presentationBackground`：它在部分呈现链路上不生效，而且系统档位
/// 切换时的 chrome 行为不可控。
///
/// 所以改成**自己画**：`ReaderView` 在设置 `reviewTarget` 的同一笔状态变更里
/// （此时 sheet 还没开始上屏）把窗口当前帧——也就是完整的书页——截下来，
/// 一次性用 CoreImage 预模糊成玻璃底图，交给面板当内容最底层。它是面板自己的
/// 图层，任何档位、任何呈现路径都稳定渲染：半屏/全屏是同一张图，效果完全一致。
/// 截图万一失败，回落淡玻璃色兜底，仍不是白板。
struct ReviewBackdropCapture {
    /// 抓当前 key window 的最后一帧（`afterScreenUpdates: false`：
    /// 在 sheet 尚未上屏时调用，拿到的就是完整的书页画面）。
    static func keyWindowSnapshot() -> UIImage? {
        guard let window = UIApplication.shared.connectedScenes
            .compactMap({ $0 as? UIWindowScene })
            .flatMap({ $0.windows })
            .first(where: { $0.isKeyWindow }),
              !window.bounds.isEmpty else { return nil }
        let bounds = window.bounds
        let renderer = UIGraphicsImageRenderer(size: bounds.size)
        return renderer.image { _ in
            window.drawHierarchy(in: bounds, afterScreenUpdates: false)
        }
    }

    /// 把截图一次性糊成玻璃底（CIGaussianBlur + 边缘扩展，避免边缘发白）。
    /// 预模糊后运行时只是贴一张图，拖动档位也零开销。
    static func blurredGlass(_ image: UIImage, radius: Double = 22) -> UIImage? {
        guard let ciImage = CIImage(image: image) else { return nil }
        let clamped = ciImage.clampedToExtent()
        guard let filter = CIFilter(name: "CIGaussianBlur") else { return nil }
        filter.setValue(clamped, forKey: kCIInputImageKey)
        filter.setValue(radius, forKey: kCIInputRadiusKey)
        guard let output = filter.outputImage else { return nil }
        // 裁回原尺寸，去掉 clampedToExtent 的无限延展。
        let cropped = output.cropped(to: ciImage.extent)
        let context = CIContext(options: [.useSoftwareRenderer: false])
        guard let cgImage = context.createCGImage(cropped, from: ciImage.extent) else { return nil }
        return UIImage(cgImage: cgImage, scale: image.scale, orientation: image.imageOrientation)
    }
}

/// 面板最底层的玻璃：屏幕对齐的模糊书页图 + 由滑杆驱动的极淡 tint。
struct ReviewPanelBackdropLayer: View {
    /// 弹出前抓下的书页截图（已预模糊）。nil = 回落淡玻璃色。
    let backdrop: UIImage?

    @Environment(\.colorScheme) private var colorScheme
    private var settings: GlobalSettings { .shared }

    private var level: Double {
        let sheet = min(max(settings.reviewSheetOpacity, 0), 1)
        let global = 1 - min(max(settings.interfaceGlassTransparency, 0), 1)
        return min(max(0.7 * sheet + 0.3 * global, 0), 1)
    }

    /// 「玻璃浓淡」对预模糊截图层的权重：0 = 截图淡出到 0.35（系统材质直接
    /// 实时采样真实书页，最透）；1 = 截图全显（磨砂最实）。两端都有材质玻璃底。
    private var backdropOpacity: Double {
        0.35 + 0.65 * level
    }

    private var windowSize: CGSize {
        if let w = UIApplication.shared.connectedScenes
            .compactMap({ $0 as? UIWindowScene })
            .first?.windows.first(where: { $0.isKeyWindow }) {
            return w.bounds.size
        }
        return UIScreen.main.bounds.size
    }

    private var tintOpacity: Double {
        // tint 压到 0~0.14：白纸书页上材质自带白纱，tint 再叠白就糊成白板——
        // 玻璃的辨识度靠模糊采样的文字形状，不靠白底。
        0.14 * level
    }

    var body: some View {
        GeometryReader { geo in
            ZStack {
                // 玻璃底全部交给系统实时材质：sheet 的 presentationBackground
                // 是透明色，材质能直接采样到背后的真实阅读页——滚动、翻页、
                // 换书，玻璃实时跟着变，任何档位/动画帧都对齐铺满。
                // 不再使用弹出瞬间拍的静态截图：那是一张死图，且窗口尺寸
                // 推算与 sheet 实际 frame 有偏差时会糊出错位的「下半角」。
                LiveGlassEffectLayer(level: level)
                // 匀光 tint：中性白零色偏（孤岛实测），只随玻璃浓淡提亮不染色。
                (colorScheme == .dark ? Color.black : Self.paperTint)
                    .opacity(tintOpacity)
            }
            .frame(width: geo.size.width, height: geo.size.height)
            .clipped()
            .ignoresSafeArea()
        }
        .ignoresSafeArea()
    }

    /// 匀光 tint：中性白（孤岛实测 R=G=B 零色偏），颜色自适应完全交给材质采样。
    private static let paperTint = Color.white
    /// 兜底磨砂色：中性浅灰，无截图时不抢色。
    private static let paperFallback = Color(white: 0.93)
}

/// 系统实时玻璃的 SwiftUI 桥：UIVisualEffectView + 系统超薄材质。
/// 深浅色自适应；面板后面是什么它就实时糊什么，任何档位/动画帧都对齐。
private struct LiveGlassEffectLayer: UIViewRepresentable {
    /// 「玻璃浓淡」0=最透、1=最实：材质层透明度随之摆动。此前材质恒定全效、
    /// 盖死在截图层之上，滑杆怎么拉都被它抹平——这是「滑杆没变化」的直接根因。
    var level: Double

    func makeUIView(context: Context) -> UIVisualEffectView {
        let view = UIVisualEffectView(effect: UIBlurEffect(style: .systemUltraThinMaterial))
        // 材质视图自身不要落底色：让采样结果直接透出来。
        view.backgroundColor = .clear
        view.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        return view
    }
    func updateUIView(_ uiView: UIVisualEffectView, context: Context) {
        // 最透端材质降到 0.15（白纸页上也不糊成白板，文字形状清晰可辨），
        // 最实端 0.75（重磨砂仍有内容透出）。无动画直改，拖滑杆即时跟手。
        uiView.alpha = 0.15 + 0.60 * level
    }
}

struct SourceBrowserPresentationConfiguration: Equatable {
    var heightPercentage: Double?
    var skipCollapsed = false
    var isHideable = true
    var expandedCornersRadius: Double?

    init(json: String) {
        guard let data = json.data(using: .utf8),
              let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            return
        }
        if let value = object["heightPercentage"] as? NSNumber,
           value.doubleValue > 0,
           value.doubleValue <= 1 {
            heightPercentage = value.doubleValue
        }
        if let value = object["skipCollapsed"] as? Bool { skipCollapsed = value }
        if let value = object["isHideable"] as? Bool { isHideable = value }
        if let value = object["expandedCornersRadius"] as? NSNumber,
           value.doubleValue >= 0,
           value.doubleValue <= 120 {
            expandedCornersRadius = value.doubleValue
        }
        // `hardwareAccelerated` is accepted as a no-op: WKWebView already uses
        // accelerated compositing and iOS exposes no per-page switch for it.
    }

    var detents: Set<PresentationDetent> {
        guard let heightPercentage else { return [.medium, .large] }
        let expanded: PresentationDetent = heightPercentage >= 1
            ? .large
            : .fraction(heightPercentage)
        return skipCollapsed ? [expanded] : [.medium, expanded]
    }
}

/// 点面板外收起段评面板，加在**呈现方**（阅读页、书详情、简介、听书）上。
///
/// SwiftUI 没有这个 API：`.presentationBackgroundInteraction` 一开，面板上方的正文就
/// 变成普通可交互区域，点它只会翻页，不会关面板（2.0.7 没开这个修饰符，是系统的遮罩层
/// 替它关的）。这一层透明点击区在 sheet 之下、正文之上：面板内的点按由面板自己接收，
/// 落在面板外的才到这里，所以不依赖手势仲裁，也不用算面板矩形。
///
/// 挂在 window 或 sheet 容器上的手势都收不到那次点按：阅读页的翻页手势挂得更深，UIKit
/// 会把识别机会让给它（维护者，2026-11-05）。
struct SheetOutsideTapDismissOverlay<Item: Identifiable>: ViewModifier {
    @Binding var item: Item?
    /// 书源把 `isHideable` 设成 false，就是要求必须看完：此时不加这一层。
    var isEnabled: Bool

    func body(content: Content) -> some View {
        content.overlay {
            if item != nil, isEnabled {
                Color.clear
                    .contentShape(Rectangle())
                    .ignoresSafeArea()
                    .onTapGesture { item = nil }
                    .accessibilityHidden(true)
            }
        }
    }
}

extension View {
    func sheetOutsideTapDismiss<Item: Identifiable>(
        item: Binding<Item?>,
        isEnabled: Bool = true
    ) -> some View {
        modifier(SheetOutsideTapDismissOverlay(item: item, isEnabled: isEnabled))
    }
}

extension ReaderHTMLUtilities.ReviewTarget {
    /// 面板本身会不会关：书源 `isHideable`。
    var isReviewSheetHideable: Bool {
        SourceBrowserPresentationConfiguration(
            json: sourceBrowserPage?.configurationJSON ?? ""
        ).isHideable
    }
}

// Modal WebView launched by `java.startBrowser` / `java.startBrowserAwait`.
// Shows a loading state (spinner + top progress bar) while the page loads so
// slow login/key servers don't appear as a frozen blank sheet, plus an error
// state with retry. Syncs WKWebView cookies into CookieStore and
// HTTPCookieStorage when the user taps "Done" (and on each navigation finish).

struct JsBridgeBrowserView: View {
    let urlString: String
    let title: String
    let onDismiss: (_ body: String?) -> Void
    let hidesToolbar: Bool
    let initialHTML: String?
    let initialRequest: URLRequest?
    let injectedJavaScript: String
    let sourceRunHandler: ((String) async throws -> String)?
    let sourceConfigurationUpdateHandler: ((String) -> Void)?
    /// The source's User-Agent. Legado opens a source's page with it, and Cloudflare ties
    /// `cf_clearance` to the User-Agent that solved the challenge: cleared under any other,
    /// the cookie is useless to the source's own requests. nil keeps `SourceWebIdentity`.
    let userAgent: String?
    /// Legado's `sourceVerificationEnable` (a page `java.startBrowserAwait` waits for): once
    /// a Cloudflare challenge on the page clears, the page finishes as if ✓ were tapped.
    let finishesWhenChallengeClears: Bool
    /// 段评面板要透出阅读器背景：WebView 与页面底色都清空，改成玻璃底。
    let transparentBackground: Bool
    /// 段评与互动样式页写好的自定义 CSS 注入脚本；空字串表示不注入。
    /// 由 `LegadoReviewBrowserView` 按当前日夜模式生成，段评面板专用。
    let customCSSScript: String
    /// 段评面板：页面加载后把评论抓出来交给原生卡片画。
    /// 关掉时页面行为与普通书源网页完全一致。
    let grabsComments: Bool
    /// 抓到评论（含后续滚动加载补抓）时回调。抓不到不会回调，页面照旧显示。
    let onCommentsGrabbed: ((GrabbedCommentPage) -> Void)?

    init(
        urlString: String,
        title: String = "",
        hidesToolbar: Bool = false,
        initialHTML: String? = nil,
        initialRequest: URLRequest? = nil,
        injectedJavaScript: String = "",
        sourceRunHandler: ((String) async throws -> String)? = nil,
        sourceConfigurationUpdateHandler: ((String) -> Void)? = nil,
        userAgent: String? = nil,
        finishesWhenChallengeClears: Bool = false,
        transparentBackground: Bool = false,
        customCSSScript: String = "",
        grabsComments: Bool = false,
        onCommentsGrabbed: ((GrabbedCommentPage) -> Void)? = nil,
        onDismiss: @escaping (_ body: String?) -> Void
    ) {
        self.urlString = urlString
        self.title = title
        self.hidesToolbar = hidesToolbar
        self.initialHTML = initialHTML
        self.initialRequest = initialRequest
        self.injectedJavaScript = injectedJavaScript
        self.sourceRunHandler = sourceRunHandler
        self.sourceConfigurationUpdateHandler = sourceConfigurationUpdateHandler
        self.userAgent = userAgent
        self.finishesWhenChallengeClears = finishesWhenChallengeClears
        self.transparentBackground = transparentBackground
        self.customCSSScript = customCSSScript
        self.grabsComments = grabsComments
        self.onCommentsGrabbed = onCommentsGrabbed
        self.onDismiss = onDismiss
    }

    @StateObject private var bridge = JsBridgeBrowserBridge()
    @State private var isSyncing = false

    private var navTitle: String { title.isEmpty ? localized("浏览器") : title }

    var body: some View {
        if hidesToolbar {
            contentView
        } else {
            NavigationStack {
                contentView
                    .navigationTitle(navTitle)
                    .toolbarTitleDisplayMode(.inline)
                    .toolbar {
                        ToolbarItem(placement: .navigationBarLeading) {
                            Button {
                                // XHR-based login can set cookies after the last
                                // navigation finished. Persist that final jar even
                                // on cancellation; nil still tells source JS that
                                // the browser was dismissed without confirmation.
                                isSyncing = true
                                guard let sync = bridge.syncCookiesAndDismiss else {
                                    onDismiss(nil)
                                    return
                                }
                                sync { _ in onDismiss(nil) }
                            } label: {
                                Label(localized("取消"), systemImage: "xmark")
                                    .labelStyle(.iconOnly)
                            }
                            .accessibilityLabel(localized("取消"))
                            .disabled(isSyncing)
                        }
                        // The page's own address, after its redirects and the reader's taps:
                        // what a reader debugging the source's rules pastes into 调试规则.
                        ToolbarItem(placement: .navigationBarTrailing) {
                            Button {
                                SourceWebPage.copy(bridge.currentURL?.absoluteString ?? urlString)
                            } label: {
                                Label(localized("复制网址"), systemImage: "doc.on.doc")
                                    .labelStyle(.iconOnly)
                            }
                            .accessibilityLabel(localized("复制网址"))
                        }
                        ToolbarItem(placement: .navigationBarTrailing) {
                            Button {
                                bridge.reload?()
                            } label: {
                                Label(localized("网页：重新整理"), systemImage: "arrow.clockwise")
                                    .labelStyle(.iconOnly)
                            }
                            .accessibilityLabel(localized("网页：重新整理"))
                            .disabled(isSyncing)
                        }
                        ToolbarItem(placement: .navigationBarTrailing) {
                            if isSyncing {
                                ProgressView().scaleEffect(0.85)
                            } else {
                                Button {
                                    confirm()
                                } label: {
                                    Label(localized("完成"), systemImage: "checkmark")
                                        .labelStyle(.iconOnly)
                                }
                                .accessibilityLabel(localized("完成"))
                            }
                        }
                    }
                    .onChange(of: bridge.challengeCleared) { _, cleared in
                        if cleared, !isSyncing { confirm() }
                    }
            }
        }
    }

    /// ✓: keep the page's cookies and hand its HTML back.
    private func confirm() {
        isSyncing = true
        guard let sync = bridge.syncCookiesAndDismiss else {
            onDismiss(nil)
            return
        }
        sync { body in onDismiss(body) }
    }

    private var contentView: some View {
        ZStack(alignment: .top) {
            JsBridgeBrowserRepresentable(
                urlString: urlString,
                initialHTML: initialHTML,
                injectedJavaScript: injectedJavaScript,
                sourceRunHandler: sourceRunHandler,
                sourceConfigurationUpdateHandler: sourceConfigurationUpdateHandler,
                bridge: bridge,
                initialRequest: initialRequest,
                userAgent: userAgent,
                finishesWhenChallengeClears: finishesWhenChallengeClears,
                transparentBackground: transparentBackground,
                customCSSScript: customCSSScript,
                grabsComments: grabsComments,
                onCommentsGrabbed: onCommentsGrabbed
            )
                .edgesIgnoringSafeArea(hidesToolbar ? .all : [])

            // Full-screen state until the page has drawn its first content. Not lifted at
            // commit: until the page paints, WebKit shows its own white, which is all a 段评
            // sheet over a dark reader showed while the page's synchronous `java.ajax` ran
            // (#21, #54, #55).
            switch bridge.phase {
            case .loading, .committed:
                loadingOverlay
            case .failed:
                errorOverlay
            case .painted, .finished:
                EmptyView()
            }

            // Safari-style thin progress bar across the top while loading.
            if bridge.phase != .failed, bridge.phase != .finished, bridge.progress < 1 {
                ProgressView(value: max(bridge.progress, 0.03))
                    .progressViewStyle(.linear)
                    .tint(DSColor.accent)
                    .transition(.opacity)
            }
        }
        .animation(DSAnimation.fast, value: bridge.phase)
        .animation(DSAnimation.fast, value: bridge.progress)
    }

    // MARK: - Overlays

    /// 透明模式下载入／错误层不能盖一块不透明底色，否则面板在页面绘出前仍是白的。
    private var overlayBackdrop: some View {
        Group {
            if transparentBackground {
                Color.clear
            } else {
                DSColor.background
            }
        }
        .ignoresSafeArea()
    }

    private var loadingOverlay: some View {
        ZStack {
            overlayBackdrop
            VStack(spacing: DSSpacing.md) {
                ProgressView()
                    .controlSize(.large)
                Text(localized("载入中…"))
                    .font(DSFont.subheadline)
                    .foregroundStyle(DSColor.textSecondary)
            }
        }
        .transition(.opacity)
    }

    private var errorOverlay: some View {
        ZStack {
            overlayBackdrop
            VStack(spacing: DSSpacing.md) {
                Image(systemName: "wifi.exclamationmark")
                    .font(DSFont.largeTitle)
                    .foregroundStyle(DSColor.textSecondary)
                Text(localized("载入失败"))
                    .font(DSFont.headline)
                    .foregroundStyle(DSColor.textPrimary)
                if let detail = bridge.errorText, !detail.isEmpty {
                    Text(detail)
                        .font(DSFont.caption)
                        .foregroundStyle(DSColor.textSecondary)
                        .multilineTextAlignment(.center)
                }
                Button(localized("重试")) { bridge.reload?() }
                    .buttonStyle(.bordered)
                    .tint(DSColor.accent)
            }
            .padding(DSSpacing.lg)
        }
        .transition(.opacity)
    }
}

/// Presents a decoded paragraph-review target. Source-authored pages keep the same native
/// sheet/browser shell as ordinary review URLs, but receive the `window.run` bridge they need
/// to call back into their own shared Legado runtime.
struct LegadoReviewBrowserView: View {
    let target: ReaderHTMLUtilities.ReviewTarget
    /// 弹出前由呈现方（ReaderView）抓下的书页截图（已预模糊）。
    /// 面板自己把它铺在最底层当玻璃：任何档位、任何呈现路径都稳定，
    /// 半屏/全屏同一张图——这是「全屏白板」的最终解法。
    var backdrop: UIImage?
    let onDismiss: (_ body: String?) -> Void
    @State private var configurationJSON: String
    /// 从书源段评页里抓到的评论。有值就画原生卡片，没有就显示书源页面。
    @State private var grabbed: GrabbedCommentPage?
    /// 右上角小地球的「临时切换」。nil = 跟随设置里的默认显示模式；
    /// 有值 = 用户这一次手动切过，只影响当前面板，不写回设置。
    @State private var sourcePageOverride: Bool?
    /// 抓取超时后停在玻璃提示态（绝不自动回落书源原网页），可手动重试或切原网页。
    @State private var hasTimedOut = false
    /// 重试计数：变化即重启 4 秒超时计时（.task(id:) 随之重跑）。
    @State private var retryToken = 0
    /// 面板底色的浓淡由外观 › 界面效果 的滑杆决定，拖动即时生效。
    private var settings: GlobalSettings { .shared }
    /// 设置页的「显示模式」决定默认显示原生卡片还是书源原网页。
    private var nativeStyle: NativeReviewPanelStyleStore { .shared }
    private var effectiveShowsSourcePage: Bool {
        sourcePageOverride ?? (nativeStyle.displayMode == .web)
    }
    @Environment(\.colorScheme) private var colorScheme

    init(
        target: ReaderHTMLUtilities.ReviewTarget,
        backdrop: UIImage? = nil,
        onDismiss: @escaping (_ body: String?) -> Void
    ) {
        self.target = target
        self.backdrop = backdrop
        self.onDismiss = onDismiss
        _configurationJSON = State(initialValue: target.sourceBrowserPage?.configurationJSON ?? "")
    }

    /// 与孤岛（Cay）一致：书源给的段评页**原样显示**，不重排、不重绘。
    /// `IslandReviewPanel` 只负责让底板透明和限制图片宽度；
    /// 「段评样式」里的自定义 CSS 默认关闭，打开后也只改字号行距颜色。
    private var customCSSScript: String {
        let css = ReviewPanelCSSBridge.browserCSS(
            ReviewPanelStyleStore.shared.activeCSS(),
            isNight: colorScheme == .dark
        )
        return IslandReviewPanel.installScript(
            isNight: colorScheme == .dark,
            title: localized("段评"),
            customCSS: css
        )
    }

    var body: some View {
        ZStack {
            // ⓪ 玻璃底：弹出前拍下的模糊书页，铺在最底层。半屏/全屏同一张图。
            ReviewPanelBackdropLayer(backdrop: backdrop)

            // ① 书源网页常驻在玻璃底之上，绝不因「抓到评论」被移出视图树。
            //    旧实现用 if/else 切换，抓到数据的瞬间 WKWebView 被销毁，
            //    页面里的 setTimeout / MutationObserver / 楼中楼展开请求全部停摆
            //    —— 这正是「新界面楼中楼点不了、切回旧版加载完再切回来才显示」的根因。
            //    常驻后 JS 持续运行，增量抓取不断回调 onCommentsGrabbed 刷新卡片。
            sourceWebView
                // 0.01 而非 0：彻底透明在个别系统上会被判为「不可见」而节流 JS 定时器。
                .opacity(displayMode == .web ? 1 : 0.01)
                .allowsHitTesting(displayMode == .web)

            // ② 抓取中：毛玻璃占位盖住网页，杜绝「先闪一下旧页面再跳进新界面」。
            if displayMode == .loading {
                loadingPlaceholder
                    .transition(.opacity)
            }

            // ②′ 抓取超时：脸不变，仍是同一块玻璃，只是换上提示+重试。
            //    绝不自动切回书源原网页——那块白底网页就是「加载慢闪旧版」的根源。
            //    WebView 在玻璃底下继续跑抓取脚本，一旦抓到数据会自动跳成原生卡片。
            if displayMode == .timedOut {
                timedOutPlaceholder
                    .transition(.opacity)
            }

            // ③ 抓到评论：原生玻璃卡片盖在最上层。
            if displayMode == .native, let grabbed {
                NativeReviewPanelView(
                    title: grabbed.panelTitle(
                        fallback: target.title.isEmpty ? localized("段评") : target.title
                    ),
                    paragraphLabel: nil,
                    comments: grabbed.items
                )
                .padding(.top, 6)
                .transition(.opacity)
            }
        }
        .animation(.easeInOut(duration: 0.22), value: displayMode)
        .task(id: retryToken) {
            // 超时兜底：抓不到就停在玻璃提示态（脸不变），WebView 继续在
            // 玻璃底下抓——一旦抓到，grabbed 非空自动跳成原生卡片。
            try? await Task.sleep(for: .seconds(4))
            if grabbed == nil { hasTimedOut = true }
        }
        .overlay(alignment: .topTrailing) {
            if grabbed != nil || hasTimedOut {
                Button {
                    withAnimation(.easeInOut(duration: 0.18)) {
                        sourcePageOverride = !effectiveShowsSourcePage
                    }
                } label: {
                    Image(systemName: effectiveShowsSourcePage ? "text.bubble" : "globe")
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(DSColor.textSecondary)
                        .padding(7)
                        .background(.ultraThinMaterial, in: Circle())
                        .overlay(
                            Circle().strokeBorder(Color.white.opacity(0.25), lineWidth: 0.5)
                        )
                }
                .buttonStyle(.plain)
                .padding(.top, 10)
                .padding(.trailing, 12)
                .accessibilityLabel(effectiveShowsSourcePage ? localized("用卡片显示") : localized("显示原网页"))
            }
        }
        // 面板玻璃由 ZStack 最底层的 ReviewPanelBackdropLayer 自己画好：
        // 系统实时材质（逐帧对齐）+ 预模糊截图兜底，双层保险，任何档位都不露底。
        // presentationBackground 清空：系统不再另画一层不透明 chrome 盖在玻璃上
        // （那层 chrome 正是全屏档白板的来源之一）。
        .presentationBackground { Color.clear }
        .presentationBackgroundInteraction(.enabled(upThrough: .large))
        .presentationDetents(presentationConfiguration.detents)
        .presentationDragIndicator(
            presentationConfiguration.skipCollapsed ? .hidden : .visible
        )
        .interactiveDismissDisabled(!presentationConfiguration.isHideable)
        .presentationCornerRadius(
            presentationConfiguration.expandedCornersRadius.map { CGFloat($0) }
        )
    }

    /// 三种显示状态。枚举自动符合 Equatable，可直接驱动 .animation(value:)。
    private enum DisplayMode: Equatable {
        case loading
        case native
        case web
        case timedOut
    }

    private var displayMode: DisplayMode {
        if effectiveShowsSourcePage { return .web }
        if grabbed != nil { return .native }
        if hasTimedOut { return .timedOut }
        return .loading
    }

    /// 书源段评网页。抽成计算属性是为了让它在 ZStack 里只存在一份、常驻。
    @ViewBuilder
    private var sourceWebView: some View {
        if let page = target.sourceBrowserPage {
            JsBridgeBrowserView(
                urlString: page.baseURL,
                title: target.title,
                hidesToolbar: ParagraphReviewBrowserPresentationPolicy.hidesToolbar,
                initialHTML: page.html,
                initialRequest: target.browserRequest,
                injectedJavaScript: page.injectedJavaScript,
                sourceRunHandler: { script in
                    try await LegadoReviewActionRunner.shared.runSourcePageScript(
                        script,
                        sourceURL: page.sourceURL,
                        actionContext: page.actionContext
                    )
                },
                sourceConfigurationUpdateHandler: { configurationJSON = $0 },
                transparentBackground: true,
                customCSSScript: customCSSScript,
                grabsComments: true,
                onCommentsGrabbed: { page in
                    if !page.items.isEmpty, page != grabbed,
                       page.items.count >= (grabbed?.items.count ?? 0) {
                        grabbed = page
                    }
                },
                onDismiss: onDismiss
            )
        } else {
            JsBridgeBrowserView(
                urlString: target.url,
                title: target.title,
                hidesToolbar: ParagraphReviewBrowserPresentationPolicy.hidesToolbar,
                initialRequest: target.browserRequest,
                transparentBackground: true,
                customCSSScript: customCSSScript,
                grabsComments: true,
                onCommentsGrabbed: { page in
                    if !page.items.isEmpty, page != grabbed,
                       page.items.count >= (grabbed?.items.count ?? 0) {
                        grabbed = page
                    }
                },
                onDismiss: onDismiss
            )
        }
    }

    /// 加载占位：一层薄毛玻璃 + 极小的进度指示，盖住尚未读好的网页。
    private var loadingPlaceholder: some View {
        VStack(spacing: 10) {
            ProgressView()
                .controlSize(.small)
                .tint(DSColor.textSecondary)
            Text(localized("正在读取评论…"))
                .font(.system(size: 12))
                .foregroundStyle(DSColor.textSecondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        // 不再垫白色实底：玻璃底（ReviewPanelBackdropLayer）已经是完整的面板
        // 外观，加载态直接透出同一块玻璃——加载中/加载完是同一张脸，
        // 杜绝「加载慢时闪现一块实心旧面板」的观感。
    }

    /// 超时占位：与加载态同一块玻璃、同一张脸，只把 spinner 换成提示与重试。
    /// 旧实现超时后回落显示书源原网页——书源网页自带白底，整块盖住实时玻璃，
    /// 看起来就是「旧版面板跳出来一会」。现在超时后脸不变，后台继续抓，
    /// 抓到评论自动切原生卡片；想看原网页用右上角小地球手动切。
    private var timedOutPlaceholder: some View {
        VStack(spacing: 10) {
            Image(systemName: "hourglass")
                .font(.system(size: 20, weight: .light))
                .foregroundStyle(DSColor.textSecondary)
            Text(localized("评论还在路上，稍等片刻"))
                .font(.system(size: 12))
                .foregroundStyle(DSColor.textSecondary)
            Button {
                withAnimation(.easeInOut(duration: 0.22)) {
                    hasTimedOut = false
                    retryToken += 1
                }
            } label: {
                Text(localized("重新加载"))
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(DSColor.textPrimary)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 6)
                    .background(.ultraThinMaterial, in: Capsule())
                    .overlay(Capsule().strokeBorder(Color.white.opacity(0.25), lineWidth: 0.5))
            }
            .buttonStyle(.plain)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var presentationConfiguration: SourceBrowserPresentationConfiguration {
        SourceBrowserPresentationConfiguration(
            json: configurationJSON
        )
    }
}

// MARK: - JsBridgeBrowserBridge

@MainActor
final class JsBridgeBrowserBridge: @MainActor ObservableObject {
    enum Phase {
        case loading
        /// The page's document has replaced the last one, but nothing of it is drawn yet.
        case committed
        /// The parsed document has been drawn; subresources may still be loading.
        case painted
        case finished
        case failed
    }

    var syncCookiesAndDismiss: ((@escaping (String?) -> Void) -> Void)?
    var reload: (() -> Void)?

    @Published var progress: Double = 0
    /// The web view's current page; nil until its first navigation starts.
    @Published var currentURL: URL?
    @Published var phase: Phase = .loading
    @Published var errorText: String?
    /// A Cloudflare challenge on the page has cleared (see `finishesWhenChallengeClears`).
    @Published var challengeCleared = false
}

// MARK: - UIViewRepresentable

struct JsBridgeBrowserRepresentable: UIViewRepresentable {
    let urlString: String
    let initialHTML: String?
    let injectedJavaScript: String
    let sourceRunHandler: ((String) async throws -> String)?
    let sourceConfigurationUpdateHandler: ((String) -> Void)?
    let bridge: JsBridgeBrowserBridge
    var initialRequest: URLRequest? = nil
    var userAgent: String? = nil
    var finishesWhenChallengeClears = false
    var transparentBackground = false
    var customCSSScript = ""
    var grabsComments = false
    var onCommentsGrabbed: ((GrabbedCommentPage) -> Void)? = nil

    static let sourceJavaPromptName = SourceWebUIDelegate.sourceBridgePromptName

    /// 段评面板透出阅读器背景：页面底色、以及铺满整个视口的「画布层」一律清空。
    /// 只清底色，不动字色与卡片内容——页面自己的文字照样读得到。
    static let transparentBackgroundScript = """
    (function () {
        var STYLE_ID = '__yuedu_transparent__';
        function installStyle() {
            if (document.getElementById(STYLE_ID)) return;
            var style = document.createElement('style');
            style.id = STYLE_ID;
            // 玻璃面板要整块透：页面一切容器的**实心底色**都要清掉——断层
            // （面板某一段突然变成实心白板）的根源就是页面把白底刷在评论
            // 列表容器、卡片、甚至后来 ajax 插进来的节点上。
            // 教训（孤岛/Cay 的回退实验）：`background-image` 与 `box-shadow`
            // 不能清 —— 头像、等级标签、装饰条全靠 background-image 画，
            // 阴影清掉卡片层次就没了，那是「把页面拆了」。这里只动底色。
            // 页面自己带 !important 的白底比 stylesheet 强，由下面的行内
            // 反盖去处理。
            style.textContent = [
                'html,body{background:transparent !important;background-color:transparent !important;}',
                'body *:not(img):not(video):not(canvas):not(svg):not(picture):not(iframe){background-color:transparent !important;}',
                'body::before,body::after{background-color:transparent !important;}'
            ].join('');
            (document.head || document.documentElement).appendChild(style);
        }
        var SKIP = { img: 1, video: 1, canvas: 1, svg: 1, picture: 1, source: 1, iframe: 1 };
        function isTransparent(color) {
            return !color || color === 'transparent' || color === 'rgba(0, 0, 0, 0)';
        }
        // 对单个元素按计算样式判定：实心底色就写行内 !important 盖掉。
        // 行内 !important 是级联里的最强项，页面自己的 !important 规则也打不过它。
        function clearOpaque(el) {
            if (!el || el.nodeType !== 1 || el.dataset.yueduBgCleared === '1') return;
            var tag = (el.tagName || '').toLowerCase();
            if (SKIP[tag]) return;
            var computed;
            try { computed = window.getComputedStyle(el); } catch (error) { return; }
            if (!computed || isTransparent(computed.backgroundColor)) return;
            el.style.setProperty('background-color', 'transparent', 'important');
            el.dataset.yueduBgCleared = '1';
        }
        function clearSubtree(root) {
            if (!root || root.nodeType !== 1) return;
            clearOpaque(root);
            var nodes = root.querySelectorAll ? root.querySelectorAll('*') : [];
            for (var i = 0; i < nodes.length; i++) clearOpaque(nodes[i]);
        }
        // 行内 style 直接写着 !important 底色的：stylesheet 永远打不过，
        // 不管计算结果如何都反盖一层行内 transparent（后写的行内胜出）。
        function sweepInlineImportant() {
            if (!document.body) return;
            var nodes = document.body.querySelectorAll('[style]');
            for (var i = 0; i < nodes.length; i++) {
                var el = nodes[i];
                if (SKIP[(el.tagName || '').toLowerCase()]) continue;
                var raw = el.getAttribute('style') || '';
                if (raw.indexOf('important') === -1) continue;
                if (raw.indexOf('background') === -1 && raw.indexOf('bg-color') === -1) continue;
                el.style.setProperty('background-color', 'transparent', 'important');
            }
        }
        function run() {
            installStyle();
            if (!document.body) return;
            sweepInlineImportant();
            clearSubtree(document.body);
        }
        run();
        document.addEventListener('DOMContentLoaded', run, { once: true });
        window.addEventListener('load', function () {
            run();
            setTimeout(run, 120);
            setTimeout(run, 600);
        });
        // 段评列表多半是 java.ajax 回来之后才插进 DOM，也可能过几秒再改样式：
        // 监听器常驻，DOM 增删与 style/class 属性变化都盯住，只对变动到的
        // 节点做增量清理，合并到同一帧执行。不再到点 disconnect。
        var queued = false;
        function schedule() {
            if (queued) return;
            queued = true;
            requestAnimationFrame(function () {
                queued = false;
                try { run(); } catch (error) {}
            });
        }
        try {
            var observer = new MutationObserver(function (records) {
                for (var i = 0; i < records.length; i++) {
                    var record = records[i];
                    if (record.type === 'attributes') {
                        clearOpaque(record.target);
                    } else {
                        for (var j = 0; j < record.addedNodes.length; j++) {
                            if (record.addedNodes[j].nodeType === 1) clearSubtree(record.addedNodes[j]);
                        }
                    }
                }
                schedule();
            });
            observer.observe(document.documentElement, {
                childList: true,
                subtree: true,
                attributes: true,
                attributeFilter: ['style', 'class']
            });
        } catch (error) {}
    })();
    """

    static func sourcePageBootstrap(injectedJavaScript: String) -> String {
        let unavailableMessage = javaScriptStringLiteral(
            localized("段评执行环境不可用")
        )
        return """
        window.java = window.java || {};
        window.cache = window.cache || {};
        window.source = window.source || {};
        (function () {
            if (window.java.__yueduSourceNetworkInstalled) return;
            function callNative(method, args) {
                var payload = JSON.stringify({
                    method: method,
                    arguments: Array.prototype.slice.call(args)
                });
                var value = window.prompt('\(sourceJavaPromptName)', payload);
                if (value === null) {
                    throw new Error(\(unavailableMessage) + ': java.' + method);
                }
                return value;
            }
            ['ajax', 'get', 'post', 'head', 'connect', 'upConfig'].forEach(function (method) {
                Object.defineProperty(window.java, method, {
                    configurable: true,
                    value: function () { return callNative(method, arguments); }
                });
            });
            window.java.__yueduSourceNetworkInstalled = true;
        })();
        window.run = function (script) {
            return window.webkit.messageHandlers.\(Coordinator.sourceRunMessageName)
                .postMessage(String(script == null ? '' : script));
        };
        \(injectedJavaScript)
        """
    }

    private static func javaScriptStringLiteral(_ value: String) -> String {
        guard let data = try? JSONEncoder().encode(value),
              let encoded = String(data: data, encoding: .utf8) else {
            return "\"\""
        }
        return encoded
    }

    /// Android exposes `upConfig` on `WebJsExtensions`, not on the parser's
    /// `JsExtensions`. A source-authored page calls it to update the active
    /// four-argument `showBrowser` sheet configuration (for example, resizing a
    /// comments panel after it has measured its content).
    static func sourceConfigurationJSON(forPromptPayload payload: String) throws -> String? {
        guard payload.utf8.count <= 256 * 1024,
              let data = payload.data(using: .utf8),
              let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let method = object["method"] as? String else {
            throw sourcePageBridgeError()
        }
        guard method == "upConfig" else { return nil }
        guard let arguments = object["arguments"] as? [Any],
              arguments.count == 1,
              let configurationJSON = arguments[0] as? String,
              configurationJSON.utf8.count <= 64 * 1024,
              let configurationData = configurationJSON.data(using: .utf8),
              (try? JSONSerialization.jsonObject(with: configurationData)) is [String: Any] else {
            throw sourcePageBridgeError()
        }
        return configurationJSON
    }

    private static func sourcePageBridgeError() -> NSError {
        NSError(
            domain: "SourcePageJavaBridge",
            code: 1,
            userInfo: [NSLocalizedDescriptionKey: localized("段评执行环境不可用")]
        )
    }

    /// Turns a bounded WebView request into source-runtime JS. Only Android's browser-page
    /// network surface is accepted; the method name is never interpolated before allowlisting,
    /// and argument JSON is re-encoded before it reaches JavaScriptCore. The evaluated call then
    /// travels through the same `ModernParserBridge` / `BookSourceSession` request pipeline as
    /// chapter parsing, preserving source headers, login headers, cookies, and AnalyzeUrl options.
    static func sourceJavaScript(forPromptPayload payload: String) throws -> String {
        guard payload.utf8.count <= 256 * 1024,
              let data = payload.data(using: .utf8),
              let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let method = object["method"] as? String,
              ["ajax", "get", "post", "head", "connect"].contains(method),
              let arguments = object["arguments"] as? [Any],
              !arguments.isEmpty,
              arguments.count <= 4,
              arguments[0] is String,
              JSONSerialization.isValidJSONObject(arguments),
              let argumentsData = try? JSONSerialization.data(
                withJSONObject: arguments,
                options: [.withoutEscapingSlashes]
              ),
              let argumentsJSON = String(data: argumentsData, encoding: .utf8) else {
            throw sourcePageBridgeError()
        }

        let call = "java.\(method).apply(java, \(argumentsJSON))"
        if method == "head" {
            return """
            (function () {
                var response = \(call);
                var headers = response && typeof response.headers === 'function'
                    ? response.headers() : response;
                if (!headers) return '{}';
                if (typeof headers.keySet === 'function' && typeof headers.get === 'function') {
                    var object = {};
                    var keys = headers.keySet();
                    for (var i = 0; i < keys.length; i++) object[String(keys[i])] = headers.get(keys[i]);
                    return JSON.stringify(object);
                }
                return JSON.stringify(headers);
            })()
            """
        }
        if method == "connect" {
            return """
            (function () {
                var response = \(call);
                if (response == null) return '';
                return typeof response.toString === 'function'
                    ? String(response.toString()) : String(response);
            })()
            """
        }
        return """
        (function () {
            var response = \(call);
            if (response == null) return '';
            if (typeof response.body === 'function') {
                var body = response.body();
                return String(body == null ? '' : body);
            }
            return String(response);
        })()
        """
    }

    func makeUIView(context: Context) -> WKWebView {
        // Let JavaScript-driven input focus raise the keyboard (SMS 验证码 fields focus a hidden
        // <input> on tap; the 番茄 验证码 step couldn't open the keyboard otherwise). One-time,
        // process-wide WKContentView patch.
        _ = WKWebView.patchKeyboardFocusOnce

        let config = WKWebViewConfiguration()
        config.websiteDataStore = .default()
        let prefs = WKWebpagePreferences()
        prefs.allowsContentJavaScript = true
        prefs.preferredContentMode = SourceWebIdentity.contentMode(desktop: false)
        config.defaultWebpagePreferences = prefs
        // A captcha/OAuth widget that opens itself (not from a tap) is blocked before
        // the UI delegate is ever consulted unless script-opened windows are allowed.
        config.preferences.javaScriptCanOpenWindowsAutomatically = true
        context.coordinator.clipboardBridge.install(in: config.userContentController)
        context.coordinator.sourceRunHandler = sourceRunHandler
        context.coordinator.sourceConfigurationUpdateHandler = sourceConfigurationUpdateHandler
        if sourceRunHandler != nil {
            context.coordinator.uiDelegate.sourceBridgePromptHandler = { [weak coordinator = context.coordinator] payload, completion in
                guard let coordinator else {
                    completion(nil)
                    return
                }
                coordinator.handleSourceJavaPrompt(payload, completion: completion)
            }
            config.userContentController.addScriptMessageHandler(
                context.coordinator,
                contentWorld: .page,
                name: Coordinator.sourceRunMessageName
            )
            let bootstrap = Self.sourcePageBootstrap(injectedJavaScript: injectedJavaScript)
            config.userContentController.addUserScript(
                WKUserScript(source: bootstrap, injectionTime: .atDocumentStart, forMainFrameOnly: true)
            )
            // Legado 的 preloadJs 在页面加载完（onPageFinished）后才执行；自绘面板书源
            // （番茄 APP 源等）靠 `document.write` 清空空壳页重写整张面板。documentStart
            // 注入时解析器还没读完空壳，write 出的内容只是追加进流，部分面板依赖「已
            // 到文档尾部」的语义时就会渲染失败 —— 表现为面板一片空白。对这类脚本再
            // 在 documentEnd 补一次：此时 write 清空文档完整重写，与 Legado 行为一致；
            // 幂等的面板脚本重跑一遍无副作用。
            if injectedJavaScript.contains("document.write") {
                config.userContentController.addUserScript(
                    WKUserScript(source: bootstrap, injectionTime: .atDocumentEnd, forMainFrameOnly: true)
                )
            }
        }
        // In a world of its own, out of the page's reach, as every page here needs it.
        config.userContentController.addScriptMessageHandler(
            context.coordinator,
            contentWorld: .defaultClient,
            name: Coordinator.firstPaintMessageName
        )
        config.userContentController.addUserScript(WKUserScript(
            source: Coordinator.firstPaintScript,
            injectionTime: .atDocumentEnd,
            forMainFrameOnly: true,
            in: .defaultClient
        ))

        let wv = WKWebView(frame: .zero, configuration: config)
        if transparentBackground {
            // 段评面板盖在阅读器上：WebView 自己那层白底不清掉就会整片不透明。
            wv.isOpaque = false
            wv.backgroundColor = .clear
            wv.layer.isOpaque = false
            wv.scrollView.isOpaque = false
            wv.scrollView.backgroundColor = .clear
            wv.scrollView.layer.isOpaque = false
            wv.underPageBackgroundColor = .clear
            config.userContentController.addUserScript(WKUserScript(
                source: Self.transparentBackgroundScript,
                injectionTime: .atDocumentStart,
                forMainFrameOnly: true
            ))
        }
        // 段评抓取：脚本在 documentEnd 跑（页面自己的渲染已经完成），
        // 之后靠 MutationObserver 跟着「滚动加载更多」补抓。
        if grabsComments {
            context.coordinator.commentsGrabHandler = onCommentsGrabbed
            config.userContentController.addScriptMessageHandler(
                context.coordinator,
                contentWorld: .page,
                name: ReviewCommentGrabber.messageHandlerName
            )
            config.userContentController.addUserScript(WKUserScript(
                source: ReviewCommentGrabber.script,
                injectionTime: .atDocumentEnd,
                forMainFrameOnly: true
            ))
        }
        // 段评与互动样式：排在透明背景脚本之后注入，样式表在运行时追加到 head
        // 末尾，同优先级下后写的 !important 规则盖得住透明脚本清底色的规则。
        if !customCSSScript.isEmpty {
            config.userContentController.addUserScript(WKUserScript(
                source: customCSSScript,
                injectionTime: .atDocumentStart,
                forMainFrameOnly: true
            ))
        }
        SourceWebIdentity.apply(desktop: false, to: wv)
        if let userAgent {
            wv.customUserAgent = userAgent
        }
        context.coordinator.finishesWhenChallengeClears = finishesWhenChallengeClears
        wv.navigationDelegate = context.coordinator
        // `uiDelegate` is weak — the Coordinator owns it. Without it the page's
        // `window.open` / `alert` / `confirm` are dropped without a trace.
        wv.uiDelegate = context.coordinator.uiDelegate
        context.coordinator.webView = wv
        context.coordinator.bridge = bridge

        // Drive the progress bar from the live load estimate.
        context.coordinator.progressObservation = wv.observe(\.estimatedProgress, options: [.new]) { [weak bridge] web, _ in
            DispatchQueue.main.async { [bridge] in bridge?.progress = web.estimatedProgress }
        }
        context.coordinator.urlObservation = wv.observe(\.url, options: [.new]) { [weak bridge] web, _ in
            DispatchQueue.main.async { [bridge] in bridge?.currentURL = web.url }
        }

        context.coordinator.installKeyboardReFocusWorkaround()

        let coordinator = context.coordinator
        bridge.syncCookiesAndDismiss = { [weak coordinator] completion in
            guard let wv = coordinator?.webView else { completion(nil); return }
            coordinator?.syncCookiesAndDismiss(from: wv, completion: completion)
        }
        bridge.reload = { [weak coordinator, weak bridge] in
            guard let coordinator, let wv = coordinator.webView else { return }
            bridge?.phase = .loading
            bridge?.errorText = nil
            bridge?.progress = 0
            coordinator.loadInitial(
                urlString: urlString,
                html: initialHTML,
                request: initialRequest,
                in: wv
            )
        }

        context.coordinator.loadInitial(urlString: urlString, html: initialHTML, request: initialRequest, in: wv)
        return wv
    }

    /// WebView 现在常驻不销毁，body 每次重算都要把最新的抓取回调同步给
    /// coordinator —— 否则楼中楼增量结果会写进首次创建时的旧闭包快照。
    func updateUIView(_ uiView: WKWebView, context: Context) {
        context.coordinator.commentsGrabHandler = onCommentsGrabbed
        // 段评模式（transparentBackground）下，sheet 半屏也要能往下翻评论：
        // 系统默认 prefersScrollingExpandsWhenScrolledToEdge = true，网页的
        // scrollView 停在顶部时，上滑手势被优先识别成「展开面板」，列表在
        // 半屏里滚不动，只能先拉到全屏。关掉后半屏内上滑就是纯滚动，
        // 展开只靠把手 —— 与起点式段评面板的手感一致。
        // SwiftUI 的 .sheet 没有对应参数，只能在 webView 挂上 window 后沿
        // presented 链找到末端的 sheetPresentationController 设置；设置是
        // 幂等的，每次 SwiftUI 更新重跑一次无妨。UIKit 呈现路径（段评面板）
        // 已在 CoreTextPageView 直接设置同一项。
        if transparentBackground {
            Self.disableScrollingExpandsSheet(for: uiView)
        }
    }

    /// 沿 presented 链找到末端控制器，把它的 sheet 改成「滚动不展开」。
    /// 末端控制器就是当前这条 sheet —— 段评面板不会再 present 别的东西。
    static func disableScrollingExpandsSheet(for webView: WKWebView) {
        DispatchQueue.main.async {
            guard var controller = webView.window?.rootViewController else { return }
            while let presented = controller.presentedViewController {
                controller = presented
            }
            controller.sheetPresentationController?.prefersScrollingExpandsWhenScrolledToEdge = false
        }
    }
    func makeCoordinator() -> Coordinator { Coordinator() }

    static func dismantleUIView(_ uiView: WKWebView, coordinator: Coordinator) {
        uiView.configuration.userContentController.removeScriptMessageHandler(
            forName: Coordinator.sourceRunMessageName,
            contentWorld: .page
        )
        uiView.configuration.userContentController.removeScriptMessageHandler(
            forName: Coordinator.firstPaintMessageName,
            contentWorld: .defaultClient
        )
        uiView.configuration.userContentController.removeScriptMessageHandler(
            forName: ReviewCommentGrabber.messageHandlerName,
            contentWorld: .page
        )
        coordinator.clipboardBridge.remove(from: uiView.configuration.userContentController)
    }

    final class Coordinator: NSObject, WKNavigationDelegate, WKScriptMessageHandlerWithReply {
        static let sourceRunMessageName = "yueduSourceRun"
        static let firstPaintMessageName = "yueduFirstPaint"
        /// Posts once the parsed document has been drawn. It runs when parsing ends, after the
        /// page's own scripts, a synchronous `java.ajax` among them; the first frame callback
        /// comes before the frame that draws the document, the second before the next one, by
        /// when the first has been drawn.
        static let firstPaintScript = """
        requestAnimationFrame(function () {
            requestAnimationFrame(function () {
                window.webkit.messageHandlers.\(firstPaintMessageName).postMessage('');
            });
        });
        """

        weak var webView: WKWebView?
        weak var bridge: JsBridgeBrowserBridge?
        var progressObservation: NSKeyValueObservation?
        var urlObservation: NSKeyValueObservation?
        var sourceRunHandler: ((String) async throws -> String)?
        /// 段评抓取结果回调；`grabsComments` 关闭时为 nil。
        var commentsGrabHandler: ((GrabbedCommentPage) -> Void)?
        var sourceConfigurationUpdateHandler: ((String) -> Void)?
        var finishesWhenChallengeClears = false
        /// A page of this navigation history was a Cloudflare challenge.
        private(set) var sawChallenge = false
        /// Strongly held: `WKWebView.uiDelegate` is weak.
        let uiDelegate = SourceWebUIDelegate()
        let clipboardBridge = SourceWebClipboardBridge()
        /// `nonisolated(unsafe)`：deinit 是非隔离的，需要读到要摘掉的通知令牌；
        /// `removeObserver` 本身线程安全，写入只发生在主 actor 的安装方法里。
        nonisolated(unsafe) private var keyboardHideObserver: NSObjectProtocol?

        /// WKWebView keeps the tapped `<input>` as `document.activeElement` after the keyboard is
        /// dismissed, so tapping it again fires no new focus event and the keyboard never returns
        /// (e.g. you collapse the 番茄 验证码 keyboard, then can't reopen it). Blur the active
        /// element once the keyboard is fully gone so the next tap is a fresh focus.
        func installKeyboardReFocusWorkaround() {
            keyboardHideObserver = NotificationCenter.default.addObserver(
                forName: UIResponder.keyboardDidHideNotification,
                object: nil,
                queue: .main
            ) { [weak self] _ in
                // Delivered on `.main` (the queue above).
                MainActor.assumeIsolated {
                    self?.webView?.evaluateJavaScript(
                        "if (document.activeElement && document.activeElement.blur) { document.activeElement.blur(); }",
                        completionHandler: nil
                    )
                }
            }
        }

        // 刻意不用 `isolated deinit`：deinit-on-executor 是 iOS 18 起才有的运行时能力，
        // 17.0 上只能走 back-deployed 的 task 路径，sheet 收起时会在 swift_task_dealloc
        // 的分配器断言里 abort（SIGABRT，1.7 build13 崩溃日志即此）。摘通知与线程无关。
        deinit {
            if let keyboardHideObserver {
                NotificationCenter.default.removeObserver(keyboardHideObserver)
            }
        }

        func setPhase(_ phase: JsBridgeBrowserBridge.Phase, error: String? = nil) {
            DispatchQueue.main.async { [weak self] in
                guard let bridge = self?.bridge else { return }
                // A first paint counts only for the page that committed: not one that finished
                // before its frames came round, nor the last page's, posted as a new one started.
                if phase == .painted, bridge.phase != .committed { return }
                bridge.phase = phase
                if let error { bridge.errorText = error }
            }
        }

        func webView(
            _ webView: WKWebView,
            decidePolicyFor navigationAction: WKNavigationAction,
            decisionHandler: @escaping @MainActor (WKNavigationActionPolicy) -> Void
        ) {
            // Intercept book-source import deep links so WKWebView doesn't try to
            // navigate to them (an unhandled custom scheme fails as "unsupported URL").
            // We handle our own `yuedu://` scheme (来源配置 and module links) plus Legado's
            // `legado://import/...`, which most 书源 update pages emit (e.g. the 更新书源
            // download button).
            guard let url = navigationAction.request.url else {
                decisionHandler(.allow)
                return
            }
            let scheme = url.scheme?.lowercased()
            let isImportDeepLink = scheme == "yuedu"
                || (scheme == "legado" && url.host?.lowercased() == "import")
            guard isImportDeepLink else {
                decisionHandler(.allow)
                return
            }

            handleImportURL(url, webView: webView)
            decisionHandler(.cancel)
        }

        func load(url: URL, request initialRequest: URLRequest? = nil, in webView: WKWebView) {
            // Attach source credentials only to the exact destination prepared by its runtime.
            let request: URLRequest
            if let initialRequest, initialRequest.url == url {
                request = initialRequest
            } else {
                request = URLRequest(url: url)
            }
            let cookies = Self.cookiesForInitialLoad(url: url)
            guard !cookies.isEmpty else {
                webView.load(request)
                return
            }

            let cookieStore = webView.configuration.websiteDataStore.httpCookieStore
            let group = DispatchGroup()
            for cookie in cookies {
                group.enter()
                cookieStore.setCookie(cookie) {
                    group.leave()
                }
            }
            group.notify(queue: .main) {
                webView.load(request)
            }
        }

        func loadInitial(urlString: String, html: String?, request: URLRequest? = nil, in webView: WKWebView) {
            if let html {
                webView.loadHTMLString(html, baseURL: URL(string: urlString))
            } else if let url = URL(string: urlString) {
                load(url: url, request: request, in: webView)
            }
        }

        // Matches the SDK requirement exactly (`WK_SWIFT_UI_ACTOR` on the protocol and the reply
        // block). Without the annotations, complete concurrency checking rejects the conformance.
        @MainActor
        func userContentController(
            _ userContentController: WKUserContentController,
            didReceive message: WKScriptMessage,
            replyHandler: @escaping @MainActor (Any?, String?) -> Void
        ) {
            if message.name == Self.firstPaintMessageName {
                setPhase(.painted)
                replyHandler(nil, nil)
                return
            }
            if message.name == ReviewCommentGrabber.messageHandlerName {
                // 抓取脚本只发一条 JSON；解不出来就当没抓到，页面继续原样显示。
                // 这条回调本身就在主 actor 上（协议要求），直接更新面板状态。
                if let body = message.body as? String,
                   let page = ReviewCommentGrabber.decode(body) {
                    commentsGrabHandler?(page)
                }
                replyHandler(nil, nil)
                return
            }
            guard message.name == Self.sourceRunMessageName,
                  let script = message.body as? String,
                  let sourceRunHandler else {
                replyHandler(nil, localized("段评执行环境不可用"))
                return
            }
            Task {
                do {
                    replyHandler(try await sourceRunHandler(script), nil)
                } catch {
                    replyHandler(nil, error.localizedDescription)
                }
            }
        }

        func handleSourceJavaPrompt(
            _ payload: String,
            completion: @escaping @MainActor (String?) -> Void
        ) {
            do {
                if let configurationJSON = try JsBridgeBrowserRepresentable
                    .sourceConfigurationJSON(forPromptPayload: payload) {
                    sourceConfigurationUpdateHandler?(configurationJSON)
                    completion("")
                    return
                }
            } catch {
                AppLogger.parse("source page upConfig rejected request", context: [
                    "error": error.localizedDescription
                ])
                completion(nil)
                return
            }
            guard let sourceRunHandler else {
                completion(nil)
                return
            }
            let script: String
            do {
                script = try JsBridgeBrowserRepresentable.sourceJavaScript(
                    forPromptPayload: payload
                )
            } catch {
                AppLogger.parse("source page java bridge rejected request", context: [
                    "error": error.localizedDescription
                ])
                completion(nil)
                return
            }
            Task { @MainActor in
                do {
                    completion(try await sourceRunHandler(script))
                } catch {
                    AppLogger.parse("source page java bridge failed", context: [
                        "error": error.localizedDescription
                    ])
                    completion(nil)
                }
            }
        }

        // MARK: Navigation phases (drive the loading / error UI)

        func webView(_ webView: WKWebView, didStartProvisionalNavigation navigation: WKNavigation!) {
            setPhase(.loading)
        }

        func webView(_ webView: WKWebView, didCommit navigation: WKNavigation!) {
            setPhase(.committed)
        }

        /// Also what lifts the overlay where no first paint is posted: a document no user script
        /// runs in (a PDF), or a web view off screen, whose frames never come round.
        func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
            DispatchQueue.main.async { [weak self] in
                self?.bridge?.progress = 1
            }
            setPhase(.finished)
            syncCookiesAndDismiss(from: webView, completion: nil)
            if finishesWhenChallengeClears {
                checkCloudflareChallenge(in: webView)
            }
        }

        /// Legado-E and MD3 both ask every finished page `!!window._cf_chl_opt` — the object
        /// Cloudflare's challenge script defines — and finish the verification on the first
        /// page after a challenge that no longer has it.
        private func checkCloudflareChallenge(in webView: WKWebView) {
            webView.evaluateJavaScript("!!window._cf_chl_opt") { [weak self] result, error in
                guard let self else { return }
                if let error {
                    AppLogger.parse("source page Cloudflare check failed", context: [
                        "error": error.localizedDescription
                    ])
                    return
                }
                if (result as? Bool) == true {
                    self.sawChallenge = true
                } else if self.sawChallenge {
                    self.sawChallenge = false
                    self.bridge?.challengeCleared = true
                }
            }
        }

        func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) {
            setPhase(.failed, error: error.localizedDescription)
        }

        func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: Error) {
            // Ignore the benign "cancelled" that follows decidePolicy(.cancel) for
            // intercepted yuedu:// / legado:// import links.
            if (error as NSError).code == NSURLErrorCancelled { return }
            setPhase(.failed, error: error.localizedDescription)
        }

        func syncCookiesAndDismiss(from webView: WKWebView, completion: ((String?) -> Void)?) {
            webView.evaluateJavaScript("document.documentElement.outerHTML") { body, _ in
                let pageBody = body as? String
                webView.configuration.websiteDataStore.httpCookieStore.getAllCookies { cookies in
                    guard !cookies.isEmpty else { completion?(pageBody); return }

                    cookies.forEach { HTTPCookieStorage.shared.setCookie($0) }

                    var byDomain: [String: [HTTPCookie]] = [:]
                    for cookie in cookies {
                        let domain = cookie.domain.hasPrefix(".")
                            ? String(cookie.domain.dropFirst()) : cookie.domain
                        byDomain["https://\(domain)", default: []].append(cookie)
                    }
                    for (domainKey, domainCookies) in byDomain {
                        let joined = domainCookies.map { "\($0.name)=\($0.value)" }.joined(separator: "; ")
                        CookieStore.shared.set(url: domainKey, cookie: joined)
                    }

                    completion?(pageBody)
                }
            }
        }

        private func handleImportURL(_ url: URL, webView: WKWebView) {
            // A module link (Phase 6e-2) opens the module import, over this page.
            if case .module(let address) = BookSourceImportDeepLink.target(from: url) {
                RuleModuleLinkPresenter.present(address)
                return
            }
            guard let sourceURL = Self.onlineImportSourceURL(from: url) else {
                presentImportResult(localized("无效的来源配置导入连结"), in: webView)
                return
            }

            URLSession.shared.dataTask(with: sourceURL) { data, _, error in
                DispatchQueue.main.async {
                    if let error {
                        self.presentImportResult(error.localizedDescription, in: webView)
                        return
                    }
                    guard let data else {
                        self.presentImportResult(localized("无法读取来源配置资料"), in: webView)
                        return
                    }
                    do {
                        let ext = sourceURL.pathExtension.isEmpty ? "json" : sourceURL.pathExtension
                        // Parse only; the confirmation list decides what gets written.
                        let sources = try BookSourceStore.shared.parseForImport(
                            data: data,
                            fileExtension: ext
                        )
                        self.presentImportReview(sources, in: webView)
                    } catch {
                        self.presentImportResult(error.localizedDescription, in: webView)
                    }
                }
            }.resume()
        }

        private func presentImportResult(_ message: String, in webView: WKWebView) {
            guard let top = Self.topPresenter(in: webView) else { return }
            let alert = UIAlertController(title: localized("来源配置导入"), message: message, preferredStyle: .alert)
            alert.addAction(UIAlertAction(title: localized("完成"), style: .default))
            top.present(alert, animated: true)
        }

        /// Shows the import confirmation list over the in-page browser. This importer lives in
        /// a `WKWebView` coordinator with no SwiftUI sheet host, so the list is hosted in a
        /// UIKit controller presented from the same presenter the result alert uses.
        private func presentImportReview(_ sources: [BookSource], in webView: WKWebView) {
            guard let top = Self.topPresenter(in: webView) else { return }
            // The dismiss callbacks need the controller that does not exist yet when its own
            // `rootView` is built. The box holds it weakly, so nothing retains a cycle.
            final class PresentedControllerBox {
                weak var controller: UIViewController?
            }
            let box = PresentedControllerBox()
            let host = UIHostingController(
                rootView: BookSourceImportReviewHost(
                    sources: sources,
                    onFinish: { [weak self] count in
                        box.controller?.dismiss(animated: true) {
                            self?.presentImportResult(
                                String(format: localized("成功汇入 %d 个来源配置"), count),
                                in: webView
                            )
                        }
                    },
                    onCancel: { box.controller?.dismiss(animated: true) }
                )
            )
            box.controller = host
            top.present(host, animated: true)
        }

        private static func topPresenter(in webView: WKWebView) -> UIViewController? {
            guard let root = webView.window?.rootViewController else { return nil }
            var top = root
            while let presented = top.presentedViewController {
                top = presented
            }
            return top
        }

        static func onlineImportSourceURL(from url: URL) -> URL? {
            // Single source of truth: shared with the system-level deep-link
            // handler in `yuedu_appApp`. One path for this concern.
            BookSourceImportDeepLink.sourceURL(from: url)
        }

        static func cookiesForInitialLoad(url: URL) -> [HTTPCookie] {
            HTTPCookieStorage.shared.cookies(for: url) ?? []
        }
    }
}

// MARK: - Keyboard-on-programmatic-focus patch
//
// WKWebView suppresses the on-screen keyboard when a web page focuses an `<input>` via JavaScript
// instead of a direct tap. SMS login pages (番茄 included) render the 验证码 field as styled boxes
// whose tap handler calls `input.focus()` — so the phone-number field (a real `<input>` you tap)
// raises the keyboard, but the 验证码 boxes never do. There is no public API for this, so we
// swizzle the private `WKContentView` focus callback ONCE to always report user interaction.
// Runtime-only: no private symbols are linked (looked up via NSClassFromString / sel_getUid).
extension WKWebView {
    /// Lazily-evaluated, thread-safe one-shot patch. Touch `WKWebView.patchKeyboardFocusOnce`
    /// from any web view's `makeUIView` to install it process-wide.
    static let patchKeyboardFocusOnce: Void = {
        guard let contentViewClass = NSClassFromString("WKContentView") else { return }

        // (self, _cmd, focusedElementInfo, userIsInteracting, blurPreviousNode,
        //  activityStateChanges, userObject)
        typealias FocusIMP = @convention(c) (Any, Selector, UnsafeRawPointer, Bool, Bool, UInt, Any?) -> Void

        // iOS 13+ uses `activityStateChanges`; the older `changingActivityState` name is kept as a
        // defensive fallback. Patch whichever exists.
        let selectorNames = [
            "_elementDidFocus:userIsInteracting:blurPreviousNode:activityStateChanges:userObject:",
            "_elementDidFocus:userIsInteracting:blurPreviousNode:changingActivityState:userObject:",
        ]

        for name in selectorNames {
            let selector = sel_getUid(name)
            guard let method = class_getInstanceMethod(contentViewClass, selector) else { continue }
            let originalIMP = method_getImplementation(method)
            let original = unsafeBitCast(originalIMP, to: FocusIMP.self)
            let override: @convention(block) (Any, UnsafeRawPointer, Bool, Bool, UInt, Any?) -> Void = {
                received, element, _, blurPreviousNode, activityStateChanges, userObject in
                // Force `userIsInteracting` = true so the keyboard appears for JS-driven focus.
                original(received, selector, element, true, blurPreviousNode, activityStateChanges, userObject)
            }
            method_setImplementation(method, imp_implementationWithBlock(override))
            return
        }
    }()
}

// MARK: - Preview

#Preview {
    JsBridgeBrowserView(
        urlString: "https://example.com",
        title: "密钥获取",
        onDismiss: { _ in }
    )
}
