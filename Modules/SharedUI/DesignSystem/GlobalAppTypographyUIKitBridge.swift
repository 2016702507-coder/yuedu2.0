import UIKit

@MainActor
enum GlobalAppTypographyUIKitBridge {
    /// Pushes the user's global font choice into the UIKit chrome (navigation
    /// bars, tab bars) that SwiftUI's `.font` cannot reach.
    ///
    /// A `nil` font means "no custom font selected" — the default — and
    /// *removes* the override instead of re-stating the system font. Writing
    /// any explicit font into `titleTextAttributes` replaces UIKit's own
    /// Dynamic-Type behavior, so the custom tab font below deliberately stays
    /// at its semantic base size while the bar keeps its normal fixed height.
    static func apply(postScriptName: String?) {
        let titleFont = chromeFont(.headline, postScriptName: postScriptName, weight: .semibold)
        let largeTitleFont = chromeFont(.largeTitle, postScriptName: postScriptName, weight: .bold)
        let tabFont = tabBarFont(postScriptName: postScriptName)

        updateAppearanceProxies(
            titleFont: titleFont,
            largeTitleFont: largeTitleFont,
            tabFont: tabFont
        )

        let roots = UIApplication.shared.connectedScenes
            .compactMap { $0 as? UIWindowScene }
            .flatMap(\.windows)
            .compactMap(\.rootViewController)
        var visited = Set<ObjectIdentifier>()
        for root in roots {
            apply(
                to: root,
                titleFont: titleFont,
                largeTitleFont: largeTitleFont,
                tabFont: tabFont,
                visited: &visited
            )
        }
    }

    /// A tab bar keeps its normal fixed height at every content-size category.
    /// Keep a custom title face at caption2's base size so Dynamic Type cannot
    /// enlarge it into the icon. A nil selection still removes the override
    /// and gives UIKit full control of the system tab font.
    static func tabBarFont(postScriptName: String?) -> UIFont? {
        guard let postScriptName else { return nil }
        return GlobalAppTypography.unscaledUIFont(
            .caption2,
            postScriptName: postScriptName
        )
    }

    /// Bar chrome lays out at a fixed height, so a custom font has to stop
    /// growing where the system's own bar title does rather than scaling
    /// without bound.
    private static func chromeFont(
        _ style: GlobalAppTypography.Style,
        postScriptName: String?,
        weight: UIFont.Weight? = nil
    ) -> UIFont? {
        guard let postScriptName else { return nil }
        return GlobalAppTypography.uiFont(
            style,
            postScriptName: postScriptName,
            weight: weight,
            maximumPointSize: GlobalAppTypography.chromeMaximumPointSize(style)
        )
    }

    private static func updateAppearanceProxies(
        titleFont: UIFont?,
        largeTitleFont: UIFont?,
        tabFont: UIFont?
    ) {
        let navigationBar = UINavigationBar.appearance()
        navigationBar.titleTextAttributes = merging(
            font: titleFont,
            into: navigationBar.titleTextAttributes
        )
        navigationBar.largeTitleTextAttributes = merging(
            font: largeTitleFont,
            into: navigationBar.largeTitleTextAttributes
        )

        let tabItem = UITabBarItem.appearance()
        if let tabFont {
            tabItem.setTitleTextAttributes([.font: tabFont], for: .normal)
            tabItem.setTitleTextAttributes([.font: tabFont], for: .selected)
        } else {
            tabItem.setTitleTextAttributes(nil, for: .normal)
            tabItem.setTitleTextAttributes(nil, for: .selected)
        }

        let tabBar = UITabBar.appearance()
        // 全局玻璃总闸（参考待改清单第 13 条）：关掉玻璃时恢复系统默认底栏，
        // 不再碰任何透明/材质配置 —— iOS 17 等旧系统遇到玻璃渲染异常时的一键兜底。
        // 开启时才是「完全透明玻璃」：清掉系统默认灰底/毛玻璃/阴影/选中态药丸底。
        guard GlobalSettings.shared.interfaceFrostedGlass else {
            let systemAppearance = UITabBarAppearance()
            systemAppearance.configureWithDefaultBackground()
            tabBar.standardAppearance = systemAppearance
            tabBar.scrollEdgeAppearance = systemAppearance
            tabBar.isTranslucent = true
            return
        }
        let tabBarAppearance = UITabBarAppearance()
        tabBarAppearance.configureWithTransparentBackground()
        tabBarAppearance.backgroundEffect = nil
        tabBarAppearance.backgroundColor = .clear
        tabBarAppearance.shadowColor = nil
        tabBarAppearance.shadowImage = nil
        tabBarAppearance.backgroundImage = nil
        tabBar.standardAppearance = tabBarAppearance
        tabBar.scrollEdgeAppearance = tabBarAppearance
        // 强制走半透明通道，杜绝任何不透明兜底背景
        tabBar.isTranslucent = true
        // 连每个标签项（含选中态）背后的高亮药丸底/背景图也清掉，只保留红字+彩图标的选中态
        for layout in [tabBarAppearance.stackedLayoutAppearance,
                       tabBarAppearance.inlineLayoutAppearance,
                       tabBarAppearance.compactInlineLayoutAppearance] {
            layout.normal.backgroundColor = .clear
            layout.normal.backgroundImage = nil
            layout.selected.backgroundColor = .clear
            layout.selected.backgroundImage = nil
        }
    }

