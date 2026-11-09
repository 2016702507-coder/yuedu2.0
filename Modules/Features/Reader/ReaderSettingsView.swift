import YueduCoreText
import Combine
import SwiftUI
import UIKit

/// 阅读设置的八个分区。`nil` 表示整份设置（浮层里「更多设置」推进来的那一页）；
/// 指定时只画出这几个分区，由浮层的九宫格各自推进来。
enum ReaderSettingsSection: String, CaseIterable, Hashable {
    case scope
    case text
    case layout
    case format
    case headerFooter
    case decoration
    case paging
    case brightness
    case backup

    var titleKey: String {
        switch self {
        case .scope: return "排版生效范围"
        case .text: return "字体与大小"
        case .layout: return "间距"
        case .format: return "格式"
        case .headerFooter: return "页首页尾"
        case .decoration: return "高亮"
        case .paging: return "翻页与手势"
        case .brightness: return "亮度"
        case .backup: return "阅读设置备份"
        }
    }

    var systemImage: String {
        switch self {
        case .scope: return "paintpalette"
        case .text: return "textformat.size"
        case .layout: return "text.alignleft"
        case .format: return "textformat"
        case .headerFooter: return "rectangle.topthird.inset.filled"
        case .decoration: return "highlighter"
        case .paging: return "hand.tap"
        case .brightness: return "sun.max"
        case .backup: return "externaldrive"
        }
    }
}

struct ReaderSettingsView: View {
    @Binding var fontSize: CGFloat
    @Binding var theme: ReaderTheme
    /// 只画出这几个分区；`nil` 是整份设置。
    var sections: Set<ReaderSettingsSection>? = nil
    var readerSafeTop: CGFloat = 0
    var readerSafeBottom: CGFloat = 0
    /// 左右边距's maximum for the page the reader is showing — wider on iPad, where it
    /// reaches the narrow column iPad used to force (`ReaderReadableWidthPolicy`).
    var pageMarginHUpperBound: CGFloat = ReaderReadableWidthPolicy.compactUpperBound
    /// The reader's window, not this sheet's, can show a spread when turned on its side
    /// (`ReaderSpreadPolicy.windowCanHoldSpread`): 页面显示 is offered only then.
    var readerWindowCanHoldSpread = false
    var capabilities: ReaderCapabilities = .reflowableText
    var allowsUserSelectedReaderFont = false
    var usesPublicationFontDefault = false
    var isVerticalWritingMode = false
    /// TXT and online books, which carry no writing mode of their own: 排版方向 shows.
    var allowsVerticalWritingMode = false
    var hasParagraphReviews = false
    var onOpenTouchZoneEditor: (() -> Void)?
    /// Hands an import — a font, a style, a layout — to the reader's first-level presenter.
    /// Nil in contexts that already are one; see `ReaderSettingsPresentationPolicy`.
    var onOpenStyleImporter: ((ReaderStyleImportRoute) -> Void)?
    /// iOS 17: hands the paywall to the reader's first-level presenter, as the importers
    /// above do — a sheet asked for from inside this sheet can be dropped there. Nil where
    /// this view presents it itself.
    var onOpenPaywall: ((PremiumFeature) -> Void)?

    @StateObject private var readerConfig = ReaderConfig.shared
    @Bindable private var settings = GlobalSettings.shared
    @ObservedObject private var subscriptionStore = SubscriptionStore.shared
    @Environment(\.dismiss) private var dismiss
    @State private var paywallFeature: PremiumFeature?
    @State private var layoutImportAlert: LayoutImportAlert?
    @State private var showingOverlayResetConfirmation = false
    @State private var showingLayoutResetConfirmation = false
    /// Set only on iOS 18+, where this sheet can own the picker itself.
    @State private var styleImportRoute: ReaderStyleImportRoute?
    /// 汇出阅读设置's name prompt, and the name typed into it.
    @State private var showingReaderSettingsExport = false
    @State private var readerSettingsExportName = ""

    private var supportsFontSize: Bool { capabilities.contains(.fontSize) }
    private var supportsUserFont: Bool { supportsFontSize && allowsUserSelectedReaderFont }
    private var supportsLineHeight: Bool { capabilities.contains(.lineHeight) }
    private var supportsSpacing: Bool { capabilities.contains(.spacing) }
    /// 套用书本间距 is for EPUB, the one format whose stylesheet sets its own spacing —
    /// the same books that default to the publication's font.
    private var showsBookSpacingToggle: Bool { supportsSpacing && usesPublicationFontDefault }
    private var supportsPageDisplay: Bool {
        readerWindowCanHoldSpread && supportsLineHeight && !settings.scrollMode
    }

    private var readerTint: Color {
        theme.accentColor
    }

    private let previewTextHeight: CGFloat = 220
    private let defaultLineHeightMultiple: CGFloat = 1.65
    private let defaultLetterSpacing: CGFloat = 0
    private let defaultParagraphSpacingMultiplier: CGFloat = 0.8
    static let defaultPageMarginH: CGFloat = 24
    private var defaultPageMarginH: CGFloat { Self.defaultPageMarginH }
    private let defaultPageMarginV: CGFloat = 16

