import SwiftUI
import UIKit

/// 浮层里「翻页」一排可选的样式，用短词挤进一行 chip（超出可横滑）：
/// 「上下滚动」在竖排书里就是「右往左」，由 `pageTurnTitleKey(for:)` 换掉。
/// 注意「上下翻」（vertical）与「上下滚动」（scroll）不是一回事：前者一屏一页、
/// 松手吸附，后者是连续滚动。
enum ReaderQuickPageTurnOption: String, CaseIterable, Identifiable, Hashable {
    case slide
    case cover
    case curl
    /// 波纹：波前从按下的位置扩散，扫过的地方换成下一页。
    case ripple
    /// 上下翻页：整页跟手上下平移，一屏一页。
    case vertical
    case fastFade
    case scroll

    var id: String { rawValue }

    var titleKey: String {
        switch self {
        case .slide: return "平移"
        case .cover: return "覆盖"
        case .curl: return "仿真"
        case .ripple: return "波纹"
        case .vertical: return "上下翻"
        case .fastFade: return "无动画"
        case .scroll: return "上下滚动"
        }
    }

    var iconName: String {
        switch self {
        case .slide: return "arrow.left.square"
        case .cover: return "square.on.square"
        case .curl: return "doc"
        case .ripple: return "water.waves"
        case .vertical: return "chevron.up.chevron.down"
        case .fastFade: return "bolt.square"
        case .scroll: return "doc.plaintext"
        }
    }
}

/// Which saved-background page the quick panel has pushed.
enum ReaderBackgroundEditorRoute: Hashable {
    case new
    case edit(UUID)

    var backgroundID: UUID? {
        if case .edit(let id) = self { return id }
        return nil
    }
}

/// The panel a reader gets on a tap in the middle of the page: type size, background,
/// page turn, and four actions. Everything else lives behind 更多设置, which is a grid of
/// the same sections the full settings sheet has — one tap per subject instead of one
/// long form to scroll.
struct ReaderQuickThemePanelView: View {
    @Binding var fontSize: CGFloat
    @Binding var readerTheme: ReaderTheme
    let pageTurnOption: ReaderQuickPageTurnOption
    let isVerticalWritingMode: Bool
    let onSelectPageTurnOption: (ReaderQuickPageTurnOption) -> Void
    /// Enters auto-read mode and puts every surface away. It is only an entry:
    /// once running, the footer pill is the single route to the speed and the exit.
    let onStartAutoRead: () -> Void
    /// The whole settings sheet, preview panel and all. Kept as the second way in:
    /// 更多设置 answers one question, this one answers all of them at once.
    let onCustomize: () -> Void
    /// A locked control asked for the paywall. The reader closes this sheet and presents
    /// it from its own `onDismiss`, as it does for 自定义 — never a sheet on top of this one.
    var onOpenPaywall: ((PremiumFeature) -> Void)? = nil
    /// 听书: the reader closes the panel and raises its own TTS sheet.
    var onOpenTTS: (() -> Void)? = nil
    /// A grid cell was picked. The reader closes this panel and opens that section as a
    /// half-height card, so the page underneath stays visible while it is adjusted.
    var onOpenSection: ((Set<ReaderSettingsSection>) -> Void)? = nil
    /// EPUB 的预设字体就是书自己的字体，那一格不该说「系统字体」。
    var usesPublicationFontDefault = false

    @Bindable private var settings = GlobalSettings.shared
    @Environment(\.colorScheme) private var colorScheme
    /// The saved-background page pushed in this panel's own navigation.
    @State private var backgroundEditor: ReaderBackgroundEditorRoute?
    /// The 更多设置 grid, pushed in this panel's own navigation.
    @State private var showingSectionGrid = false
    /// Measured height of the panel's own content, so the sheet is exactly as tall
    /// as what it holds. A fixed detent left a band of dead space under the last
    /// row whenever the content came out shorter than the constant.
    @State private var contentHeight = DSLayout.readerQuickPanelSheetHeight
    @State private var bottomSafeAreaInset: CGFloat = 0

    private let minFontSize = GlobalSettings.readerFontSizeRange.lowerBound
    private let maxFontSize = GlobalSettings.readerFontSizeRange.upperBound

