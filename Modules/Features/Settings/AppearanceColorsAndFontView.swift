import SwiftUI
import UIKit

/// 外观主题 › 颜色与字体: the theme's interface colours and the global font, grouped as
/// the reference the user handed over (2026-09-29) — 强调色, 文字颜色, 背景, 全局字体.
///
/// Each setting reaches one role, the one Apple's HIG gives it (redesigned 2026-09-29):
/// 强调色 what can be tapped or is selected, the three text levels iOS's label /
/// secondaryLabel / tertiaryLabel, 背景 the page and the surfaces stacked on it, the
/// font every interface text style. What the reader paints — its text, toolbars and
/// dialogue highlight — is set in 阅读设置 and 阅读界面; the theme's own values for
/// those stay its defaults there and are no longer edited here.
///
/// Light rows edit the theme picked for light, dark rows the theme picked for dark:
/// the same theme unless 单独设置深色主题 is on. A built-in theme's edits are kept
/// apart (`appearanceBuiltInThemeColors`) and 重置为默认 puts them back.
struct AppearanceColorsAndFontView: View {
    @Bindable private var settings = GlobalSettings.shared
    @ObservedObject private var subscriptionStore = SubscriptionStore.shared
    @State private var paywallFeature: PremiumFeature?

    var body: some View {
        Form {
            if subscriptionStore.hasAccess(.readerThemePacks) {
                accentSection
                textColorSection
                backgroundSection
            } else {
                Section {
                    SettingsLockedRow(title: localized("配色"), systemImage: "paintpalette") {
                        paywallFeature = .readerThemePacks
                    }
                }
                .interfaceSectionSurface()
            }
            fontSection
        }
        .softScrollEdges()
        .scrollContentBackground(.hidden)
        .navigationTitle(localized("颜色与字体"))
        .toolbarTitleDisplayMode(.inline)
        .themedAppSurface(for: .settings)
        .sheet(item: $paywallFeature) { _ in
            CardKeyUnlockView()
        }
    }

    // MARK: - Sections

    private var accentSection: some View {
        let light = colorsBinding(for: lightTheme)
        let dark = colorsBinding(for: darkTheme)
        return Section {
            ColorPicker(selection: hexColor(light, \.accentHex), supportsOpacity: false) {
                rowTitle("亮色模式")
            }
            .accessibilityLabel(modeLabel(section: "强调色", mode: "亮色模式"))
            // The dark accent is part of the dark palette: it has its own value only
            // once 自动深色配色 is off, under 背景.
            if dark.wrappedValue.dark != nil {
                ColorPicker(selection: darkHexColor(dark, \.accentHex), supportsOpacity: false) {
                    rowTitle("深色模式")
                }
                .accessibilityLabel(modeLabel(section: "强调色", mode: "深色模式"))
            }
        } header: {
            Text(localized("强调色"))
                .foregroundStyle(DSColor.textSecondary)
        } footer: {
            Text(localized("只用在能点或已选中的东西：按钮、连结、开关、滑杆、选中状态、Tab 选中图示和设置列的图示。"))
                .dsSectionFooter()
        }
        .interfaceSectionSurface()
    }

    private var textColorSection: some View {
        let light = colorsBinding(for: lightTheme)
        let dark = colorsBinding(for: darkTheme)
        return Section {
            ForEach(TextLevel.allCases) { level in
                ColorPicker(selection: textColor(light, level, dark: false), supportsOpacity: false) {
                    rowTitle(level.titleKey(dark: false))
                }
            }
            ForEach(TextLevel.allCases) { level in
                ColorPicker(selection: textColor(dark, level, dark: true), supportsOpacity: false) {
                    rowTitle(level.titleKey(dark: true))
                }
            }
        } header: {
            Text(localized("文字颜色"))
                .foregroundStyle(DSColor.textSecondary)
        } footer: {
            Text(localized("主文字用在标题和列名称，次级文字用在数值、副标和说明，弱文字用在停用和提示文字。阅读正文的颜色在阅读设置里设。"))
                .dsSectionFooter()
        }
        .interfaceSectionSurface()
    }

    /// What was 配色 until 2026-09-29. Its 文字, 工具列 and 对话高亮 only ever reached
    /// the reader (while 阅读主题 follows the theme) and went to 阅读设置 / 阅读界面 at
    /// the user's call, leaving the background. 自动深色配色 stays here and still
    /// governs the whole dark palette, the dark 强调色 row included.
    private var backgroundSection: some View {
        let light = colorsBinding(for: lightTheme)
        let dark = colorsBinding(for: darkTheme)
        return Section {
            ColorPicker(selection: hexColor(light, \.backgroundHex), supportsOpacity: false) {
                rowTitle("亮色模式")
            }
            .accessibilityLabel(modeLabel(section: "背景", mode: "亮色模式"))
            Toggle(isOn: automaticDarkBinding(dark)) {
                rowTitle("自动深色配色")
            }
            if dark.wrappedValue.dark != nil {
                ColorPicker(selection: darkHexColor(dark, \.backgroundHex), supportsOpacity: false) {
                    rowTitle("深色模式")
                }
                .accessibilityLabel(modeLabel(section: "背景", mode: "深色模式"))
            }
        } header: {
            Text(localized("背景"))
                .foregroundStyle(DSColor.textSecondary)
        } footer: {
            Text(dark.wrappedValue.dark == nil
                ? localized("页面、卡片和面板的底色；阅读主题选「跟随外观主题」时，阅读页也用它。关闭「自动深色配色」后，强调色和背景都能另外指定深色。")
                : localized("页面、卡片和面板的底色；阅读主题选「跟随外观主题」时，阅读页也用它。"))
                .dsSectionFooter()
        }
        .interfaceSectionSurface()
    }

