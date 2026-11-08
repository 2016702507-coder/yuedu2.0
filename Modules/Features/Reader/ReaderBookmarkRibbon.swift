import UIKit

/// 页面右上角的书签缎带：这一页有书签，这一页就挂著它——不管书签是从顶部按钮、
/// 触控区还是下拉加的。
///
/// 形状只有一份（`frame(in:)` + `path(in:)`），画法有两条：
/// - **快照**走 Core Graphics，由 `ReaderPageBars.draw` 跟页眉页脚一起画进页面。
///   仿真翻页的背面、覆盖翻页的截图、自动阅读的揭幕图都是 `renderPage` 画出来的
///   图，不是活的 view；缎带只有画在这里，才会在每一种翻页动画里跟著页走。
/// - **萤幕上那一页**用 `ReaderBookmarkRibbonView`，因为它得动：加书签时从页顶
///   慢慢长出来、移除时缩回去，下拉时跟著手指走。为这个重画整页（整页 CTFrameDraw）
///   每一帧都做不起。
/// 所以活的页面画 bars 时要先 `removingBookmarkRibbon()`，不然会两条各画一次。
enum ReaderBookmarkRibbon {
    static let width: CGFloat = 16
    /// Page top edge → the tips of the notch. Ends above the header line, whose
    /// chapter name sits at the left and never reaches this corner anyway.
    static let length: CGFloat = 60
    /// Page right edge → the ribbon's right edge. Far enough in that the rounded
    /// screen corner of a full-screen page shaves only the ribbon's top few points.
    static let trailingInset: CGFloat = 32
    static let notchDepth: CGFloat = 6
    /// The top bar's filled bookmark is SwiftUI `.orange`, which is this colour.
    static var color: UIColor { .systemOrange }

    /// Where the ribbon hangs on a page with these bounds.
    static func frame(in pageBounds: CGRect) -> CGRect {
        CGRect(
            x: pageBounds.maxX - trailingInset - width,
            y: pageBounds.minY,
            width: width,
            height: length
        )
    }

    /// A strip of ribbon cut with a V at its free end, in UIKit coordinates.
    static func path(in rect: CGRect) -> CGPath {
        let path = CGMutablePath()
        path.move(to: CGPoint(x: rect.minX, y: rect.minY))
        path.addLine(to: CGPoint(x: rect.maxX, y: rect.minY))
        path.addLine(to: CGPoint(x: rect.maxX, y: rect.maxY))
        path.addLine(to: CGPoint(x: rect.midX, y: rect.maxY - notchDepth))
        path.addLine(to: CGPoint(x: rect.minX, y: rect.maxY))
        path.closeSubpath()
        return path
    }

    /// The fully hung ribbon, for snapshots. `pageBounds` in UIKit coordinates.
    static func draw(in pageBounds: CGRect, context ctx: CGContext) {
        ctx.saveGState()
        ctx.addPath(path(in: frame(in: pageBounds)))
        ctx.setFillColor(color.cgColor)
        ctx.fillPath()
        ctx.restoreGState()
    }

    /// Opacity at a given reveal. Fades in over the first part of the slide so the
    /// notch does not arrive as a hard-edged sliver.
    static func alpha(forReveal reveal: CGFloat) -> CGFloat {
        min(max(reveal, 0) * 1.6, 1)
    }

    /// How far the strip is pulled up into the page top at a given reveal.
    static func retraction(forReveal reveal: CGFloat) -> CGFloat {
        (1 - min(max(reveal, 0), 1)) * length
    }
}

/// A page that can show the ribbon live — the pull-down gesture drives it through
/// this while the finger is down.
@MainActor
protocol ReaderBookmarkRibbonHosting: AnyObject {
    /// The finger owns the ribbon until `endInteractiveBookmarkRibbon`. A bars
    /// refresh in between (a clock tick) is recorded but not shown.
    func beginInteractiveBookmarkRibbon()
    /// 0 = retracted into the page top, 1 = fully hung.
    func setInteractiveBookmarkRibbonReveal(_ reveal: CGFloat)
    /// Settles on the outcome the gesture just committed (or the state it started
    /// from, when it was cancelled) without waiting for the page's bars to catch up.
    func endInteractiveBookmarkRibbon(isBookmarked: Bool)
}

/// The live page's ribbon. See `ReaderBookmarkRibbon` for why it is a view here
/// and a drawing everywhere else.
@MainActor
final class ReaderBookmarkRibbonView: UIView {
    private final class ShapeView: UIView {
        override class var layerClass: AnyClass { CAShapeLayer.self }
        var shapeLayer: CAShapeLayer { layer as! CAShapeLayer }
    }

    static let settleDuration: TimeInterval = 0.32

    private let strip = ShapeView()
    private(set) var isBookmarked = false
    private var isInteractive = false
    private var reveal: CGFloat = 0

    override init(frame: CGRect) {
        super.init(frame: frame)
        isUserInteractionEnabled = false
        isAccessibilityElement = false
        // The strip grows out of the page top rather than sliding in from above it.
        clipsToBounds = true
        strip.shapeLayer.fillColor = ReaderBookmarkRibbon.color.cgColor
        addSubview(strip)
        applyReveal()
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) not used")
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        let transform = strip.transform
        strip.transform = .identity
        strip.frame = bounds
        strip.shapeLayer.path = ReaderBookmarkRibbon.path(in: strip.bounds)
        strip.transform = transform
    }

    /// The resting state, from the page's bars. Animates only when the state
    /// actually flips under a page that is on screen — a bookmark added or removed
    /// from the top bar or a touch zone — so a page that turns in already
    /// bookmarked arrives with its ribbon hung.
    func setBookmarked(_ bookmarked: Bool, animated: Bool) {
        let changed = bookmarked != isBookmarked
        isBookmarked = bookmarked
        guard !isInteractive else { return }
        settle(on: bookmarked, animated: animated && changed && window != nil)
    }

    func beginInteractive() {
        isInteractive = true
        strip.layer.removeAllAnimations()
    }

    func setInteractiveReveal(_ newReveal: CGFloat) {
        guard isInteractive else { return }
        reveal = newReveal
        applyReveal()
    }

    func endInteractive(isBookmarked bookmarked: Bool) {
        isInteractive = false
        isBookmarked = bookmarked
        settle(on: bookmarked, animated: window != nil)
    }

    private func settle(on bookmarked: Bool, animated: Bool) {
        reveal = bookmarked ? 1 : 0
        guard animated else {
            strip.layer.removeAllAnimations()
            applyReveal()
            return
        }
        UIView.animate(
            withDuration: Self.settleDuration,
            delay: 0,
            options: [.curveEaseOut, .beginFromCurrentState, .allowUserInteraction]
        ) {
            self.applyReveal()
        }
    }

    private func applyReveal() {
        strip.alpha = ReaderBookmarkRibbon.alpha(forReveal: reveal)
        // Reduce Motion: the ribbon still comes and goes, it just does not travel.
        strip.transform = UIAccessibility.isReduceMotionEnabled
            ? .identity
            : CGAffineTransform(translationX: 0, y: -ReaderBookmarkRibbon.retraction(forReveal: reveal))
    }
}
