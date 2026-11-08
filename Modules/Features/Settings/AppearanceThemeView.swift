import SwiftUI
import UIKit
import UniformTypeIdentifiers

/// One screen-level message alert, so the import-failure and import-summary
/// paths share a presenter instead of competing for one.
struct ThemeScreenAlert: Identifiable {
    let id = UUID()
    let title: String
    let message: String
}

struct AppearanceThemeView: View {
    @Bindable private var settings = GlobalSettings.shared
    @EnvironmentObject private var subscriptionStore: SubscriptionStore
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    /// The paywall, opened on the feature the locked control belongs to.
    @State private var paywallFeature: PremiumFeature?

    /// 新建's name prompt, and the name typed into it.
    @State private var showNewThemeAlert = false
    @State private var newThemeName = ""
    /// The theme a long press on its tile opened 重新命名／删除 for.
    @State private var themeActionTarget: AppearanceThemePreset?
    /// The tile lifted by that long press — up before the alert, down once it goes.
    @State private var liftedThemeID: String?
    /// The theme being renamed, and the name typed so far.
    @State private var renameTarget: AppearanceThemePreset?
    @State private var renameText = ""
    /// The theme 主题管理's 删除主题 is asking about.
    @State private var deleteTarget: AppearanceThemePreset?
    @State private var showThemeImporter = false
    @State private var showResetAppearanceConfirm = false
    @State private var screenAlert: ThemeScreenAlert?
    /// The 汇入完成 sheet, up from the moment an import starts writing.
    @State private var importProgress: CustomizationImportProgress?
    /// 剑来's tile is importing its pack — the tile shows a spinner and stops taking taps.
    @State private var isInstallingBuiltInTheme = false
    /// Appearance the theme grid is editing: the 浅色／深色 tab's, which the whole window
    /// wears (`GlobalSettings.appearanceWindowColorScheme`), otherwise the one on screen.
    /// Read from the setting rather than `colorScheme` so a pick lands on the slot just
    /// chosen even before the window has redrawn in it.
    private var editingScheme: ColorScheme {
        guard settings.showsAppearanceSlotTab else { return colorScheme }
        return settings.appearanceSlotOnTab(windowColorScheme: colorScheme)
    }

    private var isProActive: Bool {
        subscriptionStore.hasAccess(.readerThemePacks)
    }

    /// Theme selected in the edited slot, as its *identity* — the grid compares
    /// ids and the 新建 / 保存 actions copy from it, so it must not be swapped for
    /// a derived dark palette here.
    private var selectedTheme: AppearanceThemePreset {
        settings.appearanceBaseTheme(
            for: editingScheme,
            isProActive: subscriptionStore.hasAccess(.readerThemePacks)
        )
    }

    /// Theme painting the app right now. Drives this screen's own tint.
    private var activeTheme: AppearanceThemePreset {
        settings.appearanceTheme(
            for: colorScheme,
            isProActive: subscriptionStore.hasAccess(.readerThemePacks)
        )
    }

    /// The selected theme when it is one of the user's own — the one 删除主题 acts on.
    private var selectedCustomTheme: AppearanceCustomTheme? {
        settings.customAppearanceThemes.first { $0.id == selectedTheme.id }
    }

    private var customThemes: [AppearanceThemePreset] {
        // 剑来 has a tile of its own, ahead of these; once imported it is also a stored
        // record, and showing it twice would read as two themes.
        let builtInID = BuiltInAppearanceTheme.installedThemeID
        return settings.customAppearanceThemes
            .filter { $0.id != builtInID }
            .map(AppearanceThemePreset.preset(from:))
    }

    private var gridColumns: [GridItem] {
        let count = horizontalSizeClass == .compact ? 4 : 5
        return Array(repeating: GridItem(.flexible(), spacing: DSSpacing.md), count: count)
    }

    var body: some View {
        // Grouped as the reference the user handed over (2026-09-29): which theme and how
        // it follows light and dark, then 介面 (what surrounds the content), 外观 (the
        // theme's colours, the page behind it, its effects — each a page of its own),
        // and the themes themselves. A theme no longer opens a page of its own. Every
        // row wears `SettingsRowLabel`, as 设置 and 阅读设置 do.
        List {
            themeSelectionSection
            lightDarkSection
            interfaceSection
            appearanceSection
            themeManagementSection
        }
        .softScrollEdges()
        .listStyle(.insetGrouped)
        .scrollContentBackground(.hidden)
        .contentMargins(.bottom, DSSpacing.xxl * 2, for: .scrollContent)
        .themedAppSurface(for: .settings)
        .navigationTitle(localized("外观主题"))
        .toolbarTitleDisplayMode(.inline)
        .tint(activeTheme.isClassic ? nil : activeTheme.accentColor)
        .sheet(item: $paywallFeature) { _ in
            CardKeyUnlockView()
        }
        .sheet(item: $importProgress) { progress in
            CustomizationImportOverviewView(progress: progress) {
                importProgress = nil
            }
        }
        // One alert modifier for the whole screen. Stacking several `.alert`s on
        // the same view is how one of them silently stops presenting — they all
        // compete for the same presenter.
        .alert(
            screenAlert?.title ?? "",
            isPresented: Binding(
                get: { screenAlert != nil },
                set: { if !$0 { screenAlert = nil } }
            ),
            presenting: screenAlert
        ) { _ in
            Button(localized("确定"), role: .cancel) {
                screenAlert = nil
            }
        } message: { alert in
            Text(alert.message)
        }
    }

    private var themeSelectionSection: some View {
        Section {
            themeSelectionCard
            if !subscriptionStore.hasAccess(.readerThemePacks) {
                customizationRow
            }
        } header: {
            Text(localized("主题"))
                .foregroundStyle(DSColor.textSecondary)
        } footer: {
            if !subscriptionStore.hasAccess(.readerThemePacks) {
                Text(localized("自订应用配色、阅读配色与页面背景需开通会员。"))
                    .dsSectionFooter()
            }
        }
        .interfaceSectionSurface()
    }

