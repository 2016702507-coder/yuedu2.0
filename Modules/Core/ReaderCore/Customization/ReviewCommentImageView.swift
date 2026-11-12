import SwiftUI
import UIKit

// MARK: - 段评配图加载器

/// 段评配图的远程图加载器。
///
/// SwiftUI 自带的 `AsyncImage` 只会画出 GIF 的**第一帧**——旧版网页面板里
/// 会动的表情包/动图，进了原生卡片就成了一张死图。这里用
/// `CGImageSource` 把 GIF（或 APNG 等多帧格式）逐帧解出来拼成
/// `UIImage.animatedImage`，动图在卡片和全屏查看器里都能正常播放。
/// 解码结果用 `NSCache` 缓存，滚动列表来回复用也不会反复下载。
@MainActor
final class ReviewImageLoader {
    static let shared = ReviewImageLoader()

    private let cache = NSCache<NSURL, UIImage>()

    private init() {
        cache.countLimit = 80
        cache.totalCostLimit = 96 * 1024 * 1024
    }

    /// 取（可能带动画的）图。失败返回 nil，由调用方决定占位。
    func animatedImage(for url: URL) async -> UIImage? {
        if let hit = cache.object(forKey: url as NSURL) { return hit }
        guard let (data, response) = try? await URLSession.shared.data(from: url),
              !data.isEmpty,
              (response as? HTTPURLResponse)?.statusCode.map({ (200..<300).contains($0) }) ?? true
        else { return nil }
        let image = Self.decode(data)
        if let image {
            cache.setObject(image, forKey: url as NSURL, cost: data.count)
        }
        return image
    }

    /// 非隔离解码：GIF 逐帧 + 每帧延时，拼成 animatedImage。
    nonisolated static func decode(_ data: Data) -> UIImage? {
        guard let src = CGImageSourceCreateWithData(data as CFData, nil) else { return nil }
        let count = CGImageSourceGetCount(src)
        guard count > 0 else { return nil }

        // 单帧（普通 PNG/JPG/WEBP 静图）直接走位图路径。
        if count == 1, let cg = CGImageSourceCreateImageAtIndex(src, 0, nil) {
            return UIImage(cgImage: cg)
        }

        var frames: [UIImage] = []
        var total: TimeInterval = 0
        for index in 0..<count {
            guard let cg = CGImageSourceCreateImageAtIndex(src, index, nil) else { continue }
            var delay: TimeInterval = 0.1
            if let props = CGImageSourceCopyPropertiesAtIndex(src, index, nil) as? [CFString: Any],
               let gif = props[kCGImagePropertyGIFDictionary] as? [CFString: Any] {
                if let d = gif[kCGImagePropertyGIFUnclampedDelayTime] as? TimeInterval {
                    delay = d
                } else if let d = gif[kCGImagePropertyGIFDelayTime] as? TimeInterval {
                    delay = d
                }
            }
            // 过短延时按下限钳制，否则一些表情包会闪成幻灯片。
            frames.append(UIImage(cgImage: cg))
            total += max(0.02, delay)
        }
        guard !frames.isEmpty else { return nil }
        return frames.count == 1 ? frames[0] : UIImage.animatedImage(with: frames, duration: total)
    }
}

// MARK: - 动图视图（SwiftUI 入口）

/// 支持 GIF 动画的远程图视图（替代卡片里的 `AsyncImage`）。
///
/// 加载态/失败态由 SwiftUI 这边画（保持和旧占位一致的布局高度），
/// 加载完成后交给 `ReviewImageCanvas`（UIImageView）渲染——
/// 只有 UIImageView 能播放 `UIImage.animatedImage`，SwiftUI 的
/// `Image(uiImage:)` 只会画第一帧。
struct ReviewAnimatedImageView: View {
    let url: URL
    /// true：撑满裁切（九宫格缩略图）；false：完整显示（单图大图）。
    var fills: Bool = false
    /// 单图加载中的占位高度（九宫格固定 84，无需占位）。
    var placeholderHeight: CGFloat = 140

    @State private var image: UIImage?
    @State private var failed = false

    var body: some View {
        Group {
            if let image {
                ReviewImageCanvas(image: image, fills: fills)
            } else if failed {
                Color.clear
            } else {
                Color.primary.opacity(0.05)
                    .frame(height: fills ? nil : placeholderHeight)
            }
        }
        .task(id: url) {
            failed = false
            image = nil
            image = await ReviewImageLoader.shared.animatedImage(for: url)
            failed = (image == nil)
        }
    }
}

/// 已解码图片的渲染画布。UIImageView 才会播 `animatedImage` 的帧动画。
private struct ReviewImageCanvas: UIViewRepresentable {
    let image: UIImage
    var fills: Bool

