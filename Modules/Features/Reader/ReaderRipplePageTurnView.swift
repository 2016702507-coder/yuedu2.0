import Metal
import MetalKit
import UIKit

/// 波纹翻页的 GPU 渲染层。
///
/// 算法逐行移植自 页间阅读 1.1.2 的 `page_turn_ripple.frag`：一个从**翻页进去的那侧
/// 边缘中点**向外扩散的波前，波前是一道竖着的弧形，从左往右（或从右往左）扫过整页；
/// 扫过之处新旧两页按 (1−m)³ / ((1−m)³ + m³) 的比例混合，波前本身既是像素位移
/// （把采样点沿法线推一下，形成一道"水峰"）又是高光带。
///
/// 着色器以源码形式内嵌、在首次用到时用 `makeLibrary(source:)` 编译，而不是放进
/// `.metal` 文件：工程用 Xcode 16 的同步文件夹，新增 Swift 文件即被编译，而 `.metal`
/// 是否进入 Sources 阶段取决于文件类型的自动归类——这里不押注它。
final class ReaderRipplePageTurnView: UIView, ReaderPageTurnOverlay {

    /// 与 MSL 里 `RippleParams` 逐字节对应：三个 float2 加两个 float，共 32 字节。
    struct Parameters {
        var size: SIMD2<Float> = .zero
        var origin: SIMD2<Float> = SIMD2<Float>(1, 0.5)
        var direction: SIMD2<Float> = SIMD2<Float>(-1, 0)
        var progress: Float = 0
        /// 0 = 从原点向外扩散（页间阅读的默认形态），1 = 边缘向内收，2 = 沿 direction 平移。
        var waveform: Float = 0
    }

    private(set) var renderer: ReaderRipplePageTurnRenderer?
    private let metalView: MTKView

    /// Nil when the device has no Metal (simulator fallback), or the shader failed to
    /// compile. Callers degrade to a plain page swap rather than crash.
    override init(frame: CGRect) {
        let device = MTLCreateSystemDefaultDevice()
        metalView = MTKView(frame: .zero, device: device)
        super.init(frame: frame)
        isUserInteractionEnabled = false
        backgroundColor = .clear
        clipsToBounds = true

        metalView.translatesAutoresizingMaskIntoConstraints = false
        metalView.isUserInteractionEnabled = false
        metalView.framebufferOnly = true
        // Not opaque: between the overlay going up and the first frame landing there
        // is nothing to show, and a black flash is worse than seeing the page under it.
        metalView.isOpaque = false
        metalView.backgroundColor = .clear
        metalView.clearColor = MTLClearColor(red: 0, green: 0, blue: 0, alpha: 0)
        metalView.colorPixelFormat = .bgra8Unorm
        // Nothing animates on its own: the pan handler and the display link push a
        // progress value, and each push schedules exactly one frame.
        metalView.isPaused = true
        metalView.enableSetNeedsDisplay = true
        metalView.autoResizeDrawable = true
        addSubview(metalView)
        NSLayoutConstraint.activate([
            metalView.leadingAnchor.constraint(equalTo: leadingAnchor),
            metalView.trailingAnchor.constraint(equalTo: trailingAnchor),
            metalView.topAnchor.constraint(equalTo: topAnchor),
            metalView.bottomAnchor.constraint(equalTo: bottomAnchor),
        ])

        if device != nil {
            renderer = ReaderRipplePageTurnRenderer(device: device!)
            metalView.delegate = renderer
        }
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    var isSupported: Bool { renderer != nil }

    /// Hands the two pages to the GPU. `origin` is normalised (0...1, top-left origin).
    func prepare(oldPage: UIImage, newPage: UIImage, origin: CGPoint, direction: CGVector) {
        guard let renderer else { return }
        renderer.upload(oldPage: oldPage, newPage: newPage)
        var parameters = renderer.parameters
        parameters.origin = SIMD2<Float>(Float(origin.x), Float(origin.y))
        let length = hypot(direction.dx, direction.dy)
        if length > 0.001 {
            parameters.direction = SIMD2<Float>(Float(direction.dx / length), Float(direction.dy / length))
        }
        // uWaveform 的三个分支，同一个 page_turn_ripple.frag：
        //   0 = 弧从 origin 向外扩（一小块半圆从边缘鼓出）
        //   1 = 弧从外缘向 origin 收
        //   2 = 波前是一条**垂直于 direction 的直线**，沿 direction 平推
        // 左右翻页要的是「一道竖着的水波从一侧推到另一侧」，所以取 2：
        // direction 由调用方给 (±1, 0)，波前就是一条竖直线，从头到尾竖直，不带弧。
        // origin 仍固定在翻页那侧的边中点 (1,0.5)/(0,0.5)，保证推进方向是右->左 / 左->右。
        parameters.waveform = 2
        renderer.parameters = parameters
    }

    func setProgress(_ progress: CGFloat) {
        guard let renderer, renderer.hasContent else {
            isHidden = true
            return
        }
        renderer.parameters.progress = Float(min(max(progress, 0), 1))
        metalView.setNeedsDisplay()
    }

    func reset() {
        renderer?.clear()
        isHidden = true
    }
}

// MARK: - Renderer

final class ReaderRipplePageTurnRenderer: NSObject, MTKViewDelegate {