    var body: some View {
        NavigationStack {
            // Scrolls rather than clips. The panel is no longer a fixed 508pt of
            // which 214 went to a background pager that only ever had one page, so
            // its height follows its content — and at the largest Dynamic Type
            // sizes that content is taller than any detent.
            ScrollView {
                VStack(alignment: .leading, spacing: DSSpacing.lg) {
                    typeRow
                    readingBackgroundRow
                    pageTurnChips
                    actionGrid
                    // Only under 绑定阅读主题: without it the reader follows the device by
                    // itself and there is nothing to switch (the user's call, 2026-09-30).
                    // It stays where it was; 更多设置 did not take it over.
                    if settings.appearanceBindReaderTheme {
                        followSystemAppearanceToggle
                    }
                }
                .padding(.horizontal, DSSpacing.xl)
                .padding(.top, DSSpacing.xl)
                .padding(.bottom, DSSpacing.xl)
                .background(
                    GeometryReader { proxy in
                        Color.clear.preference(
                            key: ReaderQuickPanelContentHeightKey.self,
                            value: proxy.size.height
                        )
                    }
                )
            }
            .softScrollEdges()
            .onPreferenceChange(ReaderQuickPanelContentHeightKey.self) { height in
                guard height > 0 else { return }
                contentHeight = height
            }
            .scrollBounceBehavior(.basedOnSize)
            // This panel supplies its own bottom padding. Let the scroll viewport
            // use the whole sheet instead of reserving another home-indicator band.
            .ignoresSafeArea(.container, edges: .bottom)
            .frame(maxWidth: DSLayout.readableCompactWidth, alignment: .topLeading)
            .frame(maxWidth: .infinity, alignment: .top)
            .pageBackgroundToolbar(for: .settings)
            // No title bar and no close button: the panel is a short sheet the
            // reader flicks away, and a navigation chrome on top of it ate height
            // the controls could use.
            .toolbar(.hidden, for: .navigationBar)
            .navigationDestination(item: $backgroundEditor) { route in
                ReaderCustomBackgroundEditorView(
                    original: route.backgroundID.flatMap(settings.readerCustomBackground(id:)),
                    onSave: { saved in
                        // A new one is made to be worn; an edit leaves what is worn alone,
                        // and the reader repaints if it was this one.
                        if route == .new {
                            wear(saved)
                        }
                        backgroundEditor = nil
                    },
                    onDelete: { backgroundEditor = nil },
                    onRequestPaywall: { onOpenPaywall?($0) }
                )
            }
            .navigationDestination(isPresented: $showingSectionGrid) {
                ReaderQuickPanelSectionGrid(onOpenSection: { sections in
                    onOpenSection?(sections)
                })
            }
        }
        .background {
            GeometryReader { proxy in
                Color.clear.preference(
                    key: ReaderQuickPanelSafeAreaBottomKey.self,
                    value: proxy.safeAreaInsets.bottom
                )
            }
        }
        .onPreferenceChange(ReaderQuickPanelSafeAreaBottomKey.self) {
            bottomSafeAreaInset = $0
        }
        // The grabber is the only way out now that the title bar is gone, so the
        // sheet must stay draggable and the indicator visible.
        // A height detent excludes the bottom safe area, which UIKit adds back.
        // Our measurement already includes the panel's complete bottom padding.
        // 更多设置 is a half sheet like this one — only the saved-background editor, which
        // is a whole form, takes the full height.
        .presentationDetents(panelDetents)
        .presentationBackground(.ultraThinMaterial)
        .presentationDragIndicator(.visible)
    }

    private var panelDetents: Set<PresentationDetent> {
        if backgroundEditor != nil { return [.large] }
        if showingSectionGrid { return [.medium] }
        return [.height(max(DSLayout.minimumTapTarget, contentHeight - bottomSafeAreaInset))]
    }

    // MARK: - 字级 + 字体

    /// The two things a reader reaches for mid-page, in one row. The size never leaves
    /// the panel — it is the one setting worth stepping with the page in sight — while
    /// 字体 hands over to 字体与大小, where the full list lives.
    private var typeRow: some View {
        HStack(spacing: DSSpacing.md) {
            fontSizeStepper
            fontMenu
                .frame(width: DSLayout.readerQuickPanelTopMenuWidth)
        }
    }