    var body: some View {
        Group {
            if let sections {
                // 由浮层的格子推进来：半屏玻璃卡片，顶上留一段正文可以边调边看。
                detailSheet(sections)
            } else {
                fullSettings
            }
        }
        .tint(readerTint)
        .sheet(item: $paywallFeature) { _ in
            CardKeyUnlockView()
                // The app's accent, not the reader's ink these settings are opened over.
                .tint(DSColor.accent)
        }
        .readerStyleImportPresentation(route: $styleImportRoute) { _ in }
        .alert(item: $layoutImportAlert) { alert in
            Alert(
                title: Text(localized(alert.titleKey)),
                message: Text(alert.message),
                dismissButton: .default(Text(localized("确定")))
            )
        }
        .alert(
            localized("重设页首页尾？"),
            isPresented: $showingOverlayResetConfirmation
        ) {
            Button(localized("重设"), role: .destructive) {
                resetReaderOverlayLayout()
            }
            Button(localized("取消"), role: .cancel) {}
        } message: {
            Text(localized("这会恢复预设的栏位配置与样式。"))
        }
        .alert(
            localized("重设排版？"),
            isPresented: $showingLayoutResetConfirmation
        ) {
            Button(localized("重设"), role: .destructive) {
                resetLayout()
            }
            Button(localized("取消"), role: .cancel) {}
        } message: {
            Text(localized("行距、字距、段距与页面边距会回到预设值。"))
        }
    }

    private func navigationTitle(for sections: Set<ReaderSettingsSection>) -> String {
        sections.count == 1 ? localized(sections.first!.titleKey) : localized("阅读设置")
    }

