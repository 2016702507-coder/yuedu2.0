import SwiftUI

// Unified library 5d-3d: 聚合设置 (Phase 5 plan, decision 21), Emby's aggregation settings
// mapped onto Yuedu's libraries. Pushed from 设置, and from 探索's ••• (decision 36).
// Laid out as Emby's 聚合资料 (search 9d): 数据来源 on top, each purpose with its n/m and its
// checklist, then 中继资料语言偏好推荐 (a menu, 2026-10-21; 偏好阅读语言 and 推荐范围 in 5d-3d)
// and 隐藏已读 (5d-3g). 书库顺序 (5d-3e) went on 2026-10-25 (maintainer: not needed).
// The home's sections (5d-3h) left in 9d: they are 编辑首页's (maintainer, 2026-10-15).

struct AggregationSettingsView: View {
    @ObservedObject private var store = AggregationSettingsStore.shared

    var body: some View {
        List {
            AggregationDataSourcesSection()
            metadataLanguageSection

            Section {
                Toggle(localized("隐藏已读"), isOn: Binding(get: { store.hidesRead }, set: { store.setHidesRead($0) }))
                    .accessibilityIdentifier("aggregation.hideRead")
            } footer: {
                Text(localized("读到最后或标记为已读完的书，任何一份都算。"))
                    .dsSectionFooter()
            }
            .interfaceSectionSurface()
        }
        .navigationTitle(localized("聚合设置"))
        .toolbarTitleDisplayMode(.inline)
        .themedAppSurface(for: .settings)
    }

    // MARK: 中继资料语言偏好推荐

    /// One language at a time, from a menu; 跟随 App 语言 until the reader picks another.
    private var metadataLanguageSection: some View {
        Section {
            Picker(localized("中继资料语言偏好推荐"), selection: Binding(
                get: { store.metadataLanguageChoice },
                set: { store.setMetadataLanguage($0) })) {
                ForEach(MetadataLanguage.choices, id: \.self) { choice in
                    Text(MetadataLanguage.name(of: choice)).tag(choice)
                }
            }
            .pickerStyle(.menu)
            .accessibilityIdentifier("aggregation.metadataLanguage")
        } footer: {
            Text(localized("这个语言的书排在前面，其次是没有标示语言的书（多数来源配置），其他语言的书排在最后。"))
                .dsSectionFooter()
        }
        .interfaceSectionSurface()
    }
}

#Preview("聚合设置") {
    NavigationStack {
        AggregationSettingsView()
    }
}
