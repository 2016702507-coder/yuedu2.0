import Foundation
import SwiftUI
import UIKit

// MARK: - ReaderOpeningTransitionDelegate

/// 让「从任意入口打开阅读器」都走书架那张封面翻开的卡片：present 用 `.push`、
/// dismiss 用 `.pop`，直接复用 `ReaderCardTransitionAnimator`，所以视觉与书架
/// 完全一致，不需要另写一套仿制动画。
///
/// `UIViewController.transitioningDelegate` 是 weak，实例由 `ReaderOpener` 强持有，
/// 直到下一次打开覆盖它（dismiss 动画期间也仍在）。
@MainActor
final class ReaderOpeningTransitionDelegate: NSObject, UIViewControllerTransitioningDelegate {
    private let source: ReaderTransitionSource

    init(source: ReaderTransitionSource) {
        self.source = source
        super.init()
    }

    func animationController(
        forPresented presented: UIViewController,
        presenting: UIViewController,
        source: UIViewController
    ) -> UIViewControllerAnimatedTransitioning? {
        ReaderCardTransitionAnimator(operation: .push, source: self.source) { _ in }
    }

    func animationController(
        forDismissed dismissed: UIViewController
    ) -> UIViewControllerAnimatedTransitioning? {
        ReaderCardTransitionAnimator(operation: .pop, source: source) { _ in }
    }
}

// MARK: - ReaderOpener

/// 所有非书架入口打开阅读器的统一入口：首页继续阅读、作品详情、搜索、探索、
/// 公共书库、远端书库、导入、浏览器……都从这里 present 同一个带封面翻开转场的
/// `ReaderHostingController`。
///
/// 返回 `false` 时调用方回落到它自己原来的 fullScreenCover / push 路径，因此
/// 任何入口都不会因为转场暂时不可用而打不开书（听书、视频保持专用播放器）。
@MainActor
enum ReaderOpener {
    /// weak 的 transitioningDelegate 需要有人强持有。
    private static var activeDelegate: ReaderOpeningTransitionDelegate?
    private static var activeHost: ReaderHostingController?
    /// 外部宿主（Open In 导入流程）自己 present，也要有人强持有它的 delegate。
    private static var attachedDelegates: [ReaderOpeningTransitionDelegate] = []
    private static var isOpening = false

    private static var isPresenting: Bool {
        activeHost?.presentingViewController != nil
    }

    /// 主实现（主 actor 隔离），由下面的 nonisolated 转发入口调用。
    @discardableResult
    private static func openOnMainActor(
        bookID: UUID,
        store: BookStore,
        dependencies: AppDependencies,
        tabBarVisibility: RootTabBarVisibility?,
        coverFrame: CGRect?,
        coverImage: UIImage?,
        openingTOCTarget: ReaderTOCTarget?,
        onDismiss: (@MainActor () -> Void)?
    ) -> Bool {
        guard !isOpening, !isPresenting else { return false }
        guard let book = store.readingBook(id: bookID) else { return false }
        // 听书 / 视频有各自的播放器，保持原路径。
        let kind = book.resolvedPipelineKind
        guard kind != .audio, kind != .video else { return false }
        guard let presenter = topPresenter() else { return false }

        let colorScheme: ColorScheme = presenter.traitCollection.userInterfaceStyle == .dark
            ? .dark : .light
        let image = coverImage ?? BookshelfCoverStyle.snapshot(
            for: book,
            drawn: nil,
            colorScheme: colorScheme,
            sourceSize: coverFrame?.size
        )
        let source = ReaderTransitionSource(
            bookID: bookID,
            cornerRadius: DSRadius.md,
            frame: coverFrame,
            snapshot: image,
            direction: .leftSpine
        )

        let host = ReaderHostingController(content: AnyView(
            BookReaderView(bookId: bookID, openingTOCTarget: openingTOCTarget)
                .environmentObject(store)
                .environment(\.appDependencies, dependencies)
                // nil navigator 让阅读器用自己的 presentationMode 关闭，
                // dismiss 会走 transitioningDelegate 的 .pop 卡片合上动画。
                .environment(\.readerNavigator, nil)
                .environment(\.rootTabBarVisibility, tabBarVisibility)
                .onDisappear {
                    ReaderOpener.activeHost = nil
                    onDismiss?()
                }
        ))
        host.modalPresentationStyle = .fullScreen
        let delegate = ReaderOpeningTransitionDelegate(source: source)
        host.transitioningDelegate = delegate
        activeDelegate = delegate
        activeHost = host
        isOpening = true
        presenter.present(host, animated: true) {
            onMain { isOpening = false }
        }
        // present 被 UIKit 静默丢弃时的兜底，避免 isOpening 一直挡住后续打开。
        Task { @MainActor in
            try? await Task.sleep(for: .seconds(2))
            if isOpening { isOpening = false }
        }
        return true
    }