    private var fontSection: some View {
        Section {
            NavigationLink {
                GlobalFontSettingsView()
            } label: {
                LabeledContent {
                    Text(settings.globalFontDisplayName)
                        .foregroundStyle(DSColor.textSecondary)
                } label: {
                    rowTitle("字体")
                }
            }
        } header: {
            Text(localized("全局字体"))
                .foregroundStyle(DSColor.textSecondary)
        } footer: {
            Text(localized("介面所有文字都用这个字体，并跟著系统字级缩放；阅读正文的字体在阅读设置里设。打开「粗体文字」时，没有粗体的字体会暂时改用系统字体。"))
                .dsSectionFooter()
        }
        .interfaceSectionSurface()
    }

    /// 强调色 and 背景 each have a 亮色模式 and a 深色模式 row, named as the reference the
    /// user handed over does (2026-09-29). Spoken alone, the two 亮色模式 would be the
    /// same row to VoiceOver, so each says whose it is — the way 页首页尾's colour rows do.
    private func modeLabel(section: String, mode: String) -> String {
        localized(section) + localized("，") + localized(mode)
    }

    /// A row's title in 主文字, like every settings row with a symbol
    /// (`SettingsRowLabel`) — a bare `Text` would stay in the system label colour,
    /// so this page would be the one place 主文字 does not reach.
    private func rowTitle(_ key: String) -> some View {
        Text(localized(key))
            .foregroundStyle(DSColor.textPrimary)
    }

    // MARK: - The themes edited

    private var lightTheme: AppearanceThemePreset {
        settings.appearanceBaseTheme(for: .light, isProActive: subscriptionStore.hasAccess(.readerThemePacks))
    }

    private var darkTheme: AppearanceThemePreset {
        settings.appearanceBaseTheme(for: .dark, isProActive: subscriptionStore.hasAccess(.readerThemePacks))
    }

    /// A theme's colours, read and written by id: one of the user's own in its own
    /// record, a built-in one in `appearanceBuiltInThemeColors` — seeded with the
    /// colours it ships with on the first edit.
    private func colorsBinding(for preset: AppearanceThemePreset) -> Binding<AppearanceCustomTheme> {
        let id = preset.id
        if let custom = settings.customAppearanceThemes.first(where: { $0.id == id }) {
            return Binding(
                get: { settings.customAppearanceThemes.first { $0.id == id } ?? custom },
                set: { edited in
                    guard let index = settings.customAppearanceThemes.firstIndex(where: { $0.id == id }) else { return }
                    settings.customAppearanceThemes[index] = edited
                }
            )
        }
        let shipped = preset.customCopy(name: preset.localizedName)
        return Binding(
            get: { settings.appearanceBuiltInThemeColors[id] ?? shipped },
            set: { settings.appearanceBuiltInThemeColors[id] = $0 }
        )
    }

    // MARK: - Bindings

    private func hexColor(
        _ theme: Binding<AppearanceCustomTheme>,
        _ keyPath: WritableKeyPath<AppearanceCustomTheme, UInt32>
    ) -> Binding<Color> {
        Binding(
            get: { Color(uiColor: AppearanceThemePreset.hex(theme.wrappedValue[keyPath: keyPath])) },
            set: { value in
                var copy = theme.wrappedValue
                copy[keyPath: keyPath] = UIColor(value).rgbHex ?? copy[keyPath: keyPath]
                // 默认 keeps the system's backgrounds until 背景 itself is changed.
                if keyPath == \AppearanceCustomTheme.backgroundHex {
                    copy.hasEditedBackground = true
                }
                theme.wrappedValue = copy
            }
        )
    }

    /// On the optional dark palette. Only reachable while it exists (the rows are hidden
    /// under 自动深色配色), so a missing palette reads as the derived value and writes
    /// seed one.
    private func darkHexColor(
        _ theme: Binding<AppearanceCustomTheme>,
        _ keyPath: WritableKeyPath<AppearanceCustomThemeDarkColors, UInt32>
    ) -> Binding<Color> {
        Binding(
            get: {
                let colors = theme.wrappedValue.dark ?? Self.derivedDarkColors(of: theme.wrappedValue)
                return Color(uiColor: AppearanceThemePreset.hex(colors[keyPath: keyPath]))
            },
            set: { value in
                var copy = theme.wrappedValue
                var colors = copy.dark ?? Self.derivedDarkColors(of: copy)
                colors[keyPath: keyPath] = UIColor(value).rgbHex ?? colors[keyPath: keyPath]
                copy.dark = colors
                if keyPath == \AppearanceCustomThemeDarkColors.backgroundHex {
                    copy.hasEditedDarkBackground = true
                }
                theme.wrappedValue = copy
            }
        )
    }