    private static func apply(
        to controller: UIViewController,
        titleFont: UIFont?,
        largeTitleFont: UIFont?,
        tabFont: UIFont?,
        visited: inout Set<ObjectIdentifier>
    ) {
        let identifier = ObjectIdentifier(controller)
        guard visited.insert(identifier).inserted else { return }

        if let navigationController = controller as? UINavigationController {
            update(
                navigationController.navigationBar,
                titleFont: titleFont,
                largeTitleFont: largeTitleFont
            )
        }
        if let tabController = controller as? UITabBarController {
            update(tabController.tabBar, font: tabFont)
        }

        for child in controller.children {
            apply(
                to: child,
                titleFont: titleFont,
                largeTitleFont: largeTitleFont,
                tabFont: tabFont,
                visited: &visited
            )
        }
        if let presented = controller.presentedViewController {
            apply(
                to: presented,
                titleFont: titleFont,
                largeTitleFont: largeTitleFont,
                tabFont: tabFont,
                visited: &visited
            )
        }
    }

    private static func update(
        _ navigationBar: UINavigationBar,
        titleFont: UIFont?,
        largeTitleFont: UIFont?
    ) {
        navigationBar.titleTextAttributes = merging(
            font: titleFont,
            into: navigationBar.titleTextAttributes
        )
        navigationBar.largeTitleTextAttributes = merging(
            font: largeTitleFont,
            into: navigationBar.largeTitleTextAttributes
        )
        navigationBar.standardAppearance = navigationAppearance(
            navigationBar.standardAppearance,
            titleFont: titleFont,
            largeTitleFont: largeTitleFont
        )
        navigationBar.compactAppearance = navigationBar.compactAppearance.map {
            navigationAppearance(
                $0,
                titleFont: titleFont,
                largeTitleFont: largeTitleFont
            )
        }
        navigationBar.scrollEdgeAppearance = navigationBar.scrollEdgeAppearance.map {
            navigationAppearance(
                $0,
                titleFont: titleFont,
                largeTitleFont: largeTitleFont
            )
        }
        navigationBar.compactScrollEdgeAppearance = navigationBar.compactScrollEdgeAppearance.map {
            navigationAppearance(
                $0,
                titleFont: titleFont,
                largeTitleFont: largeTitleFont
            )
        }
    }

    private static func navigationAppearance(
        _ source: UINavigationBarAppearance,
        titleFont: UIFont?,
        largeTitleFont: UIFont?
    ) -> UINavigationBarAppearance {
        let copy = source.copy()
        copy.titleTextAttributes = merging(
            font: titleFont,
            into: copy.titleTextAttributes
        )
        copy.largeTitleTextAttributes = merging(
            font: largeTitleFont,
            into: copy.largeTitleTextAttributes
        )
        return copy
    }