    /// A long press on a theme of the user's own: the tile pops up, and once it is up,
    /// 重新命名／删除 comes up over it — the order a Home Screen icon lifts before its
    /// menu. The animation's own completion opens the alert, not a delay.
    private func liftTheme(_ preset: AppearanceThemePreset) {
        guard !reduceMotion else {
            liftedThemeID = preset.id
            themeActionTarget = preset
            return
        }
        withAnimation(DSAnimation.press, completionCriteria: .logicallyComplete) {
            liftedThemeID = preset.id
        } completion: {
            themeActionTarget = preset
        }
    }

    /// 重新命名, from a tile's long press.
    private func beginRename(_ preset: AppearanceThemePreset) {
        renameText = preset.localizedName
        renameTarget = preset
    }

    /// How the look follows the system's light and dark, and which reading background
    /// each of the reader's two modes wears.
    private var lightDarkSection: some View {
        Section {
            Toggle(isOn: appearanceFollowsSystemBinding) {
                SettingsRowLabel(localized("跟随系统"), systemImage: "circle.lefthalf.filled")
            }
            Toggle(isOn: $settings.appearanceUsesSeparateDarkTheme) {
                SettingsRowLabel(localized("单独设置深色主题"), systemImage: "moon")
            }
            Toggle(isOn: $settings.appearanceBindReaderTheme) {
                SettingsRowLabel(localized("绑定阅读主题"), systemImage: "book")
            }
            if settings.appearanceBindReaderTheme {
                boundReaderThemeRow(titleKey: "浅色阅读主题", systemImage: "sun.max", appearance: .light)
                boundReaderThemeRow(titleKey: "深色阅读主题", systemImage: "moon.fill", appearance: .dark)
            }
        } header: {
            Text(localized("主题切换"))
                .foregroundStyle(DSColor.textSecondary)
        } footer: {
            if settings.appearanceBindReaderTheme {
                Text(localized("阅读器在浅色模式用浅色阅读主题，深色模式用深色阅读主题。要跟著装置的深浅色自动切换，在阅读器的「设置」面板开启「跟随装置深浅色」。"))
                    .dsSectionFooter()
            }
        }
        .interfaceSectionSurface()
        .animation(reduceMotion ? nil : DSAnimation.standard, value: settings.appearanceBindReaderTheme)
    }

    /// What surrounds the content: the reader's chrome, the tab bar, the bookshelf grid
    /// and its covers, the launch screen. 每列栏数 and 预设封面 moved here from 设置's
    /// 书架显示 (2026-09-29), where the theme they belong to could not be seen.
    private var interfaceSection: some View {
        Section {
            NavigationLink {
                AppearanceReaderInterfaceView()
            } label: {
                SettingsRowLabel(localized("阅读界面"), systemImage: "menubar.rectangle")
            }
            // In view without Pro too, locked (2026-09-27).
            rootTabRow
            Picker(selection: $settings.bookshelfGridColumnCount) {
                ForEach(GlobalSettings.bookshelfGridColumnCountOptions, id: \.self) { columnCount in
                    Text(String(format: localized("%d 栏"), columnCount))
                        .tag(columnCount)
                }
            } label: {
                SettingsRowLabel(localized("每列栏数"), systemImage: "square.grid.3x3.fill")
            }
            .pickerStyle(.menu)
            NavigationLink {
                DefaultCoverSettingsView()
            } label: {
                SettingsRowLabel(localized("预设封面"), systemImage: "photo.stack.fill")
            }
            launchImageRow
        } header: {
            Text(localized("介面"))
                .foregroundStyle(DSColor.textSecondary)
        }
        .interfaceSectionSurface()
    }

    /// The theme's own look, a page each: its colours and the global font, the page
    /// behind everything, and the interface effects.
    private var appearanceSection: some View {
        Section {
            NavigationLink {
                AppearanceColorsAndFontView()
            } label: {
                SettingsValueLabel(
                    title: localized("颜色与字体"),
                    systemImage: "paintpalette",
                    value: settings.globalFontDisplayName
                )
            }
            if subscriptionStore.hasAccess(.readerThemePacks) {
                NavigationLink {
                    AppearancePageBackgroundView()
                } label: {
                    SettingsRowLabel(localized("页面背景"), systemImage: "photo.on.rectangle")
                }
            } else {
                SettingsLockedRow(title: localized("页面背景"), systemImage: "photo.on.rectangle") {
                    paywallFeature = .readerThemePacks
                }
            }
            NavigationLink {
                AppearanceInterfaceEffectsView()
            } label: {
                SettingsValueLabel(title: localized("界面效果"), systemImage: "sparkles", value: interfaceEffectsSummary)
            }
        } header: {
            Text(localized("外观"))
                .foregroundStyle(DSColor.textSecondary)
        }
        .interfaceSectionSurface()
    }

    // Deliberately outside the Pro gate. An appearance pack — ours or a QiReader
    // `.qitheme` — mostly carries things that are not Pro features at all: page
    // backgrounds, tab icons, default covers, the bundled font, interface effects,
    // reader layout, chapter title and comment bubble. Hiding the importer meant a
    // non-Pro user handed a pack had no way to open it, and no explanation either.
    // The custom theme a pack carries still needs Pro to take effect; `ContentView`'s
    // `resolvedAppTheme` already downgrades it on its own, so nothing here has to.
    private var themeManagementSection: some View {
        Section {
            themeActionRows
        } header: {
            Text(localized("主题管理"))
                .foregroundStyle(DSColor.textSecondary)
        } footer: {
            Text(localized("「导出主题」包含所有自订主题、自带主题的配色、页面背景图、Tab 图示、启动图与阅读背景。"))
                .dsSectionFooter()
        }
        .interfaceSectionSurface()
    }

