import SwiftUI

/// 书签加入／移除之后跳出来的提示。
///
/// 顶部书签钮、触控区、翻页模式的下拉三种方式都走 `toggleCurrentPageBookmark()`，
/// 提示就只在那里发一次，每一种方式得到的回馈都一样。
struct ReaderBookmarkToast: Equatable, Identifiable {
    let id = UUID()
    let isAdded: Bool

    /// 提示本身的寿命——它就是一段时间，不是在等什么状态稳定。
    static let displayDuration: Duration = .milliseconds(1400)

    var titleKey: String { isAdded ? "已加入书签" : "已移除书签" }
    var systemImage: String { isAdded ? "bookmark.fill" : "bookmark.slash" }
}

/// 一颗不挡手的胶囊，贴在画面顶端、动态岛正下方。
struct ReaderBookmarkToastView: View {
    let toast: ReaderBookmarkToast
    /// The reader theme's scheme, not the system's: a night page under a light
    /// system appearance still needs the dark material.
    let colorScheme: ColorScheme

    var body: some View {
        Label {
            Text(localized(toast.titleKey))
                .foregroundStyle(.primary)
        } icon: {
            Image(systemName: toast.systemImage)
                .foregroundStyle(
                    toast.isAdded ? Color(uiColor: ReaderBookmarkRibbon.color) : Color.secondary
                )
        }
        .font(DSFont.subheadline.weight(.semibold))
        .padding(.horizontal, DSSpacing.lg)
        .padding(.vertical, DSSpacing.md)
        .background(.regularMaterial, in: Capsule())
        .shadow(color: DSColor.shadow, radius: DSSpacing.sm, y: DSSpacing.xs)
        .environment(\.colorScheme, colorScheme)
        // VoiceOver hears it as an announcement when it appears; a focusable element
        // that vanishes a second later would only strand the cursor.
        .accessibilityHidden(true)
    }
}

#Preview("已加入") {
    ReaderBookmarkToastView(toast: ReaderBookmarkToast(isAdded: true), colorScheme: .light)
        .padding()
}

#Preview("已移除・夜間") {
    ReaderBookmarkToastView(toast: ReaderBookmarkToast(isAdded: false), colorScheme: .dark)
        .padding()
        .background(Color.black)
}