    /// Automatic by default (colours derived from the light palette). Switching it off
    /// seeds the dark colours with what the derivation produced, so the first thing
    /// shown is what was already on screen.
    private func automaticDarkBinding(_ theme: Binding<AppearanceCustomTheme>) -> Binding<Bool> {
        Binding(
            get: { theme.wrappedValue.dark == nil },
            set: { isAutomatic in
                var copy = theme.wrappedValue
                copy.dark = isAutomatic ? nil : Self.derivedDarkColors(of: copy)
                // A dark palette just seeded, or none: its 背景 has not been changed.
                copy.hasEditedDarkBackground = nil
                theme.wrappedValue = copy
            }
        )
    }

    /// What the automatic derivation currently produces for this theme, in storage form.
    private static func derivedDarkColors(of theme: AppearanceCustomTheme) -> AppearanceCustomThemeDarkColors {
        var withoutOverride = theme
        withoutOverride.dark = nil
        let derived = AppearanceThemePreset.preset(from: withoutOverride).palette(for: .dark)
        return AppearanceThemeDarkColors(
            background: derived.background,
            text: derived.text,
            bar: derived.bar,
            accent: derived.accent,
            dialogue: derived.dialogue
        ).stored
    }

    /// One text level. A theme's text colours count only as a full set of three, so
    /// the first edit fills the other two with what they show now.
    private func textColor(
        _ theme: Binding<AppearanceCustomTheme>,
        _ level: TextLevel,
        dark: Bool
    ) -> Binding<Color> {
        Binding(
            get: {
                let stored = theme.wrappedValue[keyPath: level.keyPath(dark: dark)]
                return Color(uiColor: AppearanceThemePreset.hex(stored ?? level.systemHex(dark: dark)))
            },
            set: { value in
                guard let hex = UIColor(value).rgbHex else { return }
                var copy = theme.wrappedValue
                for other in TextLevel.allCases where copy[keyPath: other.keyPath(dark: dark)] == nil {
                    copy[keyPath: other.keyPath(dark: dark)] = other.systemHex(dark: dark)
                }
                copy[keyPath: level.keyPath(dark: dark)] = hex
                theme.wrappedValue = copy
            }
        )
    }
}

/// The interface's three text levels.
private enum TextLevel: CaseIterable, Identifiable {
    case primary
    case secondary
    case tertiary

    var id: Self { self }

    func titleKey(dark: Bool) -> String {
        switch self {
        case .primary: return dark ? "深色主文字" : "亮色主文字"
        case .secondary: return dark ? "深色次级文字" : "亮色次级文字"
        case .tertiary: return dark ? "深色弱文字" : "亮色弱文字"
        }
    }

    func keyPath(dark: Bool) -> WritableKeyPath<AppearanceCustomTheme, UInt32?> {
        switch self {
        case .primary: return dark ? \.darkTextPrimaryHex : \.textPrimaryHex
        case .secondary: return dark ? \.darkTextSecondaryHex : \.textSecondaryHex
        case .tertiary: return dark ? \.darkTextTertiaryHex : \.textTertiaryHex
        }
    }

    /// What the interface draws this level in when the theme names none: the system
    /// label colour, flattened onto the page it sits on — white in light, black in dark.
    func systemHex(dark: Bool) -> UInt32 {
        let label: UIColor
        switch self {
        case .primary: label = .label
        case .secondary: label = .secondaryLabel
        case .tertiary: label = .tertiaryLabel
        }
        let resolved = label.resolvedColor(with: UITraitCollection(userInterfaceStyle: dark ? .dark : .light))
        var red: CGFloat = 0, green: CGFloat = 0, blue: CGFloat = 0, alpha: CGFloat = 0
        resolved.getRed(&red, green: &green, blue: &blue, alpha: &alpha)
        let page: CGFloat = dark ? 0 : 1
        func channel(_ value: CGFloat) -> UInt32 {
            UInt32(min(max((page + (value - page) * alpha) * 255, 0), 255).rounded())
        }
        return channel(red) << 16 | channel(green) << 8 | channel(blue)
    }
}

extension GlobalSettings {
    /// The global font by the name 颜色与字体 shows it under: an imported font's own
    /// name, else 系统字体.
    var globalFontDisplayName: String {
        guard let selected = resolvedGlobalFontPostScript else {
            return localized("系统字体")
        }
        return userFonts.first { $0.postScriptName == selected }?.displayName
            ?? localized("系统字体")
    }
}

#Preview {
    NavigationStack {
        AppearanceColorsAndFontView()
    }
}
