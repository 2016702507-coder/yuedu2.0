import SwiftUI

/// 外觀主題 › 界面效果 — the two knobs behind `View.floatingSurface(in:)`, with a
/// live sample of what they do. Every floating element in the app reads the same
/// values, so the preview here is the real modifier rather than a mock-up.
struct AppearanceInterfaceEffectsView: View {
    @Bindable private var settings = GlobalSettings.shared
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
    @Environment(\.appThemes) private var appThemes

    var body: some View {
        Form {
            Section {
                previewCard
                    .listRowInsets(EdgeInsets())
                    .listRowBackground(Color.clear)
            } footer: {
                Text(localized("效果套用於底部迷你播放器與閱讀器的浮動工具列、控制欄。"))
                    .dsSectionFooter()
            }

            Section {
                Toggle(isOn: $settings.interfaceFrostedGlass) {
                    Text(localized("毛玻璃"))
                        .font(DSFont.body)
                        .foregroundStyle(DSColor.textPrimary)
                }

                if settings.interfaceFrostedGlass {
                    transparencyRow
                }
            } footer: {
                Text(localized(frostedGlassFooterKey))
                    .dsSectionFooter()
            }
            .interfaceSectionSurface()

            // 段評面板：閱讀器裡浮在正文之上的那層。它不跟隨上面的毛玻璃開關——
            // 面板永遠帶一層薄霧，否則評論的字會直接壓在正文上，兩邊都讀不清。
            Section {
                reviewSheetRow
            } footer: {
                Text(localized("段評面板浮在閱讀器之上。數值越低，背後的正文越清楚；拉到 0 就完全不畫底色。"))
                    .dsSectionFooter()
            }
            .interfaceSectionSurface()

            // The 分組卡片 switch is gone (maintainer, 2026-11-07: 所有界面要保持一個結構).
            // It only ever moved hand-drawn cards while settings rows were glass regardless,
            // so the same screen could hold both looks; cards now follow the rows
            // unconditionally, and Reduce Transparency is the one way to get solids back.

            // The switches first and the glow after, as the reference the user handed over
            // groups them (2026-09-29).
            Section {
                Toggle(isOn: glowEnabled) {
                    Text(localized("光暈"))
                        .font(DSFont.body)
                        .foregroundStyle(DSColor.textPrimary)
                }

                // Hidden with the glow off, where neither would change anything.
                if settings.interfaceGlowIntensity > 0 {
                    glowRow
                    glowColorRow
                }
            } footer: {
                Text(localized("光暈從浮動元素的邊緣向外擴散。沒選顏色時跟隨主題色。"))
                    .dsSectionFooter()
            }
            .interfaceSectionSurface()
        }
        .softScrollEdges()
        .scrollContentBackground(.hidden)
        .navigationTitle(localized("界面效果"))
        .toolbarTitleDisplayMode(.inline)
        .themedAppSurface(for: .settings)
    }

    // MARK: - Rows

    /// On and off are the strength itself — 0 is off — so a theme that carries a glow
    /// switches it on without a second setting to keep in step.
    private var glowEnabled: Binding<Bool> {
        Binding(
            get: { settings.interfaceGlowIntensity > 0 },
            set: { isOn in
                settings.interfaceGlowIntensity = isOn ? GlobalSettings.interfaceGlowSwitchOnIntensity : 0
            }
        )
    }

    private var glowRow: some View {
        VStack(alignment: .leading, spacing: DSSpacing.sm) {
            HStack {
                Text(localized("光暈強度"))
                    .font(DSFont.body)
                    .foregroundStyle(DSColor.textPrimary)
                Spacer(minLength: DSSpacing.md)
                Text(glowValueText)
                    .font(DSFont.body.monospacedDigit())
                    .foregroundStyle(DSColor.textSecondary)
            }
            Slider(
                value: $settings.interfaceGlowIntensity,
                in: GlobalSettings.interfaceGlowSliderRange,
                step: 0.05
            )
            // A bare Slider has no name and announces a fraction of its range;
            // both modifiers reuse the text shown above. docs/design.md §7.1.
            .accessibilityLabel(localized("光暈強度"))
            .accessibilityValue(glowValueText)
        }
    }

    /// Opens on the colour the glow is drawn in right now — the theme's accent until
    /// one is picked — the same contract as 閱讀界面's colour rows.
    @ViewBuilder
    private var glowColorRow: some View {
        ColorPicker(selection: glowColorBinding, supportsOpacity: false) {
            Text(localized("光暈顏色"))
                .font(DSFont.body)
                .foregroundStyle(DSColor.textPrimary)
        }
        if settings.interfaceGlowColor != nil {
            Button {
                settings.interfaceGlowColor = nil
            } label: {
                Label(localized("跟隨主題色"), systemImage: "arrow.counterclockwise")
            }
        }
    }

