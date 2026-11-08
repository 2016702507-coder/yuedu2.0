import SwiftUI

// MARK: - Pages

/// 欢迎: the icon, the name under it, and what 阅读 is in a sentence. They come in one after
/// another the first time the page shows.
struct OnboardingWelcomePage: View {
    @Binding var hasAppeared: Bool
    let focus: AccessibilityFocusState<OnboardingPage?>.Binding
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    /// VoiceOver starts the tour on the name, which an entrance would still have transparent.
    @Environment(\.accessibilityVoiceOverEnabled) private var voiceOverEnabled

    var body: some View {
        OnboardingPageScaffold {
            VStack(spacing: DSSpacing.lg) {
                AppIconImage(size: DSLayout.onboardingAppIconSize)
                    .modifier(entrance(0))
                // The app's name as 关于 gives it.
                Text(localized("阅读"))
                    .font(DSFont.onboardingAppName)
                    .foregroundStyle(DSColor.textPrimary)
                    .accessibilityAddTraits(.isHeader)
                    .accessibilityFocused(focus, equals: .welcome)
                    .modifier(entrance(1))
                Text(localized("把各处的书集中起来，在同一个首页找、同一个地方读。"))
                    .font(DSFont.title3)
                    .foregroundStyle(DSColor.textSecondary)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
                    .modifier(entrance(2))
            }
        }
        .onAppear { hasAppeared = true }
    }

    private func entrance(_ index: Int) -> OnboardingEntrance {
        OnboardingEntrance(index: index, hasAppeared: hasAppeared || voiceOverEnabled, reduceMotion: reduceMotion)
    }
}

/// 从探索找书: the home, where books from every place come together.
struct OnboardingExplorePage: View {
    let copy: OnboardingContent.Copy
    let focus: AccessibilityFocusState<OnboardingPage?>.Binding

    var body: some View {
        OnboardingPageScaffold {
            VStack(spacing: DSSpacing.xl) {
                OnboardingCoverShelf()
                OnboardingHeading(titleKey: "从探索找书", bodyKey: copy.textKey, page: .explore, focus: focus)
                OnboardingRowList(rows: copy.rows)
            }
        }
    }
}

/// 一部作品，一个页面: one work, wherever its versions are.
struct OnboardingWorksPage: View {
    let rows: [OnboardingContent.Row]
    let focus: AccessibilityFocusState<OnboardingPage?>.Binding

    var body: some View {
        OnboardingPageScaffold {
            VStack(spacing: DSSpacing.xl) {
                OnboardingWorkStack()
                OnboardingHeading(
                    titleKey: "一部作品，一个页面",
                    bodyKey: "书架、书库和来源配置里的同一部作品，会合成一笔。",
                    page: .works,
                    focus: focus
                )
                OnboardingRowList(rows: rows)
            }
        }
    }
}

/// 连接你的所有资源: what the reader adds to what 阅读 comes with.
struct OnboardingSourcesPage: View {
    let copy: OnboardingContent.Copy
    let focus: AccessibilityFocusState<OnboardingPage?>.Binding

    var body: some View {
        OnboardingPageScaffold {
            VStack(spacing: DSSpacing.xl) {
                OnboardingHeading(titleKey: "连接你的所有资源", bodyKey: copy.textKey, page: .sources, focus: focus)
                OnboardingRowList(rows: copy.rows)
            }
        }
    }
}

/// 长时间阅读也舒服: how the reader reads, and the looks they can make their own.
struct OnboardingReadingPage: View {
    let rows: [OnboardingContent.Row]
    let focus: AccessibilityFocusState<OnboardingPage?>.Binding

    var body: some View {
        OnboardingPageScaffold {
            VStack(spacing: DSSpacing.xl) {
                OnboardingPageSketches()
                OnboardingHeading(
                    titleKey: "长时间阅读也舒服",
                    bodyKey: "横排或直排、翻页或卷动，字体、字级、行距和背景都能调整。",
                    page: .reading,
                    focus: focus
                )
                OnboardingRowList(rows: rows)
            }
        }
    }
}

/// 选一个起点: each start leaves the tour for the place it names.
struct OnboardingStartPage: View {
    let starts: [OnboardingStart]
    let focus: AccessibilityFocusState<OnboardingPage?>.Binding
    let choose: (OnboardingStart) -> Void

    var body: some View {
        OnboardingPageScaffold {
            VStack(spacing: DSSpacing.xl) {
                OnboardingHeading(titleKey: "选一个起点", page: .start, focus: focus)
                VStack(spacing: DSSpacing.md) {
                    ForEach(starts) { start in
                        Button { choose(start) } label: {
                            OnboardingStartCard(start: start)
                        }
                        .buttonStyle(ExploreTileButtonStyle())
                        .accessibilityIdentifier("onboarding.start.\(start.rawValue)")
                    }
                }
            }
        }
    }
}

// MARK: - Pieces

/// A page's frame: its content in a readable column, centred in the height there is, and
/// scrolling when it is taller than that, as a page can be on a small iPhone or at the larger
/// text sizes.
private struct OnboardingPageScaffold<Content: View>: View {
    let content: Content

    init(@ViewBuilder content: () -> Content) {
        self.content = content()
    }