    private static let shaderSource = """
    #include <metal_stdlib>
    using namespace metal;

    struct RippleParams {
        float2 size;
        float2 origin;
        float2 direction;
        float progress;
        float waveform;
    };

    struct RippleVertex {
        float4 position [[position]];
        float2 uv;
    };

    vertex RippleVertex ripple_vertex(uint vid [[vertex_id]]) {
        // Triangle strip: bottom-left, bottom-right, top-left, top-right. Metal's NDC
        // has y up, a texture's first row is the top, so uv.y is flipped here.
        const float2 positions[4] = {
            float2(-1.0, -1.0), float2(1.0, -1.0), float2(-1.0, 1.0), float2(1.0, 1.0)
        };
        const float2 uvs[4] = {
            float2(0.0, 1.0), float2(1.0, 1.0), float2(0.0, 0.0), float2(1.0, 0.0)
        };
        RippleVertex out;
        out.position = float4(positions[vid], 0.0, 1.0);
        out.uv = uvs[vid];
        return out;
    }

    fragment float4 ripple_fragment(RippleVertex in [[stage_in]],
                                    constant RippleParams &p [[buffer(0)]],
                                    texture2d<float> oldPage [[texture(0)]],
                                    texture2d<float> newPage [[texture(1)]]) {
        constexpr sampler smp(coord::normalized, filter::linear, address::clamp_to_edge);

        float2 size = max(p.size, float2(1.0));
        float2 fc = in.position.xy;
        float2 uv = clamp(fc / size, float2(0.0), float2(1.0));

        if (p.progress <= 0.0) { return oldPage.sample(smp, uv); }
        if (p.progress >= 1.0) { return newPage.sample(smp, uv); }

        // Wavefront geometry: a ring of radius R whose band is a quarter of R wide,
        // measured from the touch point. `+ W * W` inside the square root keeps the
        // direction well defined at the origin instead of dividing by zero.
        float minSide = min(size.x, size.y);
        float R = max(32.0, minSide * 0.20);
        float W = R * 0.25;
        float2 o = p.origin * size;
        float2 d = fc - o;
        float dist = sqrt(dot(d, d) + W * W);
        float2 radialDir = d / dist;
        float2 farPoint = max(o, size - o);
        float corner = sqrt(dot(farPoint, farPoint) + W * W) - W;
        float radial = dist - W;

        float2 travelDir;
        float travel;
        float extent;
        if (p.waveform > 1.5) {
            travelDir = p.direction;
            travel = dot(d, p.direction);
            extent = abs(p.direction.x) * size.x + abs(p.direction.y) * size.y;
        } else if (p.waveform > 0.5) {
            travelDir = -radialDir;
            travel = corner - radial;
            extent = corner;
        } else {
            travelDir = radialDir;
            travel = radial;
            extent = corner;
        }

        // 波前保持一条笔直的竖线，不做上下起伏 —— 一旦加 sin 就会「弯」，
        // 那是水面波纹的另一种形态，不是这里要的「竖着的波纹」。

        // -1 far ahead of the front, +1 well behind it; the front sweeps from -R to
        // beyond the farthest corner as progress runs 0 -> 1.
        float wave = (travel - mix(-R, extent + R, p.progress)) / R;

        // 主峰在前，后面跟一道浅的余波 —— 单一高斯推过去只有“平移”没有“涟漪”。
        float scalar = -3.2974424362182617 * wave * exp(-2.0 * wave * wave);
        float tailWave = wave - 1.55;
        scalar += 0.32 * (-1.9 * tailWave * exp(-2.2 * tailWave * tailWave));

        float2 bump = (travelDir * scalar)
            * (smoothstep(0.0, 0.1, p.progress) * (1.0 - smoothstep(0.9, 1.0, p.progress)));
        float2 sampleUV = clamp((fc + bump * minSide * 0.036) / size, float2(0.0), float2(1.0));

        // Old page behind the front, new page ahead of it, blended with a curve that
        // keeps the crossing band narrow — (1-m)^3 / ((1-m)^3 + m^3).
        float m = smoothstep(-0.85, 0.25, wave);
        float m3 = m * m * m;
        float n = 1.0 - m;
        float n3 = n * n * n;
        float k = n3 / max(n3 + m3, 0.00001);

        float4 mixed = mix(oldPage.sample(smp, sampleUV), newPage.sample(smp, sampleUV), k);
        // 水面质感靠明暗：波峰一条窄亮线、紧跟一条窄暗线，再叠一点整体起伏。
        float crest = exp(-pow((wave + 0.45) / 0.26, 2.0));
        float trough = exp(-pow((wave - 0.55) / 0.34, 2.0));
        float shade = 1.0 + 0.10 * crest - 0.07 * trough + 0.03 * scalar;
        return float4(clamp(mixed.xyz * shade, float3(0.0), float3(mixed.w)), mixed.w);
    }
    """