    private var themeSelectionCard: some View {
        VStack(alignment: .leading, spacing: DSSpacing.lg) {
            if settings.showsAppearanceSlotTab {
                themeSlotPicker
            }
            LazyVGrid(columns: gridColumns, spacing: DSSpacing.lg) {
                // As coloured in 颜色与字体, not as shipped: the tile's dot and the ring
                // round the selected one are 强调色, so an edited accent shows here too.
                themeOption(settings.builtInThemePreset(AppearanceThemePreset.classic, isProActive: isProActive))
                ForEach(AppearanceThemePreset.freeSolidPresets) { preset in
                    themeOption(settings.builtInThemePreset(preset, isProActive: isProActive))
                }
                newThemeButton
            }
            // On the built-in grid, which is always there: a tile's own alert would go
            // with the tile, and the card below already has the long-press one — two on
            // one view compete for one presenter.
            .alert(
                localized("重新命名主题"),
                isPresented: Binding(
                    get: { renameTarget != nil },
                    set: { if !$0 { renameTarget = nil } }
                ),
                presenting: renameTarget
            ) { preset in
                TextField(localized("主题名称"), text: $renameText)
                Button(localized("确定")) {
                    settings.renameCustomAppearanceTheme(id: preset.id, to: renameText)
                }
                Button(localized("取消"), role: .cancel) {}
            }

            themeGroupTitle(localized("自订主题"))
            LazyVGrid(columns: gridColumns, spacing: DSSpacing.lg) {
                builtInThemeOption
                ForEach(customThemes) { preset in
                    themeOption(preset)
                }
            }

            if !AppearanceThemePreset.bundledThemePacks.isEmpty {
                themeGroupTitle(localized("主题包"))
                LazyVGrid(columns: gridColumns, spacing: DSSpacing.lg) {
                    ForEach(AppearanceThemePreset.bundledThemePacks) { preset in
                        themeOption(preset)
                    }
                }
            }
        }
        .animation(reduceMotion ? nil : DSAnimation.standard, value: settings.showsAppearanceSlotTab)
        // The long press lands with a firm tap of the Taptic Engine as the tile lifts —
        // the medium one was too faint to notice (2026-09-29).
        .sensoryFeedback(.impact(weight: .heavy, intensity: 1), trigger: liftedThemeID) { _, lifted in
            lifted != nil
        }
        .onChange(of: themeActionTarget) { _, target in
            guard target == nil, liftedThemeID != nil else { return }
            withAnimation(reduceMotion ? nil : DSAnimation.standard) {
                liftedThemeID = nil
            }
        }
        // On the card, not the tile: 删除 removes the tile, and an alert torn down by its
        // own action can be left half-dismissed.
        .alert(
            themeActionTarget?.localizedName ?? "",
            isPresented: Binding(
                get: { themeActionTarget != nil },
                set: { if !$0 { themeActionTarget = nil } }
            ),
            presenting: themeActionTarget
        ) { preset in
            Button(localized("重新命名")) {
                beginRename(preset)
            }
            Button(localized("删除"), role: .destructive) {
                settings.deleteCustomAppearanceTheme(id: preset.id)
            }
            Button(localized("取消"), role: .cancel) {}
        } message: { _ in
            Text(localized("删除后，使用此主题的外观会回到预设。"))
        }
    }

    /// Chooses which appearance the grid below is picking a theme for, and flips the
    /// whole app into it so the pick can be judged against the real thing. With 跟随系统
    /// off that is the app's appearance, kept; with it on, a preview until 设置 is back.
    /// 深色 shows each theme's dark version, not one black theme.
    private var themeSlotPicker: some View {
        VStack(alignment: .leading, spacing: DSSpacing.sm) {
            Picker(
                localized("主题外观"),
                selection: Binding(
                    get: { editingScheme },
                    set: { settings.pickAppearanceSlot($0) }
                )
            ) {
                Text(localized("浅色")).tag(ColorScheme.light)
                Text(localized("深色")).tag(ColorScheme.dark)
            }
            .pickerStyle(.segmented)
            .accessibilityLabel(localized("主题外观"))

            Text(localized(
                settings.appearanceFollowsSystem
                    ? "深色分页会以深色主题预览整个介面，选的是同一批主题的深色版本。"
                    : "跟随系统关闭时，App 固定使用这里选的浅色或深色。"
            ))
                .font(DSFont.caption)
                .foregroundStyle(DSColor.textSecondary)
        }
    }

    private func themeGroupTitle(_ title: String) -> some View {
        Text(title)
            .font(DSFont.subheadline.weight(.semibold))
            .foregroundStyle(DSColor.textSecondary)
            .padding(.top, DSSpacing.xs)
    }

