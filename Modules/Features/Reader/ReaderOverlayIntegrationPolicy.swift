import Foundation

struct ReaderBarVisibility: Equatable, Sendable {
    var showsHeader: Bool
    var showsFooter: Bool
}

enum ReaderOverlayPresentationPolicy {

    /// Whether each bar is drawn — and, by the same call, whether the paginator
    /// reserves space for it.
    ///
    /// **There is deliberately no `isScrolling` parameter.** The bars used to be
    /// free-positioned components that only paged mode drew, which is why scroll
    /// mode had no header or footer at all. Bars are structural: the text area is
    /// inset by their height in both modes, exactly as legado's
    /// `view_book_page.xml` constrains its `ContentTextView` between the two
    /// dividers and then scrolls only the content.
    ///
    /// Both the renderer and `ReaderLayoutMetrics` must ask this one function. If
    /// they ever disagree, the text either slides under a bar or leaves a blank
    /// strip where one was reserved but never drawn.
    static func visibility(
        layout: ReaderBarLayout,
        headerEnabled: Bool,
        footerEnabled: Bool,
        isChapterOpeningPage: Bool
    ) -> ReaderBarVisibility {
        let layout = layout.resolved(isChapterOpening: isChapterOpeningPage)
        return ReaderBarVisibility(
            showsHeader: headerEnabled
                && layout.hasContent(in: .header),
            showsFooter: footerEnabled && layout.hasContent(in: .footer)
        )
    }

    /// `alwaysShowsStatusBar` is the user-facing 顯示系統狀態欄 switch: when it is on
    /// the clock, signal and battery stay on the reading page even with the reader's
    /// own bars hidden. Editing still takes priority — the touch-zone editor is a
    /// full-screen surface with its own controls. Callers that do not pass it keep
    /// the original immersive rule, which is what `hidesHomeIndicator` wants: the
    /// indicator keeps following the chrome regardless of this switch.
    static func hidesStatusBar(
        showsReaderChrome: Bool,
        isEditing: Bool,
        alwaysShowsStatusBar: Bool = false
    ) -> Bool {
        if isEditing { return true }
        if alwaysShowsStatusBar { return false }
        return !showsReaderChrome
    }

    /// The home indicator keeps following the reader's own bars, independently of
    /// 顯示系統狀態欄: turning that switch on pins the status bar but leaves the
    /// indicator fading with the chrome — the two now diverge by design. Its own
    /// entry point keeps the call site from reading a status-bar rule to decide a
    /// home-indicator question, and the two-argument `hidesStatusBar` call below
    /// uses that function's default, i.e. the original immersive rule.
    static func hidesHomeIndicator(
        showsReaderChrome: Bool,
        isEditing: Bool
    ) -> Bool {
        hidesStatusBar(showsReaderChrome: showsReaderChrome, isEditing: isEditing)
    }
}