    /// 小 A ── 现在的字级 ── 大 A, in one capsule.
    ///
    /// The size used to be reported by a row of dots under this control that
    /// faded out after 1.8 seconds — it was gone by the time anyone looked for
    /// it, and its appearing and disappearing made the panel change height. The number
    /// now sits between the two buttons that change it and never moves.
    ///
    /// Both ends keep `.buttonRepeatBehavior(.enabled)`, so press-and-hold keeps
    /// stepping.
    private var fontSizeStepper: some View {
        HStack(spacing: 0) {
            fontSizeStepButton(
                -1,
                textFont: DSFont.body.weight(.semibold),
                accessibilityKey: "缩小字体"
            )

            Text("\(Int(fontSize))")
                .font(DSFont.title3.weight(.medium).monospacedDigit())
                .foregroundStyle(DSColor.textPrimary)
                .frame(minWidth: DSSpacing.xxl)
                // The stepper is one control with one value; the buttons carry
                // their own labels, so the number would only repeat what VoiceOver
                // already announces when the value changes.
                .accessibilityHidden(true)

            fontSizeStepButton(
                1,
                textFont: DSFont.title2.weight(.semibold),
                accessibilityKey: "放大字体"
            )
        }
        .frame(maxWidth: .infinity, minHeight: DSLayout.readerQuickPanelTopControlHeight)
        .background(DSColor.neutralControlFill, in: Capsule())
        .shadow(color: DSColor.shadow, radius: 6, y: 1)
    }