    private var glowColorBinding: Binding<Color> {
        Binding(
            get: {
                settings.interfaceGlowColor.map { Color(uiColor: AppearanceThemePreset.hex($0)) }
                    ?? appThemes.glowAccent
            },
            set: { settings.interfaceGlowColor = UIColor($0).rgbHex }
        )
    }

    private var reviewSheetRow: some View {
        VStack(alignment: .leading, spacing: DSSpacing.sm) {
            HStack {
                Text(localized("段評面板不透明度"))
                    .font(DSFont.body)
                    .foregroundStyle(DSColor.textPrimary)
                Spacer(minLength: DSSpacing.md)
                Text(Self.percentText(settings.reviewSheetOpacity))
                    .font(DSFont.body.monospacedDigit())
                    .foregroundStyle(DSColor.textSecondary)
            }
            Slider(
                value: $settings.reviewSheetOpacity,
                in: GlobalSettings.reviewSheetOpacityRange,
                step: 0.05
            )
            .accessibilityLabel(localized("段評面板不透明度"))
            .accessibilityValue(Self.percentText(settings.reviewSheetOpacity))
        }
    }

    private var transparencyRow: some View {
        VStack(alignment: .leading, spacing: DSSpacing.sm) {
            HStack {
                Text(localized("透明度"))
                    .font(DSFont.body)
                    .foregroundStyle(DSColor.textPrimary)
                Spacer(minLength: DSSpacing.md)
                Text(transparencyValueText)
                    .font(DSFont.body.monospacedDigit())
                    .foregroundStyle(DSColor.textSecondary)
            }
            Slider(
                value: $settings.interfaceGlassTransparency,
                in: GlobalSettings.interfaceGlassTransparencyRange,
                step: 0.05
            )
            .accessibilityLabel(localized("透明度"))
            .accessibilityValue(transparencyValueText)
        }
    }

    /// Reduce Transparency overrides the toggle, so say so instead of leaving the
    /// user with a switch that visibly does nothing.
    private var frostedGlassFooterKey: String {
        reduceTransparency
            ? "系統已開啟「降低透明度」，浮動元素目前一律使用不透明底色。"
            : "關閉後，浮動元素改用不透明底色。透明度越低，背後的內容越不透出。"
    }

    private var glowValueText: String {
        Self.percentText(settings.interfaceGlowIntensity)
    }

    private var transparencyValueText: String {
        Self.percentText(settings.interfaceGlassTransparency)
    }

    private static func percentText(_ value: Double) -> String {
        NumberFormatter.localizedString(from: NSNumber(value: value), number: .percent)
    }

    // MARK: - Preview card

    /// Floating samples over stand-in body text, so 毛玻璃 has something to blur and
    /// 光暈 something to bleed onto. Decorative as a whole — VoiceOver gets one
    /// element naming what it is, not each sample icon.
    private var previewCard: some View {
        ZStack {
            previewBackdrop

            VStack(spacing: DSSpacing.xl) {
                HStack(spacing: DSSpacing.lg) {
                    previewCircle("textformat.size")
                    previewCircle("play.fill")
                    previewCircle("list.bullet")
                }

                Text(localized("浮動工具列"))
                    .font(DSFont.subheadline)
                    .foregroundStyle(DSColor.textPrimary)
                    .padding(.horizontal, DSSpacing.xl)
                    .padding(.vertical, DSSpacing.md)
                    .floatingSurface(in: Capsule())
            }
        }
        .frame(maxWidth: .infinity)
        .frame(height: DSLayout.interfaceEffectPreviewHeight)
        .clipShape(RoundedRectangle(cornerRadius: DSRadius.xl, style: .continuous))
        .padding(.horizontal, DSSpacing.lg)
        .padding(.vertical, DSSpacing.sm)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(localized("效果預覽"))
    }

    private func previewCircle(_ symbol: String) -> some View {
        Image(systemName: symbol)
            .font(DSFont.toolbarIconLarge)
            .foregroundStyle(DSColor.textPrimary)
            .frame(width: 48, height: 48)
            .floatingSurface(in: Circle())
    }

    private var previewBackdrop: some View {
        ZStack {
            LinearGradient(
                colors: [
                    DSColor.accent.opacity(0.32),
                    DSColor.groupedBackground
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )

            VStack(alignment: .leading, spacing: DSSpacing.sm) {
                ForEach(0..<6, id: \.self) { row in
                    RoundedRectangle(cornerRadius: DSRadius.sm, style: .continuous)
                        .fill(DSColor.textPrimary.opacity(0.16))
                        .frame(height: 6)
                        .frame(maxWidth: row.isMultiple(of: 3) ? .infinity : 220, alignment: .leading)
                }
            }
            .padding(DSSpacing.lg)
        }
    }
}

#Preview {
    NavigationStack {
        AppearanceInterfaceEffectsView()
    }
}
