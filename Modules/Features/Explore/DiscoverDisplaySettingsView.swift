import SwiftUI

/// 显示设置, pushed from 发现页设置 (Phase 5 plan, decision 31): how a source's discover page
/// lays out its categories, which ones are charts, how many books each shows and how far ahead
/// it loads. 5d-1b deleted them with 探索设置; they are back under the same keys, the same for
/// every source's page for now.
struct DiscoverDisplaySettingsView: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @AppStorage(ExploreSettings.sourcePageLayoutKey)
    private var sourcePageLayout = ExploreSourcePageLayout.default
    @AppStorage(ExploreSettings.rankedKeywordsKey)
    private var rankedKeywordsRaw = ExploreSettings.encodeKeywords(ExploreSettings.defaultRankedKeywords)
    @AppStorage(ExploreSettings.chartBookCountKey)
    private var chartBookCount = ExploreSettings.defaultChartBookCount
    @AppStorage(ExploreSettings.shelfBookCountKey)
    private var shelfBookCount = ExploreSettings.defaultShelfBookCount
    @AppStorage(ExploreSettings.preloadCountKey)
    private var preloadCount = ExploreSettings.defaultPreloadCount
    @State private var newKeyword = ""

    private var rankedKeywords: [String] {
        ExploreSettings.decodeKeywords(rankedKeywordsRaw)
    }

    var body: some View {
        Form {
            layoutSection
            // How the charts and shelves fill and load matters only to the magazine layout.
            if sourcePageLayout == .magazine {
                keywordsSection
                restoreKeywordsSection
                bookCountSection
                preloadSection
            }
        }
        .animation(reduceMotion ? nil : DSAnimation.standard, value: sourcePageLayout)
        .softScrollEdges()
        .themedAppSurface(for: .explore)
        .navigationTitle(localized("显示设置"))
        .toolbarTitleDisplayMode(.inline)
    }

    private var layoutSection: some View {
        Section {
            Picker(selection: $sourcePageLayout) {
                ForEach(ExploreSourcePageLayout.allCases) { layout in
                    Label(localized(layout.titleKey), systemImage: layout.systemImage)
                        .tag(layout)
                }
            } label: {
                SettingsRowLabel(localized("布局"), systemImage: "rectangle.split.2x1")
            }
            .pickerStyle(.menu)
            .accessibilityIdentifier("discover.display.layout")
        } footer: {
            Text(localized("列表是上方一排分类、下方所选分类的书；杂志是每个分类一排书架或一栏榜单。这页的设置套用到每个来源配置的发现页。"))
                .dsSectionFooter()
        }
        .interfaceSectionSurface()
    }

    private var keywordsSection: some View {
        Section {
            ForEach(rankedKeywords, id: \.self) { keyword in
                SettingsRowLabel(keyword, systemImage: "number")
            }
            .onDelete { offsets in
                var keywords = rankedKeywords
                keywords.remove(atOffsets: offsets)
                rankedKeywordsRaw = ExploreSettings.encodeKeywords(keywords)
            }
            HStack(spacing: DSSpacing.md) {
                Image(systemName: "plus.circle")
                    .foregroundStyle(DSColor.textSecondary)
                    .accessibilityHidden(true)
                TextField(localized("新增关键词"), text: $newKeyword)
                    .submitLabel(.done)
                    .onSubmit(addKeyword)
            }
        } header: {
            Text(localized("竖排榜单关键词"))
        } footer: {
            Text(localized("标题含任一关键词的分类用竖排序号，其余用横滑封面。左滑可删除。"))
                .dsSectionFooter()
        }
        .interfaceSectionSurface()
    }

    private var restoreKeywordsSection: some View {
        Section {
            Button {
                rankedKeywordsRaw = ExploreSettings.encodeKeywords(ExploreSettings.defaultRankedKeywords)
            } label: {
                SettingsRowLabel(localized("恢复预设关键词"), systemImage: "arrow.counterclockwise", role: .action)
            }
            .disabled(rankedKeywords == ExploreSettings.defaultRankedKeywords)
        }
        .interfaceSectionSurface()
    }

    private var bookCountSection: some View {
        Section {
            Picker(selection: $chartBookCount) {
                ForEach(ExploreSettings.chartBookCountOptions, id: \.self) { count in
                    Text(count.formatted()).tag(count)
                }
            } label: {
                SettingsRowLabel(localized("竖排展示数"), systemImage: "list.number")
            }
            .pickerStyle(.menu)
            Picker(selection: $shelfBookCount) {
                ForEach(ExploreSettings.shelfBookCountOptions, id: \.self) { count in
                    Text(count == 0 ? localized("全部") : count.formatted()).tag(count)
                }
            } label: {
                SettingsRowLabel(localized("横滑展示数"), systemImage: "rectangle.split.3x1")
            }
            .pickerStyle(.menu)
        } header: {
            Text(localized("榜单展示数量"))
        }
        .interfaceSectionSurface()
    }

    private var preloadSection: some View {
        Section {
            Picker(selection: $preloadCount) {
                ForEach(ExploreSettings.preloadCountOptions, id: \.self) { count in
                    Text(count.formatted()).tag(count)
                }
            } label: {
                SettingsRowLabel(localized("预加载数量"), systemImage: "arrow.down.circle")
            }
            .pickerStyle(.menu)
        } header: {
            Text(localized("预加载"))
        } footer: {
            Text(localized("卷到某个分类时，顺便排队载入后面几个分类。数字越大越少看到载入中，但排队的来源配置请求也越多。"))
                .dsSectionFooter()
        }
        .interfaceSectionSurface()
    }

    private func addKeyword() {
        let keyword = newKeyword.trimmingCharacters(in: .whitespacesAndNewlines)
        newKeyword = ""
        guard !keyword.isEmpty,
              !rankedKeywords.contains(where: { $0.caseInsensitiveCompare(keyword) == .orderedSame })
        else { return }
        rankedKeywordsRaw = ExploreSettings.encodeKeywords(rankedKeywords + [keyword])
    }
}

#Preview {
    NavigationStack {
        DiscoverDisplaySettingsView()
    }
}