    /// The font itself, named. Like the size, it says which one is worn instead of
    /// making the reader open something to find out; picking goes to the section page
    /// because the list is long and each row previews its own face.
    private var fontMenu: some View {
        Button {
            onOpenSection?([.text])
        } label: {
            HStack(spacing: DSSpacing.xs) {
                Text(currentFontName)
                    .lineLimit(1)
                    .minimumScaleFactor(0.75)
                Image(systemName: "chevron.right")
                    .font(DSFont.footnote)
                    .accessibilityHidden(true)
            }
            .font(DSFont.subheadline)
            .foregroundStyle(DSColor.textPrimary)
            .padding(.horizontal, DSSpacing.sm)
            .frame(maxWidth: .infinity, minHeight: DSLayout.readerQuickPanelTopControlHeight)
            .background(DSColor.neutralControlFill, in: Capsule())
            .shadow(color: DSColor.shadow, radius: 6, y: 1)
            .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(localized("字体"))
        .accessibilityValue(currentFontName)
    }

    private var currentFontName: String {
        if usesPublicationFontDefault, settings.selectedReaderFontPostScript == nil {
            return localized("书籍字体")
        }
        guard let selected = settings.selectedReaderFontPostScript else {
            return localized("系统字体")
        }
        return settings.userFonts.first { $0.postScriptName == selected }?.displayName ?? selected
    }

    /// One half of the A / A stepper. `.buttonRepeatBehavior(.enabled)` makes
    /// press-and-hold keep stepping, matching Apple Books.
    private func fontSizeStepButton(_ delta: CGFloat, textFont: Font, accessibilityKey: String) -> some View {
        Button {
            adjustFontSize(delta)
        } label: {
            Text("A")
                .font(textFont)
                .foregroundStyle(DSColor.textPrimary)
                .frame(maxWidth: .infinity, minHeight: DSLayout.readerQuickPanelTopControlHeight)
                .contentShape(Rectangle())
        }
        .buttonStyle(QuickPanelSegmentButtonStyle())
        .buttonRepeatBehavior(.enabled)
        .accessibilityLabel(localized(accessibilityKey))
    }

    // MARK: - Reading backgrounds

    /// One scrolling row, not the 3×2 paged grid this replaced: the four built-in
    /// backgrounds, then every saved one, each by name, then 自定义 to make another.
    private var readingBackgroundRow: some View {
        let resolution = settings.readerBackgroundResolution(mode: settings.readerMode, wornTheme: readerTheme)
        return VStack(alignment: .leading, spacing: DSSpacing.sm) {
            Text(localized("阅读背景"))
                .font(DSFont.footnote)
                .foregroundStyle(DSColor.textSecondary)

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: DSSpacing.md) {
                    ForEach(ReaderTheme.allCases, id: \.self) { background in
                        readingBackgroundButton(background, resolution: resolution)
                            .frame(width: DSLayout.readerQuickPanelBackgroundTileWidth)
                    }
                    ForEach(settings.readerCustomBackgrounds) { background in
                        savedBackgroundButton(background, resolution: resolution)
                            .frame(width: DSLayout.readerQuickPanelBackgroundTileWidth)
                    }
                    newBackgroundButton
                        .frame(width: DSLayout.readerQuickPanelBackgroundTileWidth)
                }
                .padding(.vertical, DSSpacing.xs)
                .padding(.horizontal, 2)
            }
        }
    }

    private func readingBackgroundButton(
        _ background: ReaderTheme,
        resolution: ReaderBackgroundResolution
    ) -> some View {
        // While the page is painted by 跟随外观主题 or by a saved background — a dark one
        // sits on 黑色 — no built-in one is the one in effect.
        let selected = !resolution.paintsWithAppearanceTheme
            && resolution.customBackground == nil
            && resolution.theme == background
        return Button {
            settings.appearanceBindReaderTheme = false
            settings.setReaderDarkMode(background == .night, deviceIsDark: colorScheme == .dark)
            // 黑色 is the reader's dark mode; the saved background stays the light mode's
            // and comes back with it. A light built-in one takes its place there.
            if background != .night {
                settings.readerCustomBackgroundID = nil
            }
            readerTheme = background
        } label: {
            ReaderQuickPanelBackgroundTile(
                fill: background.previewBackgroundColor,
                image: nil,
                title: background.localizedTitle,
                titleColor: background.previewTextColor,
                selected: selected
            )
        }
        .buttonStyle(.plain)
        .accessibilityLabel(background.localizedTitle)
        .accessibilityAddTraits(selected ? .isSelected : [])
    }

    private func savedBackgroundButton(
        _ background: ReaderCustomBackground,
        resolution: ReaderBackgroundResolution
    ) -> some View {
        let selected = resolution.customBackground?.id == background.id
        return Button {
            wear(background)
        } label: {
            ReaderQuickPanelBackgroundTile(
                fill: Color(uiColor: AppearanceThemePreset.hex(background.colorHex)),
                image: background.imageFileName.flatMap(ReaderCustomBackgroundStorageManager.shared.thumbnail(fileName:)),
                title: background.name,
                titleColor: Color(uiColor: AppearanceThemePreset.hex(background.resolvedTextColorHex)),
                selected: selected
            )
        }
        .buttonStyle(.plain)
        // Plain buttons only, as on the theme grid: the delete confirmation is a submenu
        // because a modal raised from a context-menu action can be dropped on iOS 17
        // (Technotes/iOS17MenuModalPresentation.md).
        .contextMenu {
            Button {
                backgroundEditor = .edit(background.id)
            } label: {
                Label(localized("编辑"), systemImage: "slider.horizontal.3")
            }
            Menu {
                Button(role: .destructive) {
                    settings.deleteReaderCustomBackground(id: background.id)
                } label: {
                    Label(String(format: localized("删除「%@」"), background.name), systemImage: "trash")
                }
            } label: {
                Label(localized("删除"), systemImage: "trash")
            }
        }
        .accessibilityLabel(background.name)
        .accessibilityAddTraits(selected ? .isSelected : [])
        .accessibilityAction(named: localized("编辑")) {
            backgroundEditor = .edit(background.id)
        }
    }

    private var newBackgroundButton: some View {
        Button {
            backgroundEditor = .new
        } label: {
            ZStack {
                RoundedRectangle(cornerRadius: DSRadius.xxl, style: .continuous)
                    .fill(DSColor.neutralControlFill)
                VStack(spacing: DSSpacing.xs) {
                    Image(systemName: "plus")
                        .font(DSFont.title2.weight(.semibold))
                        .accessibilityHidden(true)
                    Text(localized("自定义"))
                        .font(DSFont.subheadline)
                }
                .foregroundStyle(DSColor.textPrimary)
            }
            .frame(height: DSLayout.readerQuickPanelReadingBackgroundTileHeight)
            .overlay(
                RoundedRectangle(cornerRadius: DSRadius.xxl, style: .continuous)
                    .stroke(DSColor.separator, lineWidth: 1)
            )
            .shadow(color: DSColor.shadow, radius: 6, y: 1)
        }
        .buttonStyle(.plain)
        .accessibilityLabel(localized("自定义"))
    }

    /// Whether the reader's dark mode keeps to the device's appearance, where the two
    /// picks of 绑定阅读主题 are worn. Off to start with; switching the reader against
    /// the device by hand turns it back off, since the two cannot both hold.
    private var followSystemAppearanceToggle: some View {
        Toggle(
            localized("跟随装置深浅色"),
            isOn: Binding(
                get: { settings.readerFollowSystemTheme },
                set: { applyFollowSystemAppearance($0) }
            )
        )
        .font(DSFont.body)
        .foregroundStyle(DSColor.textPrimary)
    }

    // MARK: - 翻页
    /// Every style as a chip, all visible at once. They used to be a `Menu` behind a
    /// capsule that said which one was on: two taps to change, and the list hid the fact
    /// that there were five. A chip row is one tap and the whole set in view — it now
    /// scrolls horizontally, which is why adding 上下翻 costs no layout work.
    private var pageTurnChips: some View {
        VStack(alignment: .leading, spacing: DSSpacing.sm) {
            Text(localized("翻页"))
                .font(DSFont.footnote)
                .foregroundStyle(DSColor.textSecondary)

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: DSSpacing.sm) {
                    ForEach(ReaderQuickPageTurnOption.allCases) { option in
                        pageTurnChip(option)
                    }
                }
                .padding(.vertical, DSSpacing.xs)
                .padding(.horizontal, 2)
            }
        }
    }

    private func pageTurnChip(_ option: ReaderQuickPageTurnOption) -> some View {
        let selected = option == pageTurnOption
        return Button {
            onSelectPageTurnOption(option)
        } label: {
            HStack(spacing: DSSpacing.xs) {
                Image(systemName: option.iconName)
                    .font(DSFont.caption)
                    .accessibilityHidden(true)
                Text(localized(pageTurnTitleKey(for: option)))
                    .font(DSFont.subheadline)
                    .lineLimit(1)
            }
            // 两个分支的类型不同（OnAccentTextStyle / Color），必须经 AnyShapeStyle 统一，
            // 否则 Xcode 26.3 报 “result values in '? :' have mismatching types”。
            .foregroundStyle(selected ? AnyShapeStyle(DSColor.textOnAccent) : AnyShapeStyle(DSColor.textPrimary))
            .padding(.horizontal, DSSpacing.md)
            .frame(minHeight: DSLayout.minimumTapTarget)
            .background(
                selected ? AnyShapeStyle(DSColor.accent) : AnyShapeStyle(DSColor.neutralControlFill),
                in: Capsule()
            )
            .overlay(
                Capsule()
                    .stroke(selected ? Color.clear : DSColor.separator, lineWidth: 1)
            )
            .shadow(color: DSColor.shadow, radius: 6, y: 1)
        }
        .buttonStyle(.plain)
        .accessibilityLabel(localized(pageTurnTitleKey(for: option)))
        .accessibilityAddTraits(selected ? .isSelected : [])
    }

    // MARK: - 动作

    /// Four actions, two by two. 自动阅读 comes first — that is where every reader that
    /// ships this feature puts it, and until now this app had no entry for it at all.
    private var actionGrid: some View {
        LazyVGrid(
            columns: [
                GridItem(.flexible(), spacing: DSSpacing.md),
                GridItem(.flexible(), spacing: DSSpacing.md)
            ],
            spacing: DSSpacing.md
        ) {
            Button {
                onStartAutoRead()
            } label: {
                Label(localized("自动阅读"), systemImage: "play.fill")
            }
            .buttonStyle(QuickPanelActionButtonStyle())

            Button {
                onOpenTTS?()
            } label: {
                Label(localized("听书"), systemImage: "headphones")
            }
            .buttonStyle(QuickPanelActionButtonStyle())

            Button {
                showingSectionGrid = true
            } label: {
                Label(localized("更多设置"), systemImage: "slider.horizontal.3")
            }
            .buttonStyle(QuickPanelActionButtonStyle())

            Button(action: onCustomize) {
                Label(localized("自定义"), systemImage: "paintbrush")
            }
            .buttonStyle(QuickPanelActionButtonStyle())
        }
    }

    // MARK: - Actions

    private func adjustFontSize(_ delta: CGFloat) {
        fontSize = GlobalSettings.clampedReaderFontSize((fontSize + delta).rounded())
    }

    /// Turning it on hands the reader's mode to the device; turning it off keeps whatever
    /// is on screen. The reader puts the background of the mode in place.
    private func applyFollowSystemAppearance(_ isOn: Bool) {
        settings.setReaderFollowsDevice(isOn, deviceIsDark: colorScheme == .dark)
    }

    /// A saved background, worn as the reader's own pick: the light mode's background.
    private func wear(_ background: ReaderCustomBackground) {
        readerTheme = settings.wearReaderCustomBackground(
            background,
            over: readerTheme,
            deviceIsDark: colorScheme == .dark
        )
    }

    private func pageTurnTitleKey(for option: ReaderQuickPageTurnOption) -> String {
        option == .scroll && isVerticalWritingMode ? "右往左" : option.titleKey
    }
}

