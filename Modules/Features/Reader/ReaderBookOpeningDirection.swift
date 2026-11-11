import YueduCoreText
import CoreGraphics
import Foundation

// MARK: - ReaderBookOpeningDirection
//
// Which side the book's spine is on, so the open animation unfolds toward
// the correct edge:
//
//   - `.leftSpine`  (右开书 / 西式 / LTR): 翻开时左侧是书脊,封面从右向左翻
//     等同于一本装订在左侧的书,打开时页面从左往右展开。
//   - `.rightSpine` (左开书 / 日式直排 / RTL): 书脊在右侧,封面从左向右翻,
//     打开时页面从右往左展开。
//
// 选取依据:直排写作模式 (verticalRTL) 或 EPUB page-progression rtl 视为
// 右侧书脊;否则左侧书脊。

enum ReaderBookOpeningDirection: Equatable {
    case leftSpine
    case rightSpine

    /// 书由右往左读（`BookDirection.isRTL`）＝书脊在右。
    static func resolve(isRTL: Bool) -> ReaderBookOpeningDirection {
        isRTL ? .rightSpine : .leftSpine
    }

    /// 依书本写作模式与 EPUB 方向决定开书方向。
    static func resolve(
        writingMode: ReaderWritingMode,
        pageProgressionIsRTL: Bool
    ) -> ReaderBookOpeningDirection {
        let rtl = writingMode.isVertical || pageProgressionIsRTL
        return rtl ? .rightSpine : .leftSpine
    }
}

// MARK: - ReaderBookOpeningPose

/// Direction-aware, reversible book-opening state. Opening and interactive
/// closing both evaluate this same model, so a gesture can stop or reverse at
/// any point without jumping between separately queued animations.
///
/// The pose models a physical paperback: the live reader page scales with
/// the growing card (small to large, always rendering real content), the
/// cover hinges just past perpendicular across most of the gesture without
/// being clipped by the card, and a soft spine shadow on the paper peaks
/// while the cover hovers mid-lift.
struct ReaderBookOpeningPose: Equatable {
    /// Front-cover hinge in unit coordinates (`0` = left, `1` = right).
    let coverAnchorX: CGFloat
    /// Signed 3D rotation around the Y axis. Spine sides are exact mirrors.
    let coverRotationY: CGFloat
    /// Opacity of the rotating front cover. Back-face culling already hides
    /// it past 90°; this is the trailing safety fade.
    let coverOpacity: CGFloat
    /// Spine shadow that builds during the unfold and fades at both endpoints.
    let spineShadowOpacity: CGFloat
    /// Darkening of the front cover as it turns away from the light, so the
    /// hinge reads as a lit, physical board rather than a flat card.
    let coverShadeOpacity: CGFloat

    /// Darkest the cover gets, reached at the peak angle. 0.38 made the lifted
    /// cover read as a grey board; 0.18 keeps the artwork's colours while the
    /// hinge still catches the light.
    static let maxCoverShade: CGFloat = 0.18

    /// Peak hinge angle (~108°): just past perpendicular, so the cover stays
    /// visible for most of the motion and back-face culling retires it.
    private static let maxCoverRotation: CGFloat = .pi * 0.60

    static func interpolate(
        progress: CGFloat,
        direction: ReaderBookOpeningDirection
    ) -> ReaderBookOpeningPose {
        let p = ReaderCardTransitionMath.clampProgress(progress)
        // The card lifts and grows first (frame/shadow phases live in
        // ReaderCardVisualState); the cover starts hinging shortly after and
        // keeps turning until nearly the end of the transition.
        let unfold = ReaderCardTransitionMath.phase(p, in: 0.14...0.90)
        let coverFade = ReaderCardTransitionMath.phase(p, in: 0.84...0.97)

        let anchorX: CGFloat
        let rotationSign: CGFloat
        switch direction {
        case .leftSpine:
            anchorX = 0
            rotationSign = -1
        case .rightSpine:
            anchorX = 1
            rotationSign = 1
        }

        // Tied to the unfold (not raw progress) so paper is flat and unshaded
        // exactly when the cover is at rest; exact zeros at the endpoints
        // because sin(π·x) leaves floating-point residue.
        let spineShadow: CGFloat
        if unfold <= 0 || unfold >= 1 {
            spineShadow = 0
        } else {
            spineShadow = 0.35 * sin(.pi * unfold)
        }

        // Lambert-style falloff, 1 − cos θ: none while the cover lies flat,
        // deepening as it turns edge-on. Past 90° the cover is culled anyway.
        let angle = maxCoverRotation * unfold
        let coverShade = unfold <= 0 ? 0 : maxCoverShade * (1 - cos(angle))

        return ReaderBookOpeningPose(
            coverAnchorX: anchorX,
            coverRotationY: rotationSign * angle,
            coverOpacity: 1 - coverFade,
            spineShadowOpacity: spineShadow,
            coverShadeOpacity: min(coverShade, maxCoverShade)
        )
    }
}