    let device: MTLDevice
    private let commandQueue: MTLCommandQueue
    private let pipeline: MTLRenderPipelineState
    private var oldTexture: MTLTexture?
    private var newTexture: MTLTexture?
    var parameters = ReaderRipplePageTurnView.Parameters()

    var hasContent: Bool { oldTexture != nil && newTexture != nil }

    /// `nonisolated(unsafe)`：渲染器是 `MTKViewDelegate`，不能在主线程隔离里声明；
    /// 这块全局缓存由下面的 `libraryLock` 串行保护，因此按既有的锁语义标注。
    private nonisolated(unsafe) static var cachedLibrary: MTLLibrary?
    private static let libraryLock = NSLock()

    /// Compiled once per process: 60 lines of MSL cost tens of milliseconds, and every
    /// reader the user opens in 波纹 mode would otherwise pay it again.
    private static func library(for device: MTLDevice) -> MTLLibrary? {
        libraryLock.lock()
        defer { libraryLock.unlock() }
        if let cachedLibrary { return cachedLibrary }
        let compiled = try? device.makeLibrary(source: shaderSource, options: nil)
        cachedLibrary = compiled
        return compiled
    }

    init?(device: MTLDevice) {
        guard let queue = device.makeCommandQueue() else { return nil }
        guard let library = Self.library(for: device) else {
            AppLogger.render("[RippleTrace] shader compile failed")
            return nil
        }
        guard
            let vertex = library.makeFunction(name: "ripple_vertex"),
            let fragment = library.makeFunction(name: "ripple_fragment")
        else {
            AppLogger.render("[RippleTrace] shader functions missing")
            return nil
        }
        let descriptor = MTLRenderPipelineDescriptor()
        descriptor.vertexFunction = vertex
        descriptor.fragmentFunction = fragment
        descriptor.colorAttachments[0].pixelFormat = .bgra8Unorm
        do {
            pipeline = try device.makeRenderPipelineState(descriptor: descriptor)
        } catch {
            AppLogger.render("[RippleTrace] pipeline failed: \(error.localizedDescription)")
            return nil
        }
        self.device = device
        self.commandQueue = queue
        super.init()
    }

