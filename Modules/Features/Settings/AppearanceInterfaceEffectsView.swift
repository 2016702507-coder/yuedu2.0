import SwiftUI

/// 外观主题 › 界面效果 — the two knobs behind `View.floatingSurface(in:)`, with a
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
                Text(localized("效果套用于底部迷你播放器与阅读器的浮动工具列、控制栏。"))
                    .dsSectionFooter()
            }

            Section {
                Toggle(isOn: $settings.interfaceFrostedGlass) {
                    Text(localized("全局玻璃"))
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

            // 段评面板：阅读器里浮在正文之上的那层。它不跟随上面的毛玻璃开关——
            // 面板永远带一层薄雾，否则评论的字会直接压在正文上，两边都读不清。
            Section {
                reviewSheetRow
            } footer: {
                Text(localized("段评面板浮在阅读器之上。数值越低，背后的正文越清楚；拉到 0 就完全不画底色。"))
                    .dsSectionFooter()
            }
            .interfaceSectionSurface()

            // The 分组卡片 switch is gone (maintainer, 2026-11-07: 所有界面要保持一个结构).
            // It only ever moved hand-drawn cards while settings rows were glass regardless,
            // so the same screen could hold both looks; cards now follow the rows
            // unconditionally, and Reduce Transparency is the one way to get solids back.

            // The switches first and the glow after, as the reference the user handed over
            // groups them (2026-09-29).
            Section {
                Toggle(isOn: glowEnabled) {
                    Text(localized("光晕"))
                        .font(DSFont.body)
                        .foregroundStyle(DSColor.textPrimary)
                }

                // Hidden with the glow off, where neither would change anything.
                if settings.interfaceGlowIntensity > 0 {
                    glowRow
                    glowColorRow
                }
            } footer: {
                Text(localized("光晕从浮动元素的边缘向外扩散。没选颜色时跟随主题色。"))
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
                Text(localized("光晕强度"))
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
            .accessibilityLabel(localized("光晕强度"))
            .accessibilityValue(glowValueText)
        }
    }

    /// Opens on the colour the glow is drawn in right now — the theme's accent until
    /// one is picked — the same contract as 阅读界面's colour rows.
    @ViewBuilder
    private var glowColorRow: some View {
        ColorPicker(selection: glowColorBinding, supportsOpacity: false) {
            Text(localized("光晕颜色"))
                .font(DSFont.body)
                .foregroundStyle(DSColor.textPrimary)
        }
        if settings.interfaceGlowColor != nil {
            Button {
                settings.interfaceGlowColor = nil
            } label: {
                Label(localized("跟随主题色"), systemImage: "arrow.counterclockwise")
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
                Text(localized("段评面板不透明度"))
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
            .accessibilityLabel(localized("段评面板不透明度"))
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

    /// 全局玻璃总闸的说明：明确它覆盖全 App 的所有玻璃表面，以及 iOS 17 兜底用途。
    /// Reduce Transparency overrides the toggle, so say so instead of leaving the
    /// user with a switch that visibly does nothing.
    private var frostedGlassFooterKey: String {
        reduceTransparency
            ? "系统已开启「降低透明度」，全 App 的玻璃表面目前一律使用不透明底色。"
            : "全 App 的卡片、设置行、工具列、分类栏与底部导航栏统一为玻璃质感。若 iOS 17 等旧系统出现玻璃显示异常，关闭此开关即可让所有界面回退为不透明底色。透明度越低，背后的内容越不透出。"
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
    /// 光晕 something to bleed onto. Decorative as a whole — VoiceOver gets one
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

                Text(localized("浮动工具列"))
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
        .accessibilityLabel(localized("效果预览"))
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