    /// 全部设置：预览 + 表单。浮层里「更多设置」推进来的就是这一页。
    private var fullSettings: some View {
        NavigationStack {
            VStack(spacing: 0) {
                previewPanel
                Divider()

                // What the text looks like, how it sits on the page, what surrounds it,
                // what decorates it, then how the reader behaves — the order a reader
                // reaches for them. 排版生效范围 comes first because it decides where every
                // change below is kept.
                Form {
                    scopeSection

                    if supportsUserFont || supportsFontSize {
                        textSection
                    }

                    if supportsSpacing || supportsLineHeight {
                        layoutSection
                    }

                    if showsFormatSection {
                        formatSection
                    }

                    headerFooterSection

                    // Pro sections stay in view without Pro, locked: a reader has to see a
                    // feature where it would be used to want it (2026-09-27).
                    readerDecorationSection

                    if showsPagingSection {
                        pagingSection
                    }

                    brightnessSection

                    readerSettingsBackupSection
                }
                // 与所有设置页共用同一块玻璃：清掉 Form 底与导航栏材质，
                // 让 sheet 根部那块 ReaderGlassSheetBackground 透上来。
                .readerGlassSettingsSurface()
                .softScrollEdges()
            }
            .navigationTitle(localized("阅读设置"))
            .toolbarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button {
                        dismiss() // 点击叉叉直接离开
                    } label: {
                        Image(systemName: "xmark")
                    }
                    .accessibilityLabel(localized("关闭"))
                }

                ToolbarItem(placement: .topBarTrailing) {
                    Button { dismiss() } label: {
                        Image(systemName: "checkmark")
                    }
                    .accessibilityLabel(localized("完成"))
                }
            }
        }
    }

    /// 浮层格子推进来的一页：半屏卡片，顶部一小段正文仍然可预览。
    ///
    /// 卡片本身是系统 `Form`，但把它的不透明底去掉、只留分区自己的卡面，
    /// 于是卡与卡之间透出后面的书页（`presentationBackground` 在 `ReaderView` 那侧设），
    /// 一边拖滑杆一边就能看见正文的行距与边距在动。
    private func detailSheet(_ shown: Set<ReaderSettingsSection>) -> some View {
        NavigationStack {
            VStack(spacing: 0) {
                compactPreview
                detailForm(shown)
            }
            .background(Color.clear)
            .navigationTitle(navigationTitle(for: shown))
            .toolbarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button {
                        dismiss()
                    } label: {
                        Image(systemName: "chevron.left")
                    }
                    .accessibilityLabel(localized("返回"))
                }
            }
        }
    }

    /// The paragraph the full sheet shows at 220pt, shortened to the one screenful a
    /// half-height card can spare. Same text, same type: what is being adjusted is
    /// still what the reader sees.
    private var compactPreview: some View {
        Text(localized("  这是一段测试文字，用来测试字体大小和行距、字距、段落间距，以及不同主题下的阅读舒适度。调整设置时，可以观察文字密度、换行节奏与背景对比是否符合你的阅读习惯。"))
            .font(previewFont(size: min(max(fontSize, 17), 24)))
            .lineSpacing(readerConfig.lineSpacing)
            .tracking(readerConfig.letterSpacing)
            .foregroundStyle(theme.textColor)
            .padding(.horizontal, readerConfig.pageMarginH)
            .padding(.top, 16)
            .frame(maxWidth: .infinity, minHeight: 118, maxHeight: 118, alignment: .topLeading)
            .clipped()
            .background(theme.backgroundColor.opacity(0.55))
            .accessibilityHidden(true)
    }

    /// 浮层格子推进来的一页：只画被指定的分区，没有预览、没有关闭钮
    /// （返回由卡片自己的导览列提供）。
    private func detailForm(_ shown: Set<ReaderSettingsSection>) -> some View {
        Form {
            if shown.contains(.scope) { scopeSection }

            if shown.contains(.text), supportsUserFont || supportsFontSize {
                textSection
            }

            if shown.contains(.layout), supportsSpacing || supportsLineHeight {
                layoutSection
            }

            if shown.contains(.format), showsFormatSection { formatSection }

            if shown.contains(.headerFooter) { headerFooterSection }

            if shown.contains(.decoration) { readerDecorationSection }

            if shown.contains(.paging), showsPagingSection { pagingSection }

            if shown.contains(.brightness) { brightnessSection }

            if shown.contains(.backup) { readerSettingsBackupSection }
        }
        // 与所有设置页共用同一块玻璃：清掉 Form 底与导航栏材质，
        // 让 sheet 根部那块 ReaderGlassSheetBackground 透上来。
        .readerGlassSettingsSurface()
        .softScrollEdges()
    }

    private var premiumVisibility: ReaderPremiumVisibilityPolicy {
        ReaderPremiumVisibilityPolicy(isProActive: subscriptionStore.isProActive)
    }

    private var showsCommentBubbleSettings: Bool {
        premiumVisibility.showsCommentBubbleSettings(hasParagraphReviews: hasParagraphReviews)
    }

    /// Paged-only gestures: scroll mode has no page turns and no tap zones.
    private var showsPagingSection: Bool {
        !settings.scrollMode
    }

    // MARK: - 排版生效范围

    /// Where every change below is kept. Named here rather than only on its own page,
    /// because it is what makes a change made under one theme vanish under another.
    private var scopeSection: some View {
        let themeItems = settings.readingSettingsScope.themeItems
        return Section {
            NavigationLink {
                ReadingSettingsScopeView()
            } label: {
                SettingsValueLabel(
                    title: localized("排版生效范围"),
                    systemImage: "paintpalette",
                    value: scopeSummary(themeItems)
                )
            }
        } footer: {
            if !themeItems.isEmpty {
                Text(String(
                    format: localized("跟随主题的设置，改动会存进目前的主题「%@」。"),
                    settings.readingSettingsThemeName
                ))
                .dsSectionFooter()
            }
        }
        .interfaceSectionSurface()
    }

    private func scopeSummary(_ themeItems: Set<ReadingSettingsScopeItem>) -> String {
        if themeItems.isEmpty { return localized("全部跟随全域") }
        if themeItems.count == ReadingSettingsScopeItem.allCases.count { return localized("全部跟随主题") }
        return String(format: localized("%d 项跟随主题"), themeItems.count)
    }

    // MARK: - 文字

    private var textSection: some View {
        Section {
            if supportsUserFont {
                fontSelector
            }

            if supportsFontSize {
                Stepper(value: fontSizeBinding, in: GlobalSettings.readerFontSizeRange, step: 1) {
                    LabeledContent {
                        Text(String(format: localized("ReaderOverlay.Format.Points"), Int(fontSize)))
                            .monospacedDigit()
                            .foregroundStyle(DSColor.textSecondary)
                    } label: {
                        SettingsRowLabel(
                            localized(ReadingSettingsScopeItem.fontSize.titleKey),
                            systemImage: ReadingSettingsScopeItem.fontSize.systemImage
                        )
                    }
                }
            }

            Toggle(isOn: $readerConfig.readerFontBold) {
                SettingsRowLabel(
                    localized(ReadingSettingsScopeItem.bold.titleKey),
                    systemImage: ReadingSettingsScopeItem.bold.systemImage
                )
            }

            ColorPicker(selection: readerTextColorBinding, supportsOpacity: false) {
                SettingsRowLabel(
                    localized(ReadingSettingsScopeItem.textColor.titleKey),
                    systemImage: ReadingSettingsScopeItem.textColor.systemImage
                )
            }

            if hasReaderTextColorOverride {
                Button {
                    setReaderTextColor(nil)
                } label: {
                    SettingsRowLabel(localized("跟随主题文字颜色"), systemImage: "arrow.counterclockwise", role: .action)
                }
            }
        } header: {
            Text(localized("文字"))
                .foregroundStyle(DSColor.textSecondary)
        } footer: {
            Text(String(
                format: localized("文字颜色只套用到目前的阅读背景（%@）。"),
                wornSavedBackground?.name ?? theme.localizedTitle
            ))
            .dsSectionFooter()
        }
        .interfaceSectionSurface()
    }

    /// The saved background on the page, if one is: its text colour is its own, not the
    /// one set for the built-in background under it.
    private var wornSavedBackground: ReaderCustomBackground? {
        theme.activeReaderBackgroundID.flatMap(settings.readerCustomBackground(id:))
    }

    private var hasReaderTextColorOverride: Bool {
        if let background = wornSavedBackground { return background.textColorHex != nil }
        return settings.readerTextColorOverride(for: theme) != nil
    }

    /// Nil goes back to the colour the background picks for itself.
    private func setReaderTextColor(_ rgbHex: UInt32?) {
        if let background = wornSavedBackground {
            settings.setReaderCustomBackgroundTextColor(rgbHex, id: background.id)
        } else {
            settings.setReaderTextColorOverride(rgbHex, for: theme)
        }
    }

    /// Reads the color the reader is actually painting with, so opening the picker
    /// starts from what is on screen rather than from a blank swatch. Writing one
    /// stores it for the *current* reading background only.
    private var readerTextColorBinding: Binding<Color> {
        Binding(
            get: { Color(uiColor: theme.uiTextColor) },
            set: { newColor in
                guard let rgbHex = UIColor(newColor).rgbHex else { return }
                setReaderTextColor(rgbHex)
            }
        )
    }

    private var fontSelector: some View {
        HStack(spacing: DSSpacing.sm) {
            Menu {
                Button {
                    settings.selectedReaderFontPostScript = nil
                } label: {
                    Label(defaultFontName, systemImage: settings.selectedReaderFontPostScript == nil ? "checkmark" : "f.cursive")
                }

                if !settings.userFonts.isEmpty {
                    Divider()
                    Section {
                        ForEach(settings.userFonts, id: \.id) { font in
                            Button {
                                settings.selectedReaderFontPostScript = font.postScriptName
                            } label: {
                                Label(
                                    font.displayName,
                                    systemImage: settings.selectedReaderFontPostScript == font.postScriptName ? "checkmark" : "f.cursive"
                                )
                            }
                        }
                    } header: {
                        Text(localized("已汇入字体"))
                            .foregroundStyle(DSColor.textSecondary)
                    }

                    Menu(localized("删除字体")) {
                        ForEach(settings.userFonts, id: \.id) { font in
                            Button(role: .destructive) {
                                settings.deleteUserFont(font)
                            } label: {
                                Label(font.displayName, systemImage: "trash")
                            }
                        }
                    }
                }

                if !ReaderSettingsPresentationPolicy.requiresFirstLevelImporter {
                    Divider()
                    if premiumVisibility.allowsFontImport {
                        Button {
                            requestStyleImporter(.readerFont)
                        } label: {
                            Label(localized("汇入字体..."), systemImage: "plus")
                        }
                    } else {
                        // Locked: the second `Text` is the menu row's subtitle.
                        Button {
                            requestPaywall(.customFonts)
                        } label: {
                            Text(localized("汇入字体..."))
                            Text(localized("需要 Pro"))
                            Image(systemName: "lock.fill")
                        }
                    }
                }
            } label: {
                LabeledContent {
                    HStack(spacing: DSSpacing.xs) {
                        Text(currentFontName)
                        Image(systemName: "chevron.up.chevron.down")
                            .font(DSFont.footnote)
                            .accessibilityHidden(true)
                    }
                    .foregroundStyle(DSColor.textSecondary)
                } label: {
                    SettingsRowLabel(
                        localized(ReadingSettingsScopeItem.font.titleKey),
                        systemImage: ReadingSettingsScopeItem.font.systemImage
                    )
                }
            }
            .buttonStyle(.plain)

            if ReaderSettingsPresentationPolicy.requiresFirstLevelImporter {
                let locked = !premiumVisibility.allowsFontImport
                Button {
                    if locked {
                        requestPaywall(.customFonts)
                    } else {
                        requestStyleImporter(.readerFont)
                    }
                } label: {
                    Image(systemName: locked ? "lock.fill" : "plus")
                }
                .accessibilityLabel(localized("汇入字体..."))
                .accessibilityValue(locked ? localized("需要 Pro") : "")
            }
        }
    }

    // MARK: - 格式

    /// 文字的走向与字形：竖排、繁简、底部对齐。这几项在浮层上是「格式」一格，
    /// 从文字与排版两区里提出来——它们决定的是「怎么排」，不是「多大」「多松」。
    private var formatSection: some View {
        Section {
            if allowsVerticalWritingMode {
                Picker(selection: $settings.readerWritingMode) {
                    Text(localized("横排")).tag(ReaderWritingMode.horizontal)
                    Text(localized("直排")).tag(ReaderWritingMode.verticalRTL)
                } label: {
                    SettingsRowLabel(localized(ReadingSettingsScopeItem.writingMode.titleKey),
                                     systemImage: ReadingSettingsScopeItem.writingMode.systemImage)
                }
            }

            if supportsFontSize {
                Picker(selection: $settings.textConversion) {
                    ForEach(TextConversion.allCases, id: \.self) { mode in
                        Text(mode.localizedTitle).tag(mode)
                    }
                } label: {
                    SettingsRowLabel(localized("繁简转换"), systemImage: "character.book.closed")
                }
            }

            if showsBookSpacingToggle {
                Toggle(isOn: $settings.readerUsesBookSpacing) {
                    SettingsRowLabel(localized("套用书本间距"), systemImage: "text.book.closed")
                }
            }

            if showsBottomJustify {
                Toggle(isOn: $settings.readerBottomJustify) {
                    SettingsRowLabel(localized(ReadingSettingsScopeItem.bottomJustify.titleKey),
                                     systemImage: ReadingSettingsScopeItem.bottomJustify.systemImage)
                }
            }
        } header: {
            Text(localized("格式"))
                .foregroundStyle(DSColor.textSecondary)
        } footer: {
            if showsBottomJustify || showsBookSpacingToggle {
                VStack(alignment: .leading, spacing: DSSpacing.xs) {
                    if showsBookSpacingToggle {
                        Text(localized("ReaderSettings.BookSpacing.Footer"))
                    }
                    if showsBottomJustify {
                        Text(localized("底部对齐：开启后每页文字会自动调整行间距以填满页面，使底部对齐整齐。"))
                    }
                }
                .dsSectionFooter()
            }
        }
        .interfaceSectionSurface()
    }

    // MARK: - 排版

    /// Spacing and the three body margins, together: they are all "how the text sits on
    /// the page", and they used to be two sections with two different ways to reset.
    ///
    /// 上下边距 means the same thing in both modes. It used to not: paged mode took its
    /// vertical margin from the header/footer layout's hand-tuned "content reservation"
    /// while scroll mode used `pageMarginV`. The bars' heights are known now, so the
    /// margin no longer has to absorb them.
    private var layoutSection: some View {
        Section {
            if supportsSpacing {
                SettingsSliderRow(
                    title: localized(ReadingSettingsScopeItem.lineSpacing.titleKey),
                    systemImage: ReadingSettingsScopeItem.lineSpacing.systemImage,
                    valueText: String(format: "%.2f", readerConfig.lineHeightMultiple),
                    value: $readerConfig.lineHeightMultiple,
                    range: 1.0...2.4,
                    step: 0.05
                )
                SettingsSliderRow(
                    title: localized(ReadingSettingsScopeItem.letterSpacing.titleKey),
                    systemImage: ReadingSettingsScopeItem.letterSpacing.systemImage,
                    valueText: "\(String(format: "%.1f", readerConfig.letterSpacing)) pt",
                    value: $readerConfig.letterSpacing,
                    range: 0...12,
                    step: 0.5
                )
                SettingsSliderRow(
                    title: localized(ReadingSettingsScopeItem.paragraphSpacing.titleKey),
                    systemImage: ReadingSettingsScopeItem.paragraphSpacing.systemImage,
                    valueText: String(format: "%.2f", readerConfig.paragraphSpacingMultiplier),
                    value: $readerConfig.paragraphSpacingMultiplier,
                    range: 0.3...1.2,
                    step: 0.05
                )
            }

            if supportsLineHeight {
                SettingsSliderRow(
                    title: localized("左右边距"),
                    systemImage: ReadingSettingsScopeItem.pageMargins.systemImage,
                    valueText: String(format: localized("ReaderOverlay.Format.Points"), Int(readerConfig.pageMarginH)),
                    value: $readerConfig.pageMarginH,
                    range: 0...pageMarginHUpperBound,
                    step: 1
                )
                SettingsSliderRow(
                    title: localized("上边距"),
                    systemImage: "arrow.up.to.line",
                    valueText: String(format: localized("ReaderOverlay.Format.Points"), Int(readerConfig.pageMarginTop)),
                    value: $readerConfig.pageMarginTop,
                    range: ReaderVerticalMargin.range,
                    step: 1
                )
                SettingsSliderRow(
                    title: localized("下边距"),
                    systemImage: "arrow.down.to.line",
                    valueText: String(format: localized("ReaderOverlay.Format.Points"), Int(readerConfig.pageMarginBottom)),
                    value: $readerConfig.pageMarginBottom,
                    range: ReaderVerticalMargin.range,
                    step: 1
                )
            }

            Button(role: .destructive) {
                showingLayoutResetConfirmation = true
            } label: {
                SettingsRowLabel(localized("重设排版"), systemImage: "arrow.counterclockwise", role: .destructive)
            }
            .disabled(!hasCustomLayout)
        } header: {
            Text(localized("排版"))
                .foregroundStyle(DSColor.textSecondary)
        } footer: {
            if supportsLineHeight, !settings.scrollMode {
                Text(localized("上下边距同时是页首页尾的容身空间，改动不会移动页首页尾本身。"))
                    .dsSectionFooter()
            }
        }
        .interfaceSectionSurface()
    }

    /// 格式这一区在三种书里都可能整区无内容（没有竖排、没有繁简、不是 EPUB），
    /// 那就整区不出现，而不是留一个空标题。
    private var showsFormatSection: Bool {
        allowsVerticalWritingMode || supportsFontSize || showsBookSpacingToggle || showsBottomJustify
    }

    /// 底部对齐 spreads a page's leftover space over its lines; a scroll column has no
    /// page bottom, and vertical columns are not justified, so the switch only shows
    /// for horizontal pages.
    private var showsBottomJustify: Bool {
        supportsLineHeight && !settings.scrollMode && !isVerticalWritingMode
    }

    private var hasCustomLayout: Bool {
        let spacing = supportsSpacing && (
            abs(readerConfig.lineHeightMultiple - defaultLineHeightMultiple) > 0.001
                || abs(readerConfig.letterSpacing - defaultLetterSpacing) > 0.001
                || abs(readerConfig.paragraphSpacingMultiplier - defaultParagraphSpacingMultiplier) > 0.001
        )
        let margins = supportsLineHeight && (
            abs(readerConfig.pageMarginH - defaultPageMarginH) > 0.001
                || abs(readerConfig.pageMarginTop - defaultPageMarginV) > 0.001
                || abs(readerConfig.pageMarginBottom - defaultPageMarginV) > 0.001
        )
        let bottomJustify = showsBottomJustify && !settings.readerBottomJustify
        let bookSpacing = showsBookSpacingToggle && !settings.readerUsesBookSpacing
        return spacing || margins || bottomJustify || bookSpacing
    }

    /// The bars' own space is computed from their height, so there is no separate
    /// reservation left to reset here — only what this section shows.
    private func resetLayout() {
        if supportsSpacing {
            readerConfig.lineHeightMultiple = defaultLineHeightMultiple
            readerConfig.letterSpacing = defaultLetterSpacing
            readerConfig.paragraphSpacingMultiplier = defaultParagraphSpacingMultiplier
        }
        if supportsLineHeight {
            readerConfig.pageMarginH = defaultPageMarginH
            readerConfig.pageMarginV = defaultPageMarginV
            readerConfig.pageMarginTop = defaultPageMarginV
            readerConfig.pageMarginBottom = defaultPageMarginV
        }
        if showsBottomJustify {
            settings.readerBottomJustify = true
        }
        if showsBookSpacingToggle {
            settings.readerUsesBookSpacing = true
        }
    }

    // MARK: - 页首页尾与标题

    /// Pushed pages, not sheets handed back to the reader to present. This sheet is
    /// already inside a `NavigationStack`, so pushing keeps the whole flow at one
    /// presentation level — the iOS 17 sheet-from-sheet trap never arises.
    private var headerFooterSection: some View {
        Section {
            NavigationLink {
                ReaderBarLayoutEditorView(
                    theme: theme,
                    readerSafeTop: readerSafeTop,
                    readerSafeBottom: readerSafeBottom
                )
            } label: {
                SettingsRowLabel(
                    localized("页首页尾编辑"),
                    systemImage: ReadingSettingsScopeItem.headerFooter.systemImage
                )
            }

            if supportsLineHeight {
                NavigationLink {
                    ChapterTitleStyleSettingsView(
                        onOpenImporter: { requestStyleImporter(.chapterTitleStyle) }
                    )
                } label: {
                    SettingsRowLabel(
                        localized(ReadingSettingsScopeItem.chapterTitle.titleKey),
                        systemImage: ReadingSettingsScopeItem.chapterTitle.systemImage
                    )
                }
            }

            Button(role: .destructive) {
                showingOverlayResetConfirmation = true
            } label: {
                SettingsRowLabel(localized("重设页首页尾"), systemImage: "arrow.counterclockwise", role: .destructive)
            }
        } header: {
            Text(localized("页首页尾与标题"))
                .foregroundStyle(DSColor.textSecondary)
        } footer: {
            Text(localized("正文与页首页尾的距离在「排版」的上下边距调整。"))
                .dsSectionFooter()
        }
        .interfaceSectionSurface()
    }

    /// Writes the archive under `name` — 阅读设置 when left blank — and hands it to the
    /// share sheet. The values are read now, on the main actor; the zip is made off it.
    private func exportReaderSettings(named name: String) {
        let inputs = ReaderSettingsExportSnapshot.make()
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        Task { @MainActor in
            do {
                let url = try await ReaderSettingsExportFile.write(
                    inputs,
                    named: trimmed.isEmpty ? localized("阅读设置") : trimmed
                )
                SystemShareSheet.present(fileURL: url)
            } catch {
                AppLogger.error("⟐ reading settings export failed", error: error)
                layoutImportAlert = LayoutImportAlert(
                    titleKey: "汇出失败",
                    message: error.localizedDescription
                )
            }
        }
    }

    private func resetReaderOverlayLayout() {
        guard settings.saveReaderBarLayout(.default) else {
            layoutImportAlert = LayoutImportAlert(
                titleKey: "无法储存页首页尾设置",
                message: localized("请稍后再试。")
            )
            return
        }
    }

    // MARK: - 阅读装饰

    private var readerDecorationSection: some View {
        Section {
            if premiumVisibility.showsReaderDecoration {
                if showsCommentBubbleSettings {
                    NavigationLink {
                        ReaderCommentBubbleSettingsView(onOpenImporter: requestStyleImporter)
                    } label: {
                        SettingsRowLabel(
                            localized("气泡设置"),
                            systemImage: ReadingSettingsScopeItem.commentBubble.systemImage
                        )
                    }
                }

                NavigationLink {
                    ReaderDialogueBubbleSettingsView(
                        style: settings.dialogueBubbleStyle,
                        onOpenImporter: { requestStyleImporter(.dialogueBubble) },
                        onChange: { settings.dialogueBubbleStyle = $0 }
                    )
                } label: {
                    SettingsValueLabel(
                        title: localized(ReadingSettingsScopeItem.dialogueBubble.titleKey),
                        systemImage: ReadingSettingsScopeItem.dialogueBubble.systemImage,
                        value: onOffText(settings.dialogueBubbleStyle.isEnabled)
                    )
                }

                NavigationLink {
                    RegexHighlightSettingsView(
                        configuration: settings.regexHighlightConfiguration,
                        onOpenImporter: { requestStyleImporter(.regexHighlights) },
                        onChange: { settings.regexHighlightConfiguration = $0 }
                    )
                } label: {
                    SettingsValueLabel(
                        title: localized(ReadingSettingsScopeItem.regexHighlight.titleKey),
                        systemImage: ReadingSettingsScopeItem.regexHighlight.systemImage,
                        value: onOffText(settings.regexHighlightConfiguration.isEnabled)
                    )
                }

                NavigationLink {
                    ReaderTextUnderlineSettingsView()
                } label: {
                    SettingsValueLabel(
                        title: localized(ReadingSettingsScopeItem.textUnderline.titleKey),
                        systemImage: ReadingSettingsScopeItem.textUnderline.systemImage,
                        value: onOffText(settings.readerTextUnderlineDecorationEnabled)
                    )
                }
            } else {
                ForEach(lockedDecorationItems) { item in
                    SettingsLockedRow(
                        title: localized(item == .commentBubble ? "气泡设置" : item.titleKey),
                        systemImage: item.systemImage
                    ) {
                        requestPaywall(.dialogueHighlight)
                    }
                }
            }
        } header: {
            Text(localized("阅读装饰"))
                .foregroundStyle(DSColor.textSecondary)
        }
        .interfaceSectionSurface()
    }

    /// The same rows, in the same order, as with Pro.
    private var lockedDecorationItems: [ReadingSettingsScopeItem] {
        (hasParagraphReviews ? [.commentBubble] : []) + [.dialogueBubble, .regexHighlight, .textUnderline]
    }

    private func onOffText(_ isOn: Bool) -> String {
        localized(isOn ? "已开启" : "已关闭")
    }

    // MARK: - 翻页与手势

    private var pagingSection: some View {
        Section {
            if supportsPageDisplay {
                Picker(selection: $settings.readerSpreadMode) {
                    ForEach(ReaderSpreadMode.settingsCases, id: \.self) { mode in
                        Text(localized(spreadTitleKey(for: mode))).tag(mode)
                    }
                } label: {
                    SettingsRowLabel(localized("页面显示"), systemImage: "rectangle.portrait.on.rectangle.portrait")
                }
            }

            Toggle(isOn: $settings.readerTapBothSidesNextPage) {
                SettingsRowLabel(localized("全局翻页"), systemImage: "hand.tap")
            }

            Toggle(isOn: $settings.readerSwipeUpToExit) {
                SettingsRowLabel(localized("上滑退出阅读"), systemImage: "rectangle.portrait.and.arrow.right")
            }

            Toggle(isOn: $settings.readerPullDownToBookmark) {
                SettingsRowLabel(localized("下拉加入书签"), systemImage: "bookmark")
            }

            if let onOpenTouchZoneEditor {
                if premiumVisibility.showsTouchZoneEditor {
                    Button {
                        dismiss()
                        DispatchQueue.main.async { onOpenTouchZoneEditor() }
                    } label: {
                        SettingsRowLabel(localized("翻页区块编辑"), systemImage: "square.grid.3x3", role: .action)
                    }
                } else {
                    SettingsLockedRow(title: localized("翻页区块编辑"), systemImage: "square.grid.3x3") {
                        requestPaywall(.touchZoneEditor)
                    }
                }
            }
        } header: {
            Text(localized("翻页与手势"))
                .foregroundStyle(DSColor.textSecondary)
        } footer: {
            Text(localized("全局翻页：点画面左右两侧都翻到下一页，中间仍呼出选单。上滑退出与下拉书签都要滑过一半再松手。"))
                .dsSectionFooter()
        }
        .interfaceSectionSurface()
    }

    private func spreadTitleKey(for mode: ReaderSpreadMode) -> String {
        switch mode {
        case .singlePage: return "单页"
        case .doublePage: return "双页"
        case .auto: return "单页"
        }
    }

    // MARK: - 亮度

    private var brightnessSection: some View {
        Section {
            Toggle(isOn: followSystemBrightnessBinding) {
                SettingsRowLabel(localized("跟随系统亮度"), systemImage: "sun.max")
            }

            SettingsSliderRow(
                title: localized("阅读亮度"),
                systemImage: "sun.min",
                valueText: "\(Int(settings.readerBrightness * 100))%",
                value: readerBrightnessBinding,
                range: 0.05...1.0,
                step: 0.05,
                isEnabled: !settings.followSystemBrightness
            )

            // Outside 排版生效范围 and its backup: iCloud syncs it on its own.
            Toggle(isOn: $settings.readerKeepsScreenAwake) {
                SettingsRowLabel(localized("阅读时萤幕常亮"), systemImage: "lock.open.display")
            }

            // 显示系统状态栏: same screen-level, per-device family as 萤幕常亮.
            // Sits in 亮度 so the quick panel's 亮度 tile reaches it without a new
            // section or another grid cell.
            Toggle(isOn: $settings.readerShowsStatusBar) {
                SettingsRowLabel(localized("显示系统状态栏"), systemImage: "clock")
            }
        } header: {
            Text(localized("亮度"))
                .foregroundStyle(DSColor.textSecondary)
        } footer: {
            Text(localized("只防止自动锁定，会比较耗电；按下电源键仍可锁定萤幕。"))
                .dsSectionFooter()
        }
        .interfaceSectionSurface()
    }

    // The reader that presents this panel owns the screen: it puts these two settings on the
    // screen it is on, and keeps the slider following the system while that is on
    // (`ReaderView`'s `followSystemBrightness` and `readerBrightness` handlers).
    private var followSystemBrightnessBinding: Binding<Bool> {
        $settings.followSystemBrightness
    }

    private var readerBrightnessBinding: Binding<Double> {
        $settings.readerBrightness
    }

    // MARK: - 阅读设置备份

    /// 汇出/汇入 the whole of 阅读设置 in one file: layout parameters, the chapter
    /// title style, and the regex highlight rules. Each of those two styles keeps
    /// its own single-purpose export on its own page; this is the "move my whole
    /// reading setup to the new phone" file.
    private var readerSettingsBackupSection: some View {
        Section {
            if premiumVisibility.showsLayoutPresetImport {
                Button {
                    readerSettingsExportName = localized("阅读设置")
                    showingReaderSettingsExport = true
                } label: {
                    SettingsRowLabel(localized("汇出阅读设置"), systemImage: "square.and.arrow.up", role: .action)
                }
                // The file is named first, then shared: the file name is all that
                // tells one exported setup from another.
                .alert(localized("汇出阅读设置"), isPresented: $showingReaderSettingsExport) {
                    TextField(localized("名称"), text: $readerSettingsExportName)
                    Button(localized("汇出")) {
                        exportReaderSettings(named: readerSettingsExportName)
                    }
                    Button(localized("取消"), role: .cancel) {}
                }

                Button {
                    requestStyleImporter(.readerSettings)
                } label: {
                    SettingsRowLabel(localized("汇入阅读设置"), systemImage: "square.and.arrow.down", role: .action)
                }
            } else {
                SettingsLockedRow(title: localized("汇出阅读设置"), systemImage: "square.and.arrow.up") {
                    requestPaywall(.layoutPresetImport)
                }
                SettingsLockedRow(title: localized("汇入阅读设置"), systemImage: "square.and.arrow.down") {
                    requestPaywall(.layoutPresetImport)
                }
            }
        } header: {
            Text(localized("阅读设置备份"))
                .foregroundStyle(DSColor.textSecondary)
        } footer: {
            Text(localized("包含排版、章节标题样式与正则高亮。汇入也接受 legado 的 readConfig.json。"))
                .dsSectionFooter()
        }
        .interfaceSectionSurface()
    }

    // MARK: - Presenting

    /// A locked control's paywall: from this sheet on iOS 18, from the reader on iOS 17
    /// (`onOpenPaywall`), where a sheet asked for from inside this one can be dropped.
    private func requestPaywall(_ feature: PremiumFeature) {
        if let onOpenPaywall {
            onOpenPaywall(feature)
        } else {
            paywallFeature = feature
        }
    }

    /// iOS 17 cannot present a document picker from this sheet — hand it to the
    /// reader's first-level presenter instead. See
    /// `Technotes/iOS17MenuModalPresentation.md`.
    private func requestStyleImporter(_ route: ReaderStyleImportRoute) {
        guard ReaderSettingsPresentationPolicy.requiresFirstLevelImporter,
              let onOpenStyleImporter else {
            styleImportRoute = route
            return
        }
        // The caller dismisses this sheet and presents from its real `onDismiss`
        // — an event boundary, never a timed delay.
        onOpenStyleImporter(route)
    }

    // MARK: - Preview

    /// Preview font that reflects the user-selected reader font in real time;
    /// falls back to the system font when none is selected (or it can't be loaded).
    private func previewFont(size: CGFloat, weight: Font.Weight = .regular) -> Font {
        let isBold = readerConfig.readerFontBold
        let resolvedWeight: Font.Weight = isBold ? .bold : weight
        if let postScript = settings.selectedReaderFontPostScript,
           !postScript.isEmpty,
           let uiFont = UIFont(name: postScript, size: size) {
            if isBold,
               let descriptor = uiFont.fontDescriptor.withSymbolicTraits(.traitBold) {
                return Font(UIFont(descriptor: descriptor, size: size) as CTFont)
            }
            return Font(uiFont as CTFont)
        }
        return .system(size: size, weight: resolvedWeight)
    }

    private var previewPanel: some View {
        VStack(alignment: .leading, spacing: 18) {
            HStack(alignment: .firstTextBaseline, spacing: 1) {
                Text(localized("大"))
                    .font(previewFont(size: 34))

                Text(localized("小"))
                    .font(previewFont(size: 18))
                    .baselineOffset(-6)
            }
            Text(localized("  这是一段测试文字，用来测试字体大小和行距、字距、段落间距，以及不同主题下的阅读舒适度。调整设置时，可以观察文字密度、换行节奏与背景对比是否符合你的阅读习惯。"))
                .font(previewFont(size: min(max(fontSize, 17), 24)))
                .lineSpacing(readerConfig.lineSpacing)
                .tracking(readerConfig.letterSpacing)
                .foregroundStyle(theme.textColor)
        }
        .padding(.horizontal, readerConfig.pageMarginH)
        .padding(.top, 26)
        .padding(.bottom, 22)
        .frame(maxWidth: .infinity, minHeight: previewTextHeight, maxHeight: previewTextHeight, alignment: .topLeading)
        .clipped()
        .foregroundStyle(theme.textColor)
        .background(theme.backgroundColor.opacity(0.55))
    }

    // MARK: - Fonts

    private var fontSizeBinding: Binding<CGFloat> {
        Binding(
            get: { fontSize },
            set: { fontSize = GlobalSettings.clampedReaderFontSize($0) }
        )
    }

    private var defaultFontName: String {
        localized(usesPublicationFontDefault ? "书籍预设字体" : "系统字体")
    }

    private var currentFontName: String {
        guard let selected = settings.selectedReaderFontPostScript else { return defaultFontName }
        return settings.userFonts.first { $0.postScriptName == selected }?.displayName ?? selected
    }

}