    func makeUIView(context: Context) -> UIImageView {
        let view = UIImageView()
        view.contentMode = fills ? .scaleAspectFill : .scaleAspectFit
        view.clipsToBounds = true
        view.backgroundColor = .clear
        view.image = image
        return view
    }

    func updateUIView(_ view: UIImageView, context: Context) {
        view.image = image
        view.contentMode = fills ? .scaleAspectFill : .scaleAspectFit
    }
}

// MARK: - 全屏图片查看器

/// 点击段评配图弹出的全屏查看器：黑底、可捏合缩放、双击放大、单击关闭。
/// 与旧版网页面板的体验对齐——动图（GIF）在全屏里照样播放。
struct ReviewImageViewer: View {
    let url: URL

    @Environment(\.dismiss) private var dismiss

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()
            ReviewZoomableImageView(url: url) {
                dismiss()
            }
        }
        .background(Color.black.ignoresSafeArea())
    }
}

/// 黑底里可缩放的图片容器（UIScrollView + UIImageView）。
/// 固定铺满父视图，加载在内部完成；单击回调用于关闭查看器。
struct ReviewZoomableImageView: UIViewRepresentable {
    let url: URL
    /// 单击（非双击）回调，用于关闭查看器。
    var onSingleTap: () -> Void

    func makeCoordinator() -> Coordinator { Coordinator(onSingleTap: onSingleTap) }

    final class Coordinator: NSObject, UIScrollViewDelegate {
        var onSingleTap: () -> Void
        weak var imageView: UIImageView?
        weak var scrollView: UIScrollView?

        init(onSingleTap: @escaping () -> Void) {
            self.onSingleTap = onSingleTap
        }

        @objc func handleSingleTap() { onSingleTap() }

        @objc func handleDoubleTap(_ g: UITapGestureRecognizer) {
            guard let scroll = scrollView else { return }
            if scroll.zoomScale > scroll.minimumZoomScale + 0.01 {
                scroll.setZoomScale(scroll.minimumZoomScale, animated: true)
            } else {
                let point = g.location(in: imageView)
                let target = CGFloat(2.5)
                let size = CGSize(
                    width: scroll.bounds.width / target,
                    height: scroll.bounds.height / target
                )
                let origin = CGPoint(x: point.x - size.width / 2, y: point.y - size.height / 2)
                scroll.zoom(to: CGRect(origin: origin, size: size), animated: true)
            }
        }

        func viewForZooming(in scrollView: UIScrollView) -> UIView? { imageView }
    }

    func makeUIView(context: Context) -> UIScrollView {
        let scroll = UIScrollView()
        scroll.minimumZoomScale = 1
        scroll.maximumZoomScale = 5
        scroll.showsHorizontalScrollIndicator = false
        scroll.showsVerticalScrollIndicator = false
        scroll.backgroundColor = .clear
        scroll.delegate = context.coordinator

        let imageView = UIImageView()
        imageView.contentMode = .scaleAspectFit
        imageView.clipsToBounds = true
        imageView.backgroundColor = .clear
        imageView.translatesAutoresizingMaskIntoConstraints = false
        scroll.addSubview(imageView)
        NSLayoutConstraint.activate([
            imageView.topAnchor.constraint(equalTo: scroll.frameLayoutGuide.topAnchor),
            imageView.bottomAnchor.constraint(equalTo: scroll.frameLayoutGuide.bottomAnchor),
            imageView.leadingAnchor.constraint(equalTo: scroll.frameLayoutGuide.leadingAnchor),
            imageView.trailingAnchor.constraint(equalTo: scroll.frameLayoutGuide.trailingAnchor),
        ])
        context.coordinator.imageView = imageView
        context.coordinator.scrollView = scroll

        let single = UITapGestureRecognizer(
            target: context.coordinator,
            action: #selector(Coordinator.handleSingleTap)
        )
        let double = UITapGestureRecognizer(
            target: context.coordinator,
            action: #selector(Coordinator.handleDoubleTap(_:))
        )
        double.numberOfTapsRequired = 2
        single.require(toFail: double)
        scroll.addGestureRecognizer(single)
        scroll.addGestureRecognizer(double)

        Task { @MainActor in
            let image = await ReviewImageLoader.shared.animatedImage(for: url)
            // representable 复用时 URL 可能已换，过期结果直接丢弃。
            guard context.coordinator.imageView === imageView else { return }
            imageView.image = image
        }
        return scroll
    }

    func updateUIView(_ view: UIScrollView, context: Context) {
        context.coordinator.onSingleTap = onSingleTap
    }
}

// MARK: - 查看器入参包装

/// `fullScreenCover(item:)` 需要的 Identifiable 包装。
struct ReviewViewerImageItem: Identifiable, Equatable {
    let url: URL
    var id: String { url.absoluteString }
}