    /// 出厂的剑来主题，排在自订主题第一位。
    ///
    /// 它是会员权益：没开通时卡片带锁，点它开的是开通面板，跟其他自订主题一致。开通后点
    /// 它才汇入——汇入一次，之后就是一条普通的自订主题记录，选中、切换都走同一条路，
    /// 不再另存一份（`BuiltInAppearanceTheme.install`）。
    private var builtInThemeOption: some View {
        let locked = !subscriptionStore.hasAccess(.readerThemePacks)
        let installedID = BuiltInAppearanceTheme.installedThemeID
        // Only a stored record can be the selected one; the placeholder id never is.
        let selected = installedID != nil && selectedTheme.id == installedID
        let preview = BuiltInAppearanceTheme.previewPreset(for: editingScheme)

        return Button {
            guard !locked else {
                paywallFeature = .readerThemePacks
                return
            }
            guard !isInstallingBuiltInTheme else { return }
            if let id = installedID,
               let record = settings.customAppearanceThemes.first(where: { $0.id == id }) {
                settings.setAppearanceTheme(
                    AppearanceThemePreset.preset(from: record),
                    for: editingScheme,
                    activeAppearance: editingScheme
                )
                return
            }
            isInstallingBuiltInTheme = true
            Task { @MainActor in
                let id = await BuiltInAppearanceTheme.install()
                isInstallingBuiltInTheme = false
                guard let id,
                      let record = settings.customAppearanceThemes.first(where: { $0.id == id })
                else {
                    screenAlert = ThemeScreenAlert(
                        title: localized("汇入失败"),
                        message: localized("剑来主题没能汇入，请稍后再试。")
                    )
                    return
                }
                settings.setAppearanceTheme(
                    AppearanceThemePreset.preset(from: record),
                    for: editingScheme,
                    activeAppearance: editingScheme
                )
            }
        } label: {
            VStack(spacing: DSSpacing.sm) {
                ZStack {
                    ThemePreviewTile(
                        preset: preview,
                        isSelected: selected,
                        isLocked: locked,
                        colorScheme: editingScheme
                    )
                    if isInstallingBuiltInTheme {
                        ProgressView()
                            .tint(.white)
                    }
                }
                Text(BuiltInAppearanceTheme.displayName)
                    .font(DSFont.caption)
                    .foregroundStyle(locked ? DSColor.textDisabled : DSColor.textPrimary)
                    .lineLimit(2)
                    .multilineTextAlignment(.center)
                    .minimumScaleFactor(0.72)
                    .frame(minHeight: 32, alignment: .top)
            }
            .contentShape(Rectangle())
        }
        // Nothing to rename or delete here: the stored record is managed from 主题管理.
        .buttonStyle(ThemeTileButtonStyle(onLongPress: nil))
        .disabled(isInstallingBuiltInTheme)
        .accessibilityLabel(BuiltInAppearanceTheme.displayName)
        .accessibilityAddTraits(selected ? .isSelected : [])
    }

    private func themeOption(_ preset: AppearanceThemePreset) -> some View {
        let locked = preset.requiresPro && !subscriptionStore.hasAccess(.readerThemePacks)
        // Ring marks the theme actually in effect (not a stored-but-locked pick).
        let selected = selectedTheme.id == preset.id
        // Only the user's own themes can be renamed or deleted.
        let editable = preset.isCustom && !locked
        // Preview in the appearance being edited: the dark slot shows this
        // theme's dark palette, which is what selecting it will apply.
        let displayed = preset.palette(for: editingScheme)
        return Button {
            guard !locked else {
                paywallFeature = .readerThemePacks
                return
            }
            settings.setAppearanceTheme(
                preset,
                for: editingScheme,
                // The window wears `editingScheme` (`appearanceWindowColorScheme`), so
                // that is the appearance on screen — `colorScheme` may not have caught up
                // with a tab picked a moment ago.
                activeAppearance: editingScheme
            )
        } label: {
            VStack(spacing: DSSpacing.sm) {
                ThemePreviewTile(
                    preset: displayed,
                    isSelected: selected,
                    isLocked: locked,
                    colorScheme: editingScheme
                )
                Text(preset.localizedName)
                    .font(DSFont.caption)
                    .foregroundStyle(locked ? DSColor.textDisabled : DSColor.textPrimary)
                    .lineLimit(2)
                    .multilineTextAlignment(.center)
                    .minimumScaleFactor(0.72)
                    .frame(minHeight: 32, alignment: .top)
            }
            .contentShape(Rectangle())
        }
        // A long press on a theme of the user's own asks 重新命名 or 删除 in an alert —
        // not a context menu, whose actions could not raise an alert on iOS 17
        // (Technotes/iOS17MenuModalPresentation.md). 主题管理 has 删除主题 as a row too.
        .buttonStyle(ThemeTileButtonStyle(
            onLongPress: editable ? { liftTheme(preset) } : nil,
            isLifted: liftedThemeID == preset.id
        ))
        // Above its neighbours while it is lifted, or they would cover it.
        .zIndex(liftedThemeID == preset.id ? 1 : 0)
        .accessibilityActions {
            if editable {
                Button(localized("重新命名")) { beginRename(preset) }
                Button(localized("删除")) { deleteTarget = preset }
            }
        }
        .accessibilityLabel(preset.localizedName)
        .accessibilityAddTraits(selected ? .isSelected : [])
    }

    private var newThemeButton: some View {
        Button {
            guard subscriptionStore.hasAccess(.readerThemePacks) else {
                paywallFeature = .readerThemePacks
                return
            }
            newThemeName = ""
            showNewThemeAlert = true
        } label: {
            VStack(spacing: DSSpacing.sm) {
                ZStack {
                    RoundedRectangle(cornerRadius: DSRadius.lg, style: .continuous)
                        .fill(DSColor.textSecondary.opacity(0.2))
                    Image(systemName: subscriptionStore.hasAccess(.readerThemePacks) ? "plus" : "lock.fill")
                        .font(DSFont.fixed(size: 24, weight: .semibold))
                        .foregroundStyle(selectedTheme.palette(for: editingScheme).accentColor)
                }
                .frame(maxWidth: .infinity)
                .frame(height: 58)
                Text(localized("新建"))
                    .font(DSFont.caption)
                    .foregroundStyle(subscriptionStore.hasAccess(.readerThemePacks) ? DSColor.textPrimary : DSColor.textDisabled)
                    .lineLimit(1)
                    .minimumScaleFactor(0.76)
                    .frame(minHeight: 32, alignment: .top)
            }
        }
        .buttonStyle(.plain)
        .accessibilityLabel(localized("新建"))
        // A name, then the whole look on screen — colours, page backgrounds, icons, font
        // and all — becomes the new theme, selected in the slot being edited. This was
        // two rows: 新建 copied the colours alone and opened an editor page, and
        // 保存为新主题 saved the whole look (2026-09-29).
        .alert(localized("新建主题"), isPresented: $showNewThemeAlert) {
            TextField(localized("主题名称"), text: $newThemeName)
            Button(localized("新建")) {
                settings.saveCurrentAppearanceAsTheme(
                    named: newThemeName,
                    basedOn: selectedTheme,
                    for: editingScheme
                )
            }
            Button(localized("取消"), role: .cancel) {}
        } message: {
            Text(localized("目前的整套外观会存成这个新主题。"))
        }
    }

