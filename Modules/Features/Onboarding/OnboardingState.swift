import Foundation
import Observation

/// 新手导览 (maintainer, 2026-10-24): what the app is and how it is used, 探索 first, in six
/// pages a reader can skip at any point, the last one opening where they choose to start.
/// Shown once on each device, to a new install and to a reader updating from an earlier
/// version alike, and again from 设置 → 关于.
///
/// Its own key rather than a `GlobalSettings` value, which the settings sync and export carry:
/// having seen the tour on one device says nothing about another.
@MainActor
@Observable
final class OnboardingState {
    /// UI tests launch with `-onboarding.completed YES` to start on the tabs.
    static let completedKey = "onboarding.completed"

    /// Whether the tour is on screen.
    private(set) var isPresented: Bool
    /// A choice from the last page that opens a page past its tab, until that tab takes it.
    private(set) var pendingStart: OnboardingStart?

    private let defaults: UserDefaults

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        isPresented = !defaults.bool(forKey: Self.completedKey)
    }

    /// 设置 → 关于 → 新手导览.
    func replay() {
        isPresented = true
    }

    /// Skipped, finished, or left through one of the last page's choices.
    func finish(startingAt start: OnboardingStart?) {
        defaults.set(true, forKey: Self.completedKey)
        isPresented = false
        pendingStart = start?.opensPage == true ? start : nil
    }

    /// True once, for the tab whose page `start` opens: that tab opens it, and nothing else does.
    func take(_ start: OnboardingStart) -> Bool {
        guard pendingStart == start else { return false }
        pendingStart = nil
        return true
    }
}

/// The tour's pages, in order.
enum OnboardingPage: Int, CaseIterable, Identifiable {
    case welcome
    /// 从探索找书.
    case explore
    /// 一部作品，一个页面: 搜寻 and 作品详情 by the work.
    case works
    /// 连接你的所有资源.
    case sources
    /// 长时间阅读也舒服.
    case reading
    case start

    var id: Int { rawValue }
}

/// Where the last page sends the reader: a tab, and on 书架 and 资源库 the page past it.
enum OnboardingStart: String, CaseIterable, Identifiable {
    case explore
    case addSources
    case connectLibrary
    case importFiles

    var id: String { rawValue }

    var tab: RootTabItem {
        switch self {
        case .explore: return .explore
        case .addSources, .connectLibrary: return .library
        case .importFiles: return .bookshelf
        }
    }

    /// 资源库's 来源配置管理 and 远端书库, and 书架's 添加书籍, are a page past the tab; 探索 is
    /// the tab itself.
    var opensPage: Bool { self != .explore }

    var titleKey: String {
        switch self {
        case .explore: return "去探索找书"
        // What 来源配置管理's 「＋」 is called, as 设置 adds one (2026-10-27).
        case .addSources: return "新增来源配置"
        case .connectLibrary: return "连接书库"
        // 添加书籍's own tab, by its name.
        case .importFiles: return "汇入文件"
        }
    }

    var detailKey: String {
        switch self {
        case .explore: return "看看首页帮你排好的书"
        case .addSources: return "从档案或网址汇入，也能手动新增"
        case .connectLibrary: return "连上 WebDAV、OPDS 或 Calibre"
        case .importFiles: return "把 TXT、EPUB、PDF、漫画或有声书加入书架"
        }
    }
}