    var body: some View {
        GeometryReader { proxy in
            ScrollView {
                content
                    .frame(maxWidth: DSLayout.readableNarrowWidth)
                    .padding(.horizontal, DSSpacing.xl)
                    .padding(.vertical, DSSpacing.lg)
                    .frame(maxWidth: .infinity, minHeight: proxy.size.height)
            }
            .scrollBounceBehavior(.basedOnSize)
            // What runs past the page fades out over the dots and under 略过 instead of
            // being cut through a line. As deep as the padding, so nothing is faded at rest
            // or at either end of the scroll; only the mask's opacity counts.
            .mask {
                VStack(spacing: 0) {
                    LinearGradient(colors: [.clear, .black], startPoint: .top, endPoint: .bottom)
                        .frame(height: DSSpacing.lg)
                    Rectangle()
                    LinearGradient(colors: [.black, .clear], startPoint: .top, endPoint: .bottom)
                        .frame(height: DSSpacing.lg)
                }
            }
        }
    }
}

/// A page's title and the sentence under it. VoiceOver lands on the title as the page turns.
private struct OnboardingHeading: View {
    let titleKey: String
    var bodyKey: String?
    let page: OnboardingPage
    let focus: AccessibilityFocusState<OnboardingPage?>.Binding

    var body: some View {
        VStack(spacing: DSSpacing.sm) {
            Text(localized(titleKey))
                .font(DSFont.onboardingTitle)
                .foregroundStyle(DSColor.textPrimary)
                .accessibilityAddTraits(.isHeader)
                .accessibilityFocused(focus, equals: page)
            if let bodyKey {
                Text(localized(bodyKey))
                    .font(DSFont.body)
                    .foregroundStyle(DSColor.textSecondary)
            }
        }
        .multilineTextAlignment(.center)
        .fixedSize(horizontal: false, vertical: true)
    }
}

/// A page's list: each feature's name over its sentence, one VoiceOver stop each.
private struct OnboardingRowList: View {
    let rows: [OnboardingContent.Row]

    var body: some View {
        VStack(alignment: .leading, spacing: DSSpacing.md) {
            ForEach(rows) { row in
                VStack(alignment: .leading, spacing: DSSpacing.xxs) {
                    HStack(spacing: DSSpacing.sm) {
                        Text(localized(row.titleKey))
                            .font(DSFont.headline)
                            .foregroundStyle(DSColor.textPrimary)
                        // The lock settings shows on the same feature's row.
                        if row.isLocked {
                            ProLockBadge()
                        }
                    }
                    Text(localized(row.textKey))
                        .font(DSFont.subheadline)
                        .foregroundStyle(DSColor.textSecondary)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .fixedSize(horizontal: false, vertical: true)
                .accessibilityElement(children: .combine)
            }
        }
    }
}

/// A start on the last page: what it is, and where it goes.
private struct OnboardingStartCard: View {
    let start: OnboardingStart

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: DSRadius.lg, style: .continuous)
        HStack(spacing: DSSpacing.md) {
            VStack(alignment: .leading, spacing: DSSpacing.xxs) {
                Text(localized(start.titleKey))
                    .font(DSFont.headline)
                    .foregroundStyle(DSColor.textPrimary)
                Text(localized(start.detailKey))
                    .font(DSFont.subheadline)
                    .foregroundStyle(DSColor.textSecondary)
            }
            .multilineTextAlignment(.leading)
            .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 0)
            Image(systemName: "chevron.right")
                .font(DSFont.footnote.weight(.semibold))
                .foregroundStyle(DSColor.textTertiary)
                .accessibilityHidden(true)
        }
        .padding(DSSpacing.lg)
        .frame(maxWidth: .infinity, alignment: .leading)
        .contentShape(shape)
        .interfaceCardSurface(in: shape)
    }
}

/// The welcome page's pieces coming in after one another: rising a little as they fade in,
/// or only fading in under Reduce Motion.
private struct OnboardingEntrance: ViewModifier {
    let index: Int
    let hasAppeared: Bool
    let reduceMotion: Bool

    func body(content: Content) -> some View {
        content
            .opacity(hasAppeared ? 1 : 0)
            .offset(y: hasAppeared || reduceMotion ? 0 : DSLayout.onboardingEntranceOffset)
            .animation(
                DSAnimation.standard.delay(Double(index) * DSAnimation.onboardingStagger),
                value: hasAppeared
            )
    }
}

// MARK: - Previews

private struct OnboardingPagePreview<Page: View>: View {
    @AccessibilityFocusState private var focus: OnboardingPage?
    @ViewBuilder let page: (AccessibilityFocusState<OnboardingPage?>.Binding) -> Page

    var body: some View {
        page($focus)
            .background(PageBackgroundView(scope: .global).ignoresSafeArea())
    }
}

private let previewContent = OnboardingContent(
    visibleTabs: RootTabItem.tabs,
    librariesAvailable: true,
    languages: ["zh"],
    lockedFeatures: Set(PremiumFeature.allCases)
)

#Preview("欢迎") {
    @Previewable @State var hasAppeared = false
    OnboardingPagePreview { OnboardingWelcomePage(hasAppeared: $hasAppeared, focus: $0) }
}

#Preview("从探索找书") {
    OnboardingPagePreview { focus in
        if let explore = previewContent.explore {
            OnboardingExplorePage(copy: explore, focus: focus)
        }
    }
}

#Preview("一部作品，一个页面") {
    OnboardingPagePreview { OnboardingWorksPage(rows: previewContent.works, focus: $0) }
}

#Preview("连接你的所有资源") {
    OnboardingPagePreview { OnboardingSourcesPage(copy: previewContent.sources, focus: $0) }
}

#Preview("长时间阅读也舒服") {
    OnboardingPagePreview { OnboardingReadingPage(rows: previewContent.reading, focus: $0) }
}

#Preview("选一个起点") {
    OnboardingPagePreview { OnboardingStartPage(starts: previewContent.starts, focus: $0, choose: { _ in }) }
}