    private var appearanceFollowsSystemBinding: Binding<Bool> {
        Binding(
            get: { settings.appearanceFollowsSystem },
            set: {
                // Turned off, the appearance on the tab — previewed or not — is kept.
                settings.setAppearanceFollowsSystem(
                    $0,
                    currentColorScheme: editingScheme
                )
            }
        )
    }

    /// One appearance's reading-background pick, shown while 绑定阅读主题 is on.
    private func boundReaderThemeRow(titleKey: String, systemImage: String, appearance: ColorScheme) -> some View {
        Picker(selection: Binding(
            get: { settings.boundReaderTheme(for: appearance) },
            set: { settings.setBoundReaderTheme($0, for: appearance) }
        )) {
            ForEach(settings.boundReaderThemeOptions) { option in
                Text(settings.title(for: option)).tag(option)
            }
        } label: {
            SettingsRowLabel(localized(titleKey), systemImage: systemImage)
        }
    }

    /// Names whichever effects are on, so the row says something useful without
    /// opening it. Both off reads 已关闭.
    private var interfaceEffectsSummary: String {
        var parts: [String] = []
        if settings.interfaceGlowIntensity > 0 {
            parts.append(localized("光晕"))
        }
        if settings.interfaceFrostedGlass {
            parts.append(localized("毛玻璃"))
        }
        guard !parts.isEmpty else { return localized("已关闭") }
        // Locale-correct joiner ("光晕、毛玻璃" / "Glow, Frosted Glass") instead of a
        // hardcoded separator that only reads right in one language.
        return parts.formatted(.list(type: .and, width: .narrow))
    }

    /// Pro pushes the settings page; without Pro the row is the paywall.
    @ViewBuilder
    private var launchImageRow: some View {
        if subscriptionStore.hasAccess(.launchScreen) {
            NavigationLink {
                LaunchImageSettingsView()
            } label: {
                SettingsValueLabel(
                    title: localized("启动图"),
                    systemImage: "iphone",
                    value: localized(settings.launchImageEnabled ? "已开启" : "已关闭")
                )
            }
        } else {
            SettingsLockedRow(title: localized("启动图"), systemImage: "iphone") {
                paywallFeature = .launchScreen
            }
        }
    }

    @ViewBuilder
    private var rootTabRow: some View {
        if ReaderPremiumVisibilityPolicy(isProActive: subscriptionStore.isProActive).showsBottomTabCustomization {
            NavigationLink {
                RootTabCustomizationView()
            } label: {
                SettingsRowLabel(localized("底部 Tab"), systemImage: "square.grid.2x2")
            }
        } else {
            SettingsLockedRow(title: localized("底部 Tab"), systemImage: "square.grid.2x2") {
                paywallFeature = .bottomBarCustomization
            }
        }
    }

    // MARK: - Theme actions (save / export / import / reset)

    @ViewBuilder
    private var themeActionRows: some View {
        // One export for the whole look, named after the theme on screen. There used to
        // be two — 导出主题 (one theme's colours and page backgrounds) and 导出全部自定义 —
        // but a theme is the whole look now, as an imported pack is (2026-09-29).
        ShareLink(
            item: themeExportPayload,
            preview: SharePreview(selectedTheme.localizedName)
        ) {
            SettingsRowLabel(localized("导出主题"), systemImage: "square.and.arrow.up", role: .action)
        }
        // 删除主题's confirmation, on a row that is always there: the 删除主题 row goes
        // with the theme, and an alert torn down by its own action can be left
        // half-dismissed.
        .alert(
            String(format: localized("删除「%@」？"), deleteTarget?.localizedName ?? ""),
            isPresented: Binding(
                get: { deleteTarget != nil },
                set: { if !$0 { deleteTarget = nil } }
            ),
            presenting: deleteTarget
        ) { preset in
            Button(localized("删除"), role: .destructive) {
                settings.deleteCustomAppearanceTheme(id: preset.id)
            }
            Button(localized("取消"), role: .cancel) {}
        } message: { _ in
            Text(localized("删除后，使用此主题的外观会回到预设。"))
        }

        Button {
            showThemeImporter = true
        } label: {
            SettingsRowLabel(localized("导入主题"), systemImage: "square.and.arrow.down", role: .action)
        }
        .fileImporter(
            isPresented: $showThemeImporter,
            allowedContentTypes: [
                .json,
                .yueduReaderStyle,
                UTType(filenameExtension: "qitheme") ?? .data,
                UTType(filenameExtension: "red") ?? .data,
                UTType(filenameExtension: "theme") ?? .data,
                .zip,
            ],
            allowsMultipleSelection: false,
            onCompletion: handleThemeImport
        )

        if let custom = selectedCustomTheme {
            Button(role: .destructive) {
                deleteTarget = AppearanceThemePreset.preset(from: custom)
            } label: {
                SettingsRowLabel(localized("删除主题"), systemImage: "trash", role: .destructive)
            }
        }

        // A built-in theme's only: it has a default look to go back to. A theme of the
        // user's own — an imported pack included — is its own look, and is renamed or
        // deleted instead (2026-09-29).
        if selectedCustomTheme == nil {
            Button(role: .destructive) {
                showResetAppearanceConfirm = true
            } label: {
                SettingsRowLabel(localized("重置为默认"), systemImage: "arrow.counterclockwise", role: .destructive)
            }
            .alert(localized("重置为默认？"), isPresented: $showResetAppearanceConfirm) {
                Button(localized("重置为默认"), role: .destructive) {
                    settings.resetAppearanceToDefault()
                }
                Button(localized("取消"), role: .cancel) {}
            } message: {
                Text(localized("主题、自带主题的配色、页面背景、Tab 图示、全局字体、介面效果、阅读介面与启动图会回到预设。你的主题、主题包、书架与封面设置、阅读设置都会保留。"))
            }
        }
    }

