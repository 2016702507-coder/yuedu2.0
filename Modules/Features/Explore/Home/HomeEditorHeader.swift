import SwiftUI

// The maintainer, 2026-10-27, after an Emby client's home editor: 编辑首页 opens on the
// 首页配置 it edits, in the 顶部轮播图's place. Its photo, with a camera badge, changes the
// photo (`HomePhotoPicker`, the form's own); its name pushes 首页配置's page, where
// it is switched, added and renamed; 选择轮播数据 pushes 选择内容来源 for the 轮播图 alone; and
// 关闭轮播图 hides it, keeping what it shows, or 开启轮播图 shows it again.

struct HomeEditorHeader: View {
    /// Pushes 首页配置's page.
    let openConfigurations: () -> Void
    /// Pushes 选择轮播数据.
    let chooseCarousel: () -> Void

    @ObservedObject private var pageStore = HomePageStore.shared
    @ObservedObject private var photos = HomePageStore.shared.photos

    private var configurationID: HomeConfigurationID { pageStore.selectedConfiguration }

    private var name: String {
        pageStore.configurations.first { $0.id == configurationID }?.name ?? ""
    }

    private var carousel: HomeSection? { pageStore.page?.carouselSection }

    var body: some View {
        VStack(spacing: DSSpacing.md) {
            HomePhotoPicker(photos: photos, id: configurationID) {
                HomeConfigurationPhoto(name: name, image: photos.images[configurationID], size: DSLayout.homeEditorPhotoSize)
                    .overlay(alignment: .bottomTrailing) {
                        Image(systemName: "camera.fill")
                            .font(DSFont.caption2)
                            .foregroundStyle(DSColor.textPrimary)
                            .frame(width: DSLayout.homeEditorPhotoBadgeSize, height: DSLayout.homeEditorPhotoBadgeSize)
                            .floatingSurfaceBackground(in: Circle())
                            .accessibilityHidden(true)
                    }
            }
            .accessibilityIdentifier("homeEditor.photo")

            Button(action: openConfigurations) {
                Text(name)
                    .font(DSFont.headline)
                    .foregroundStyle(DSColor.textPrimary)
                    .multilineTextAlignment(.center)
                    .frame(minHeight: DSLayout.minimumTapTarget)
            }
            .buttonStyle(.plain)
            .accessibilityHint(localized("首页配置"))
            .accessibilityIdentifier("homeEditor.configuration")

            VStack(spacing: DSSpacing.xs) {
                Button(action: chooseCarousel) {
                    Text(localized("选择轮播数据"))
                        .font(DSFont.body)
                        .foregroundStyle(DSColor.textPrimary)
                        .frame(minHeight: DSLayout.minimumTapTarget)
                }
                .buttonStyle(.plain)
                .accessibilityIdentifier("homeEditor.chooseCarousel")

                if let carousel {
                    Button {
                        pageStore.edit { $0.setCarouselShown(!carousel.isEnabled) }
                    } label: {
                        Text(localized(carousel.isEnabled ? "关闭轮播图" : "开启轮播图"))
                            .font(DSFont.body)
                            .foregroundStyle(DSColor.textSecondary)
                            .frame(minHeight: DSLayout.minimumTapTarget)
                    }
                    .buttonStyle(.plain)
                    .accessibilityIdentifier("homeEditor.toggleCarousel")
                }
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.horizontal, DSSpacing.lg)
        .padding(.vertical, DSSpacing.xl)
    }
}

#if DEBUG
#Preview("编辑首页的顶部") {
    NavigationStack {
        ScrollView {
            HomeEditorHeader(openConfigurations: {}, chooseCarousel: {})
        }
        .background(PageBackgroundView(scope: .explore).ignoresSafeArea())
    }
}

#Preview("编辑首页的顶部，辅助使用字级") {
    NavigationStack {
        ScrollView {
            HomeEditorHeader(openConfigurations: {}, chooseCarousel: {})
        }
    }
    .environment(\.dynamicTypeSize, .accessibility3)
}
#endif