    func upload(oldPage: UIImage, newPage: UIImage) {
        oldTexture = Self.texture(from: oldPage, device: device, reusing: oldTexture)
        newTexture = Self.texture(from: newPage, device: device, reusing: newTexture)
    }

    func clear() {
        oldTexture = nil
        newTexture = nil
    }

    func mtkView(_ view: MTKView, drawableSizeWillChange size: CGSize) {}

    func draw(in view: MTKView) {
        guard
            let oldTexture, let newTexture,
            let drawable = view.currentDrawable,
            let pass = view.currentRenderPassDescriptor,
            let buffer = commandQueue.makeCommandBuffer(),
            let encoder = buffer.makeRenderCommandEncoder(descriptor: pass)
        else { return }

        var params = parameters
        params.size = SIMD2<Float>(Float(view.drawableSize.width), Float(view.drawableSize.height))
        encoder.setRenderPipelineState(pipeline)
        encoder.setFragmentBytes(&params, length: MemoryLayout<ReaderRipplePageTurnView.Parameters>.stride, index: 0)
        encoder.setFragmentTexture(oldTexture, index: 0)
        encoder.setFragmentTexture(newTexture, index: 1)
        encoder.drawPrimitives(type: .triangleStrip, vertexStart: 0, vertexCount: 4)
        encoder.endEncoding()
        buffer.present(drawable)
        buffer.commit()
    }

    /// Draws the image into a BGRA buffer whose first row is the image's top row —
    /// CoreGraphics would otherwise hand back the bottom row first and every page
    /// would come out upside down.
    private static func texture(from image: UIImage, device: MTLDevice, reusing existing: MTLTexture?) -> MTLTexture? {
        guard let cgImage = image.cgImage else { return nil }
        let width = cgImage.width
        let height = cgImage.height
        guard width > 0, height > 0 else { return nil }

        let bytesPerRow = width * 4
        guard let context = CGContext(
            data: nil,
            width: width,
            height: height,
            bitsPerComponent: 8,
            bytesPerRow: bytesPerRow,
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedFirst.rawValue | CGBitmapInfo.byteOrder32Little.rawValue
        ) else { return nil }

        context.translateBy(x: 0, y: CGFloat(height))
        context.scaleBy(x: 1, y: -1)
        context.interpolationQuality = .high
        context.draw(cgImage, in: CGRect(x: 0, y: 0, width: width, height: height))
        guard let data = context.data else { return nil }

        let texture: MTLTexture
        if let existing, existing.width == width, existing.height == height {
            texture = existing
        } else {
            let descriptor = MTLTextureDescriptor.texture2DDescriptor(
                pixelFormat: .bgra8Unorm,
                width: width,
                height: height,
                mipmapped: false
            )
            descriptor.usage = .shaderRead
            guard let created = device.makeTexture(descriptor: descriptor) else { return nil }
            texture = created
        }
        // `data` points into the context's own backing store, which dies with the
        // context — and ARC may release it right after the last use of `context`. The
        // upload has to happen while the context is provably alive.
        withExtendedLifetime(context) {
            texture.replace(
                region: MTLRegionMake2D(0, 0, width, height),
                mipmapLevel: 0,
                withBytes: data,
                bytesPerRow: bytesPerRow
            )
        }
        return texture
    }
}