private struct LayoutImportAlert: Identifiable {
    let id = UUID()
    let titleKey: String
    let message: String
}

/// 浮层九宫格推进来的那一页，`Identifiable` 只是为了 `sheet(item:)`：
/// 同一组分区算同一页，重复点同一格不会叠出第二张卡。
struct ReaderSectionSheet: Identifiable, Hashable {
    let sections: Set<ReaderSettingsSection>

    var id: String {
        sections.map(\.rawValue).sorted().joined(separator: ",")
    }
}

#Preview {
    ReaderSettingsView(
        fontSize: .constant(18),
        theme: .constant(.sepia),
        capabilities: .reflowableText,
        allowsUserSelectedReaderFont: true,
        allowsVerticalWritingMode: true
    )
}

#Preview("EPUB・套用書本間距") {
    ReaderSettingsView(
        fontSize: .constant(18),
        theme: .constant(.sepia),
        capabilities: EPUBBookDocument.supportedCapabilities,
        usesPublicationFontDefault: true
    )
}

#Preview("iPad 橫向・左右邊距上限") {
    ReaderSettingsView(
        fontSize: .constant(18),
        theme: .constant(.night),
        pageMarginHUpperBound: ReaderReadableWidthPolicy.sliderUpperBound(
            pageWidth: 1133,
            usesReadableWidth: true,
            defaultMargin: ReaderSettingsView.defaultPageMarginH
        ),
        readerWindowCanHoldSpread: true,
        capabilities: .reflowableText
    )
}