    /// 任意上下文都能调用的转发入口：Swift 6 严格并发下，非主 actor 隔离的
    /// UIKit 回调 / 异步完成块也能安全调用。所有这些回调都在主线程触发。
    ///
    /// - Parameters:
    ///   - coverFrame: 书封在 window 坐标系中的 frame；nil 时卡片从屏幕中央展开。
    ///   - coverImage: 入口已经拿到的真实封面；nil 时按书封缓存 / 生成封面取一张，
    ///     绝不会退化成灰色占位卡。
    ///   - onDismiss: 阅读器关闭后执行，把原入口的 onDismiss 逻辑原样传进来。
    @discardableResult
    nonisolated static func open(
        bookID: UUID,
        store: BookStore,
        dependencies: AppDependencies = .live,
        tabBarVisibility: RootTabBarVisibility? = nil,
        coverFrame: CGRect? = nil,
        coverImage: UIImage? = nil,
        openingTOCTarget: ReaderTOCTarget? = nil,
        onDismiss: (@MainActor () -> Void)? = nil
    ) -> Bool {
        onMain {
            openOnMainActor(
                bookID: bookID,
                store: store,
                dependencies: dependencies,
                tabBarVisibility: tabBarVisibility,
                coverFrame: coverFrame,
                coverImage: coverImage,
                openingTOCTarget: openingTOCTarget,
                onDismiss: onDismiss
            )
        }
    }

    /// 主线程保护：UI 调用都在主线程，个别导入 / 下载回调可能不是。
    /// 与 TTSCoordinator 的写法一致，避免 `assumeIsolated` 在非主线程崩溃。
    nonisolated private static func onMain<T: Sendable>(_ work: @MainActor () -> T) -> T {
        if Thread.isMainThread { return MainActor.assumeIsolated(work) }
        return DispatchQueue.main.sync { MainActor.assumeIsolated(work) }
    }

    /// 给外部已经构造好的全屏宿主挂同一套转场（Open In 导入流程自己 present）。
    @discardableResult
    nonisolated static func attach(
        to host: UIViewController,
        bookID: UUID,
        store: BookStore
    ) -> Bool {
        onMain {
            attachOnMainActor(to: host, bookID: bookID, store: store)
        }
    }

    @MainActor
    private static func attachOnMainActor(
        to host: UIViewController,
        bookID: UUID,
        store: BookStore
    ) -> Bool {
        guard let book = store.readingBook(id: bookID) else { return false }
        let kind = book.resolvedPipelineKind
        guard kind != .audio, kind != .video else { return false }
        let colorScheme: ColorScheme = host.traitCollection.userInterfaceStyle == .dark
            ? .dark : .light
        let image = BookshelfCoverStyle.snapshot(
            for: book,
            drawn: nil,
            colorScheme: colorScheme
        )
        let source = ReaderTransitionSource(
            bookID: bookID,
            cornerRadius: DSRadius.md,
            snapshot: image,
            direction: .leftSpine
        )
        let delegate = ReaderOpeningTransitionDelegate(source: source)
        host.transitioningDelegate = delegate
        // transitioningDelegate 是 weak；保留最近几个直到它们的转场结束。
        attachedDelegates.append(delegate)
        if attachedDelegates.count > 4 { attachedDelegates.removeFirst() }
        return true
    }

    /// 当前可用来 present 的最上层控制器；跳过正在 dismiss 的那一层。
    private static func topPresenter() -> UIViewController? {
        let scenes = UIApplication.shared.connectedScenes
            .compactMap { $0 as? UIWindowScene }
        let scene = scenes.first { $0.activationState == .foregroundActive } ?? scenes.first
        guard let root = scene?.windows.first(where: \.isKeyWindow)?.rootViewController
            ?? scene?.windows.first?.rootViewController
        else { return nil }
        var top = root
        while let presented = top.presentedViewController, !presented.isBeingDismissed {
            top = presented
        }
        return top
    }
}
