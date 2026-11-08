import Foundation

/// Visibility rules for reader customization surfaces that should not be
/// discoverable until the single Yuedu Pro entitlement is active.
struct ReaderPremiumVisibilityPolicy {
    let isProActive: Bool

    var showsReaderDecoration: Bool { isProActive }
    var showsBottomTabCustomization: Bool { isProActive }
    var showsBackgroundImageImport: Bool { isProActive }
    var showsLayoutPresetImport: Bool { isProActive }
    var showsTouchZoneEditor: Bool { isProActive }

    /// 新增／编辑段落笔记。**只锁入口**：已经写过的笔记，圆圈照常画、内容照常读得到，
    /// 过期只是不能再改——和专案其他 Pro 功能一样，不动使用者已经产生的资料。
    var allowsParagraphNoteEditing: Bool { isProActive }

    /// Every AI feature (`PremiumFeature.aiReading`). Without Pro the only AI entries left
    /// are the reader's top menu and the bookshelf menu, marked Pro and opening the paywall.
    /// Chapter translations already made stay stored but are not laid out; the book's
    /// setting is kept for when Pro returns — a lapsed reader must not be stuck with a
    /// translated page behind a paywalled sheet.
    var allowsAI: Bool { isProActive }

    /// 汇入字体 (`PremiumFeature.customFonts`). Only the entry is locked — shown with a lock,
    /// opening the paywall: fonts imported earlier stay selectable and keep rendering.
    var allowsFontImport: Bool { isProActive }

    /// 问 AI／解释／查词／翻译 in the text-selection menu. Hidden rather than locked: a
    /// paywall on every highlight would nag at the one gesture readers repeat most.
    var showsAISelectionActions: Bool { isProActive }

    func showsCommentBubbleSettings(hasParagraphReviews: Bool) -> Bool {
        isProActive && hasParagraphReviews
    }
}