/// 更多设置：the settings sheet's nine subjects as a grid. Each cell is one page,
/// half-height and see-through, so a change is made with the paragraph still in view.
private struct ReaderQuickPanelSectionGrid: View {
    let onOpenSection: (Set<ReaderSettingsSection>) -> Void

    private let columns = [
        GridItem(.flexible(), spacing: DSSpacing.md),
        GridItem(.flexible(), spacing: DSSpacing.md),
        GridItem(.flexible(), spacing: DSSpacing.md)
    ]

    var body: some View {
        ScrollView {
            LazyVGrid(columns: columns, spacing: DSSpacing.md) {
                ForEach(ReaderSettingsSection.allCases, id: \.self) { section in
                    Button {
                        onOpenSection([section])
                    } label: {
                        VStack(spacing: DSSpacing.sm) {
                            Image(systemName: section.systemImage)
                                .font(DSFont.title3)
                                .accessibilityHidden(true)
                            Text(localized(section.titleKey))
                                .font(DSFont.caption)
                                .multilineTextAlignment(.center)
                                .lineLimit(2)
                                .minimumScaleFactor(0.8)
                        }
                        .foregroundStyle(DSColor.textPrimary)
                        .frame(maxWidth: .infinity, minHeight: 84)
                        .padding(.horizontal, DSSpacing.xs)
                        .background(DSColor.neutralControlFill, in: RoundedRectangle(cornerRadius: DSRadius.xl, style: .continuous))
                        .overlay(
                            RoundedRectangle(cornerRadius: DSRadius.xl, style: .continuous)
                                .stroke(DSColor.separator, lineWidth: 1)
                        )
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, DSSpacing.xl)
            .padding(.top, DSSpacing.md)
            .padding(.bottom, DSSpacing.xxl)
        }
        .toolbar(.visible, for: .navigationBar)
        // 玻璃卡片上不该再压一条不透明的导览列底色。
        .toolbarBackground(.hidden, for: .navigationBar)
        .navigationTitle(localized("更多设置"))
        .toolbarTitleDisplayMode(.inline)
    }
}

/// One background's tile: its colour or picture, its name, and the selection ring.
/// Built-in and saved ones alike carry the name — only the saved ones did at first,
/// which left the built-in half of the row unnamed (2026-09-29).
///
/// The tile owns its size. Its picture used to be framed by `maxWidth: .infinity`
/// alone, and a flexible frame never shrinks a child wider than the proposal: a
/// scaled-to-fill picture whose aspect is wider than the tile's (74×82, so any
/// landscape picture and even a square one) came back wider than the tile, the
/// whole `ZStack` grew to match, and the row's `.frame(width:)` only centred the
/// result. The star badge then sat over the next tile (feedback #12, iPad).
/// Internal, not private, so a test can measure it.
struct ReaderQuickPanelBackgroundTile: View {
    let fill: Color
    let image: UIImage?
    let title: String
    let titleColor: Color
    let selected: Bool

    private static let width = DSLayout.readerQuickPanelBackgroundTileWidth
    private static let height = DSLayout.readerQuickPanelReadingBackgroundTileHeight

    var body: some View {
        ZStack(alignment: .topTrailing) {
            RoundedRectangle(cornerRadius: DSRadius.xxl, style: .continuous)
                .fill(fill)

            if let image {
                Image(uiImage: image)
                    .resizable()
                    .scaledToFill()
                    .frame(width: Self.width, height: Self.height)
                    .clipped()
                    .accessibilityHidden(true)
                    .allowsHitTesting(false)
            }

            Text(title)
                .font(DSFont.caption)
                .lineLimit(2)
                .multilineTextAlignment(.leading)
                .foregroundStyle(titleColor)
                .padding(.horizontal, DSSpacing.sm)
                .padding(.bottom, DSSpacing.sm)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottomLeading)
                .accessibilityHidden(true)

            if selected {
                Image(systemName: "asterisk")
                    .font(DSFont.subheadline.weight(.semibold))
                    .foregroundStyle(titleColor.opacity(0.6))
                    .padding(.top, DSSpacing.sm)
                    .padding(.trailing, DSSpacing.md)
                    .accessibilityHidden(true)
            }
        }
        .frame(width: Self.width, height: Self.height)
        .clipShape(RoundedRectangle(cornerRadius: DSRadius.xxl, style: .continuous))
        .contentShape(RoundedRectangle(cornerRadius: DSRadius.xxl, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: DSRadius.xxl, style: .continuous)
                .stroke(
                    selected ? DSColor.textPrimary : DSColor.separator,
                    lineWidth: selected ? 3 : 1
                )
        )
        .shadow(color: DSColor.shadow, radius: 6, y: 1)
    }
}

/// Full-width quick-panel action button: darkens and gently compresses while
/// pressed, then springs back on release.
private struct QuickPanelActionButtonStyle: ButtonStyle {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    /// Filled with the accent while auto-read is running, so the panel says what
    /// state the reader is in without a second row of text.
    var isProminent = false

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(DSFont.headline)
            .foregroundStyle(isProminent ? AnyShapeStyle(DSColor.textOnAccent) : AnyShapeStyle(DSColor.textPrimary))
            .frame(maxWidth: .infinity, minHeight: DSLayout.readerQuickPanelControlHeight)
            .background(
                isProminent
                    ? DSColor.accent.opacity(configuration.isPressed ? 0.8 : 1)
                    : (configuration.isPressed ? DSColor.neutralControlPressedFill : DSColor.neutralControlFill),
                in: Capsule()
            )
            .shadow(color: DSColor.shadow, radius: 6, y: 1)
            .scaleEffect(configuration.isPressed && !reduceMotion ? 0.97 : 1)
            .animation(DSAnimation.fast, value: configuration.isPressed)
    }
}