    /// Cheap to build — values and file names now, bytes at share time — so it is
    /// safe in a row SwiftUI rebuilds with its parent.
    private var themeExportPayload: AppearanceCustomizationExportPayload {
        AppearanceCustomizationExportPayload(
            filename: AppearanceCustomizationExportPayload.filename(for: selectedTheme.localizedName),
            snapshot: settings.appearanceCustomizationSnapshot()
        )
    }

    private func handleThemeImport(_ result: Result<[URL], Error>) {
        do {
            guard let url = try result.get().first else { return }
            let didAccess = url.startAccessingSecurityScopedResource()
            defer {
                if didAccess { url.stopAccessingSecurityScopedResource() }
            }
            let data = try Data(contentsOf: url)
            if QiThemeImporter.hasQiThemeExtension(url)
                || ReedenThemeImporter.hasRedExtension(url)
                || YuejingThemeImporter.hasYuejingExtension(url) {
                handleQiThemeImport(data, fileExtension: url.pathExtension)
                return
            }
            Task { @MainActor in
                do {
                    let summary = try await settings.importAppearanceCustomizationPackage(from: data)
                    let selected = summary.selectedThemeID.flatMap { id in
                        settings.customAppearanceThemes.first { $0.id == id }
                    }
                    // Up only once the import has finished — after an `await`, so never
                    // while the document picker is still on its way out.
                    importProgress = CustomizationImportProgress(phase: .finished(
                        CustomizationImportOverview(appearance: summary, selectedTheme: selected)
                    ))
                } catch let error as AppearanceThemeImportError {
                    showImportFailure(localized(error.messageKey))
                } catch {
                    showImportFailure(localized("汇入主题失败。"))
                }
            }
        } catch let error as AppearanceThemeImportError {
            showImportFailure(localized(error.messageKey))
        } catch {
            showImportFailure(localized("汇入主题失败。"))
        }
    }

    /// QiReader `.qitheme`, Reeden `.red` and 阅境 `.zip` packs are foreign archives
    /// `ReaderStylePackage` cannot read, so they get their own parse before any of the
    /// native routes are tried.
    private func handleQiThemeImport(_ data: Data, fileExtension: String? = nil) {
        Task { @MainActor in
            do {
                // Nothing to ask: the pack's reading setup is its theme's own.
                applyQiTheme(try await QiThemeImportService.load(data, fileExtension: fileExtension))
            } catch let error as QiThemeImportError {
                showImportFailure(error.errorDescription ?? localized("汇入主题失败。"))
            } catch {
                showImportFailure(localized("汇入主题失败。"))
            }
        }
    }

    private func applyQiTheme(_ theme: QiThemeImport) {
        // Installing a pack's font takes a moment; the sheet shows it happening.
        let progress = CustomizationImportProgress()
        importProgress = progress
        Task { @MainActor in
            do {
                let outcome = try await QiThemeImportService.apply(theme)
                progress.phase = .finished(CustomizationImportOverview(qiTheme: outcome))
            } catch {
                AppLogger.error("⟐ qitheme import failed", error: error)
                progress.phase = .failed(
                    (error as? LocalizedError)?.errorDescription ?? localized("汇入主题失败。")
                )
            }
        }
    }

    private func showImportFailure(_ message: String) {
        screenAlert = ThemeScreenAlert(title: localized("汇入失败"), message: message)
    }

    /// Free-user upsell row; hidden entirely once Pro is active.
    private var customizationRow: some View {
        Button {
            paywallFeature = .readerThemePacks
        } label: {
            HStack(spacing: DSSpacing.md) {
                // Pro is marked with the app's own icon, as on the 阅读Pro row and page.
                AppIconImage(size: DSLayout.settingsRowIconSize)
                Text(localized("主题自定义"))
                    .font(DSFont.body)
                    .foregroundStyle(DSColor.textPrimary)
                Spacer(minLength: 0)
                Image(systemName: "lock.fill")
                    .foregroundStyle(DSColor.textSecondary)
                    .accessibilityHidden(true)
            }
        }
        .buttonStyle(.plain)
    }
}

private struct ThemePreviewTile: View {
    let preset: AppearanceThemePreset
    let isSelected: Bool
    let isLocked: Bool
    let colorScheme: ColorScheme

    private let tileHeight: CGFloat = 58

    var body: some View {
        // Rigid cell-width × fixed-height frame + clip so an image preview
        // (scaledToFill) can never overflow into the neighbouring tile.
        previewBackground
            .frame(maxWidth: .infinity)
            .frame(height: tileHeight)
            .clipShape(RoundedRectangle(cornerRadius: DSRadius.lg, style: .continuous))
            .overlay(alignment: .topLeading) {
                if assetPreviewImage == nil, !preset.isImagePreset {
                    swatchContent
                }
            }
            .overlay {
                if isLocked {
                    ZStack {
                        RoundedRectangle(cornerRadius: DSRadius.lg, style: .continuous)
                            .fill(Color.black.opacity(0.16))
                        Image(systemName: "lock.fill")
                            .font(DSFont.fixed(size: 22, weight: .semibold))
                            .foregroundStyle(.white)
                    }
                }
            }
            .overlay(
                RoundedRectangle(cornerRadius: DSRadius.lg, style: .continuous)
                    .stroke(isSelected ? preset.accentColor : Color.clear, lineWidth: 3)
            )
    }