    private static func update(_ tabBar: UITabBar, font: UIFont?) {
        tabBar.items?.forEach { item in
            item.setTitleTextAttributes(
                merging(font: font, into: item.titleTextAttributes(for: .normal)),
                for: .normal
            )
            item.setTitleTextAttributes(
                merging(font: font, into: item.titleTextAttributes(for: .selected)),
                for: .selected
            )
        }
        // 全局玻璃总闸关闭时：重建系统默认 appearance，实例层也不再做透明化，
        // 彻底规避 iOS 17 等旧系统的玻璃渲染异常（参考待改清单第 13 条）。
        guard GlobalSettings.shared.interfaceFrostedGlass else {
            let systemAppearance = UITabBarAppearance()
            systemAppearance.configureWithDefaultBackground()
            for layout in [systemAppearance.stackedLayoutAppearance,
                           systemAppearance.inlineLayoutAppearance,
                           systemAppearance.compactInlineLayoutAppearance] {
                layout.normal.titleTextAttributes = merging(font: font, into: layout.normal.titleTextAttributes)
                layout.selected.titleTextAttributes = merging(font: font, into: layout.selected.titleTextAttributes)
            }
            tabBar.standardAppearance = systemAppearance
            tabBar.scrollEdgeAppearance = systemAppearance
            tabBar.isTranslucent = true
            return
        }
        let newStandard = tabAppearance(tabBar.standardAppearance, font: font)
        tabBar.standardAppearance = newStandard
        // Keep scrollEdgeAppearance in sync; when nil, the system provides a
        // default transparent appearance that differs from the modified
        // standard, causing white/transparent flicker on scroll.
        let scrollSource = tabBar.scrollEdgeAppearance ?? newStandard
        tabBar.scrollEdgeAppearance = tabAppearance(scrollSource, font: font)
        // 彻底透明：强制半透明通道，杜绝任何不透明兜底背景与残留磨砂（参考待改清单第 11 条）。
        tabBar.isTranslucent = true
    }

    private static func tabAppearance(
        _ source: UITabBarAppearance,
        font: UIFont?
    ) -> UITabBarAppearance {
        let copy = source.copy()
        let itemAppearances = [
            copy.stackedLayoutAppearance,
            copy.inlineLayoutAppearance,
            copy.compactInlineLayoutAppearance,
        ]
        for itemAppearance in itemAppearances {
            itemAppearance.normal.titleTextAttributes = merging(
                font: font,
                into: itemAppearance.normal.titleTextAttributes
            )
            itemAppearance.selected.titleTextAttributes = merging(
                font: font,
                into: itemAppearance.selected.titleTextAttributes
            )
            // 最透：连每个标签项（含选中态）背后的高亮药丸底/背景图也清掉，
            // 只保留红字+彩图标的选中态，不残留任何不透明块（参考待改清单第 11 条）。
            itemAppearance.normal.backgroundColor = .clear
            itemAppearance.normal.backgroundImage = nil
            itemAppearance.selected.backgroundColor = .clear
            itemAppearance.selected.backgroundImage = nil
        }
        // 底部导航栏完全透明：去掉系统默认的灰底、毛玻璃与阴影，让背后山影/正文直接透出，
        // 与藏书页「继续阅读」按钮、分类标签栏同一套透明玻璃语言（参考待改清单第 7、10 条）。
        // 只清背景，不动图标/文字的选中态（选中项仍以红色文字+彩色图标表明当前页）。
        // 关键：backgroundEffect = nil 把 iOS 26 液态玻璃那层磨砂彻底拿掉，否则仍有一层雾。
        copy.backgroundColor = .clear
        copy.backgroundEffect = nil
        copy.shadowColor = nil
        copy.shadowImage = nil
        copy.backgroundImage = nil
        return copy
    }

    /// Merges `font` into `attributes`, or strips the font key when `font` is
    /// `nil` so UIKit falls back to its own clamped bar title font.
    private static func merging(
        font: UIFont?,
        into attributes: [NSAttributedString.Key: Any]?
    ) -> [NSAttributedString.Key: Any] {
        var result = attributes ?? [:]
        if let font {
            result[.font] = font
        } else {
            result.removeValue(forKey: .font)
        }
        return result
    }
}