/// Segment sharing one capsule with its neighbor in the A / A control. While
/// pressed, an inset darker capsule appears behind the content; on release it
/// shrinks and fades back out, echoing the Apple Books quick panel.
private struct QuickPanelSegmentButtonStyle: ButtonStyle {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .background(
                Capsule()
                    .fill(DSColor.neutralControlPressedFill)
                    .padding(DSSpacing.xs)
                    .opacity(configuration.isPressed ? 1 : 0)
                    .scaleEffect(configuration.isPressed || reduceMotion ? 1 : 0.85)
            )
            .animation(
                configuration.isPressed ? DSAnimation.fast : DSAnimation.standard,
                value: configuration.isPressed
            )
    }
}

#Preview() {
    ReaderQuickThemePanelView(
        fontSize: .constant(18),
        readerTheme: .constant(.white),
        pageTurnOption: .curl,
        isVerticalWritingMode: false,
        onSelectPageTurnOption: { _ in },
        onStartAutoRead: {},
        onCustomize: {}
    )
}

/// A selected tile wearing a 16:9 picture between two plain ones: the badge must stay
/// inside its own tile and the neighbours must not be overlapped (feedback #12).
#Preview("Background tile, landscape picture") {
    let landscape = UIGraphicsImageRenderer(size: CGSize(width: 320, height: 180)).image { context in
        // Drawn away from any view, where `UIColor(DSColor.accent)` is iOS 17's light blue
        // in dark too; `tintColor` resolves to the system accent here (see `DSUIColor`).
        UIColor.tintColor.setFill()
        context.fill(CGRect(x: 0, y: 0, width: 320, height: 180))
        DSUIColor.textPrimary.setFill()
        context.fill(CGRect(x: 0, y: 120, width: 320, height: 60))
    }
    return HStack(spacing: DSSpacing.md) {
        ReaderQuickPanelBackgroundTile(
            fill: DSColor.neutralControlFill, image: nil, title: "Plain",
            titleColor: DSColor.textPrimary, selected: false
        )
        ReaderQuickPanelBackgroundTile(
            fill: DSColor.neutralControlFill, image: landscape, title: "Landscape",
            titleColor: DSColor.textPrimary, selected: true
        )
        ReaderQuickPanelBackgroundTile(
            fill: DSColor.neutralControlFill, image: nil, title: "Plain",
            titleColor: DSColor.textPrimary, selected: false
        )
    }
    .padding(DSSpacing.xl)
}
