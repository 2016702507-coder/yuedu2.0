import UIKit

/// 屏幕空间翻页浮层的统一接口。
///
/// 两个实现：`ReaderRipplePageTurnView`（波纹，Metal 逐像素混合）和
/// `ReaderVerticalPageTurnView`（上下翻页，两页垂直平移）。协调器只认这套方法，
/// 换样式时不必再改一遍调用点。
protocol ReaderPageTurnOverlay: AnyObject {
    /// 设备 / 编译期能力不足时返回 false，调用方退化成瞬间换页。
    var isSupported: Bool { get }
    /// 交出两张页面快照。`origin` 是归一化坐标（0…1，左上原点），`direction` 是推进方向；
    /// 上下翻页只用到 `direction.dy` 的符号。
    func prepare(oldPage: UIImage, newPage: UIImage, origin: CGPoint, direction: CGVector)
    /// 0 = 旧页铺满，1 = 新页铺满。
    func setProgress(_ progress: CGFloat)
    func reset()
}

/// 上下翻页（起点那种）：整页跟着手指上下走，两页首尾相接，不折、不擦、不带波纹。
///
/// 两张快照各自的 `transform` 平移，进度就是位移比例 —— 手指拖多少，页面走多少，
/// 松手后由协调器决定补完到 1 还是弹回 0。
final class ReaderVerticalPageTurnView: UIView, ReaderPageTurnOverlay {

    private let oldView = UIImageView()
    private let newView = UIImageView()
    /// 两页交界处压一条 16pt 的淡渐变，翻的时候能看出层次；起止两端渐隐，
    /// 所以进度 0 / 1 时完全看不见。
    private let edgeFade = CAGradientLayer()

    /// true = 下一页（整页往上翻），false = 上一页。
    private var forward = true
    private var progress: CGFloat = 0

    var isSupported: Bool { true }

    override init(frame: CGRect) {
        super.init(frame: frame)
        isUserInteractionEnabled = false
        clipsToBounds = true
        backgroundColor = .clear

        // 新页先加、旧页后加：两页不重叠，顺序只是为了旧页压在上面时不闪。
        for imageView in [newView, oldView] {
            imageView.contentMode = .scaleAspectFit
            imageView.isUserInteractionEnabled = false
            imageView.backgroundColor = .clear
            addSubview(imageView)
        }

        edgeFade.colors = [
            UIColor.black.withAlphaComponent(0).cgColor,
            UIColor.black.withAlphaComponent(0.10).cgColor,
            UIColor.black.withAlphaComponent(0).cgColor,
        ]
        edgeFade.startPoint = CGPoint(x: 0.5, y: 0)
        edgeFade.endPoint = CGPoint(x: 0.5, y: 1)
        edgeFade.isHidden = true
        layer.addSublayer(edgeFade)

        isHidden = true
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    func prepare(oldPage: UIImage, newPage: UIImage, origin: CGPoint, direction: CGVector) {
        // 上下翻页不看触点：direction.dy < 0 是往上翻（下一页），> 0 是往下翻。
        forward = direction.dy <= 0
        oldView.image = oldPage
        newView.image = newPage
        progress = 0
        isHidden = false
        setNeedsLayout()
        layoutIfNeeded()
        applyTransforms()
    }

    func setProgress(_ value: CGFloat) {
        progress = min(max(value, 0), 1)
        applyTransforms()
    }

    func reset() {
        oldView.image = nil
        newView.image = nil
        progress = 0
        edgeFade.isHidden = true
        isHidden = true
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        let size = bounds.size
        guard size.width > 0, size.height > 0 else { return }
        // 用 bounds + center 定位，随后 transform 才不会把 frame 算歪。
        for imageView in [oldView, newView] {
            imageView.transform = .identity
            imageView.bounds = CGRect(origin: .zero, size: size)
            imageView.center = CGPoint(x: bounds.midX, y: bounds.midY)
        }
        applyTransforms()
    }

    private func applyTransforms() {
        let height = bounds.height
        guard height > 0 else { return }

        // 下一页：旧页往上走 -p·H，新页从下方 (1-p)·H 处补进来。上一页整体取反。
        let sign: CGFloat = forward ? -1 : 1
        oldView.transform = CGAffineTransform(translationX: 0, y: sign * progress * height)
        newView.transform = CGAffineTransform(translationX: 0, y: -sign * (1 - progress) * height)

        let edge = forward ? height * (1 - progress) : height * progress
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        edgeFade.frame = CGRect(x: 0, y: edge - 8, width: bounds.width, height: 16)
        edgeFade.isHidden = progress <= 0.001 || progress >= 0.999
        CATransaction.commit()
    }
}