    /// Mini "reader page" sketch shown on solid-color swatches.
    private var swatchContent: some View {
        HStack(alignment: .top, spacing: DSSpacing.sm) {
            Circle()
                .fill(preset.accentColor)
                .frame(width: 16, height: 16)

            VStack(alignment: .leading, spacing: 5) {
                RoundedRectangle(cornerRadius: 2)
                    .fill(preset.textColor)
                    .frame(width: 40, height: 4)
                RoundedRectangle(cornerRadius: 2)
                    .fill(preset.textColor.opacity(0.78))
                    .frame(width: 30, height: 4)
                RoundedRectangle(cornerRadius: 2)
                    .fill(preset.textColor.opacity(0.42))
                    .frame(width: 22, height: 4)
            }
            Spacer(minLength: 0)
        }
        .padding(DSSpacing.md)
    }

    @ViewBuilder
    private var previewBackground: some View {
        if let image = assetPreviewImage {
            Image(uiImage: image)
                .resizable()
                .scaledToFill()
        } else if preset.isImagePreset,
           let url = preset.backgroundImageURL(colorScheme: colorScheme),
           let image = UIImage(contentsOfFile: url.path) {
            Image(uiImage: image)
                .resizable()
                .scaledToFill()
        } else {
            LinearGradient(
                colors: [
                    preset.previewBackgroundColor,
                    preset.dialogueColor.opacity(0.72)
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
        }
    }

    /// Themes whose artwork ships in the asset catalog rather than in
    /// `Assets/ReaderThemes` — 剑来 is the only one. Its tile shows the real page behind
    /// it instead of a colour sketch.
    private var assetPreviewImage: UIImage? {
        let name = colorScheme == .dark
            ? (preset.darkAssetPreviewName ?? preset.assetPreviewName)
            : preset.assetPreviewName
        guard let name else { return nil }
        return UIImage(named: name)
    }
}

private struct AppearanceReaderInterfaceView: View {
    @Bindable private var settings = GlobalSettings.shared

    /// The reading background the reader is currently painting with, so the preview
    /// shows the chrome against the surface it will actually sit on. Read once per
    /// body pass: the reading background can only change from inside the reader, which
    /// this page is never on screen for.
    private var previewTheme: ReaderTheme { ReaderTheme.loadPersisted() }

    private var palette: ReaderChromePalette {
        ReaderChromePalette(theme: previewTheme, settings: settings)
    }

    var body: some View {
        Form {
            Section {
                chromePreview

                ForEach(ReaderChromeSlot.allCases) { slot in
                    colorRow(slot)
                }

                NavigationLink {
                    ReaderChromeIconSettingsView()
                } label: {
                    HStack {
                        Text(localized("按钮图示"))
                            .font(DSFont.body)
                            .foregroundStyle(DSColor.textPrimary)
                        Spacer(minLength: DSSpacing.md)
                        Text(iconSummary)
                            .font(DSFont.body)
                            .foregroundStyle(DSColor.textSecondary)
                    }
                }

                if settings.hasReaderChromeOverride {
                    Button {
                        settings.resetReaderChrome()
                    } label: {
                        Label(localized("跟随阅读主题"), systemImage: "arrow.counterclockwise")
                    }
                }
            } header: {
                Text(localized("自定义"))
                    .font(DSFont.headline)
                    .foregroundStyle(DSColor.textPrimary)
            } footer: {
                Text(localized("顶栏是系统玻璃，只能改图示颜色；强调色用在开启中的「深色」和书卡的图示。未调整的部分跟随目前的阅读主题。"))
                    .dsSectionFooter()
            }
            .interfaceSectionSurface()
        }
        .softScrollEdges()
        .scrollContentBackground(.hidden)
        .navigationTitle(localized("阅读界面"))
        .toolbarTitleDisplayMode(.inline)
        .themedAppSurface(for: .settings)
    }

    /// 目录／深色／听书／主题 and the book card's actions, so the row says something
    /// without opening it.
    private var iconSummary: String {
        let custom = settings.readerChromeIcons.count
        let hidden = settings.readerChromeHiddenIDs.count
        var parts: [String] = []
        if custom > 0 { parts.append(String(format: localized("已换 %d 个"), custom)) }
        if hidden > 0 { parts.append(String(format: localized("已隐藏 %d 个"), hidden)) }
        guard !parts.isEmpty else { return localized("预设") }
        return parts.formatted(.list(type: .and, width: .narrow))
    }

    private func colorRow(_ slot: ReaderChromeSlot) -> some View {
        ColorPicker(selection: colorBinding(slot), supportsOpacity: false) {
            Text(localized(slot.titleKey))
                .font(DSFont.body)
                .foregroundStyle(DSColor.textPrimary)
        }
    }

    /// Opens on the colour that is on screen right now rather than a blank swatch,
    /// the same contract as the reader's 文字颜色 picker. Writing one stores an
    /// override; clearing every override is the 跟随阅读主题 button, not a colour.
    private func colorBinding(_ slot: ReaderChromeSlot) -> Binding<Color> {
        Binding(
            get: { palette.color(for: slot) },
            set: { settings.setReaderChromeColor(UIColor($0).rgbHex, slot: slot) }
        )
    }

    /// The real chrome, drawn with the real palette on the real reading background —
    /// the section is about how the reader looks, so swatches would not answer the
    /// only question anyone has here. A miniature of the reader: the title capsule and
    /// cover circle up top, the scrubber and tool capsules floating at the bottom.
    private var chromePreview: some View {
        let palette = palette
        return VStack(spacing: 0) {
            HStack(spacing: DSSpacing.md) {
                Image(systemName: "chevron.left")
                Spacer(minLength: 0)
                Text(localized("书名"))
                    .font(DSFont.fixed(size: 11, weight: .medium))
                    .padding(.horizontal, DSSpacing.lg)
                    .frame(height: 22)
                    .overlay(Capsule().stroke(palette.topIcon.opacity(0.25), lineWidth: 0.5))
                Spacer(minLength: 0)
                Circle()
                    .fill(palette.panelFill)
                    .frame(width: 22, height: 22)
                    .overlay(Circle().stroke(palette.topIcon.opacity(0.25), lineWidth: 0.5))
            }
            .font(DSFont.fixed(size: 13, weight: .medium))
            .foregroundStyle(palette.topIcon)
            .padding(.horizontal, DSSpacing.md)
            .frame(height: 34)

            Spacer(minLength: 24)

            VStack(spacing: DSSpacing.xs) {
                HStack(spacing: DSSpacing.sm) {
                    Image(systemName: "chevron.left")
                    HStack(spacing: 0) {
                        Capsule().fill(palette.bottomIcon).frame(width: 48)
                        Capsule().fill(palette.bottomIcon.opacity(0.2))
                    }
                    .frame(height: 3)
                    Image(systemName: "chevron.right")
                }
                .font(DSFont.fixed(size: 12, weight: .medium))
                .foregroundStyle(palette.bottomIcon)
                .padding(.horizontal, DSSpacing.md)
                .frame(height: 28)
                .background(palette.bottomFill, in: Capsule())

                HStack(spacing: 0) {
                    ForEach(settings.visibleReaderChromeToolItems) { item in
                        previewToolGlyph(for: item, palette: palette)
                    }
                    Image(systemName: "ellipsis")
                        .font(DSFont.fixed(size: 14))
                        .foregroundStyle(palette.bottomIcon)
                        .frame(maxWidth: .infinity)
                }
                .frame(height: 28)
                .background(palette.bottomFill, in: Capsule())
            }
            .padding(DSSpacing.sm)
        }
        .background(previewTheme.backgroundColor)
        .clipShape(RoundedRectangle(cornerRadius: DSRadius.lg, style: .continuous))
        // One decorative element: VoiceOver gets the values from the rows below,
        // not from a stack of unlabelled symbols.
        .accessibilityHidden(true)
    }

    @ViewBuilder
    private func previewToolGlyph(
        for item: ReaderChromeToolItem,
        palette: ReaderChromePalette
    ) -> some View {
        Group {
            if let image = settings.readerChromeIconImage(for: item) {
                Image(uiImage: image)
                    .renderingMode(.original)
                    .resizable()
                    .scaledToFit()
                    .frame(width: 16, height: 16)
            } else if item == .settings {
                Text(verbatim: "Aa")
                    .font(DSFont.fixed(size: 13, weight: .bold, design: .serif))
                    .foregroundStyle(palette.bottomIcon)
            } else {
                // Same rule as the bar: 深色 takes the accent while night mode is on.
                let isActive = item == .nightMode && previewTheme == .night
                Image(systemName: item.systemImage(isNight: previewTheme == .night))
                    .font(DSFont.fixed(size: 14))
                    .foregroundStyle(isActive ? palette.bottomAccent : palette.bottomIcon)
            }
        }
        .frame(maxWidth: .infinity)
    }
}

/// A theme tile: a tap selects; a long press on one of the user's own themes opens
/// 重新命名／删除. Primitive, so the two cannot both fire — a long-press gesture added to
/// a plain button would still select the theme on the release that ends it.
private struct ThemeTileButtonStyle: PrimitiveButtonStyle {
    /// Nil for a theme that has nothing to rename or delete.
    let onLongPress: (() -> Void)?
    /// Its 重新命名／删除 is up, or on its way.
    var isLifted = false

    func makeBody(configuration: Configuration) -> some View {
        ThemeTileButtonBody(configuration: configuration, onLongPress: onLongPress, isLifted: isLifted)
    }
}

/// The tile under a finger grows while it is held — a long press is on its way — and
/// pops up once it lands (2026-09-29). Under Reduce Motion it stays put and the haptic
/// alone says the press landed.
private struct ThemeTileButtonBody: View {
    let configuration: PrimitiveButtonStyleConfiguration
    let onLongPress: (() -> Void)?
    let isLifted: Bool

    @State private var isPressing = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private static let pressingScale: CGFloat = 1.05
    private static let liftedScale: CGFloat = 1.12

    var body: some View {
        if let onLongPress {
            configuration.label
                .scaleEffect(scale)
                .animation(pressAnimation, value: isPressing)
                .onTapGesture { configuration.trigger() }
                .onLongPressGesture(minimumDuration: 0.5, perform: onLongPress) { pressing in
                    isPressing = pressing
                }
        } else {
            configuration.label
                .onTapGesture { configuration.trigger() }
        }
    }

    private var scale: CGFloat {
        guard !reduceMotion else { return 1 }
        if isLifted { return Self.liftedScale }
        return isPressing ? Self.pressingScale : 1
    }

    /// Growing takes most of the hold, so a quick tap barely moves the tile; letting go
    /// early settles it at once.
    private var pressAnimation: Animation? {
        guard !reduceMotion else { return nil }
        return isPressing ? DSAnimation.slow : DSAnimation.fast
    }
}

#Preview {
    NavigationStack {
        AppearanceThemeView()
            .environmentObject(SubscriptionStore.shared)
    }
}

#Preview("阅读界面") {
    NavigationStack {
        AppearanceReaderInterfaceView()
    }
}
