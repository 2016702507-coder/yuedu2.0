import SwiftUI

struct NetworkSettingsView: View {
    @Bindable private var settings = GlobalSettings.shared
    /// 封面并发数, 探索设置's until 5d-1b; a network setting since decision 31, same key.
    @AppStorage(BookCoverLoader.downloadLimitKey) private var coverDownloadLimit = 0
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var store: BookStore

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    stepperRow(
                        title: localized("并发数"),
                        description: localized("搜索/缓存/下载/校验等网络请求并发数，建议16个"),
                        value: $settings.searchConcurrency,
                        range: 1...30
                    )
                    stepperRow(
                        title: localized("自动暂停"),
                        description: localized("每搜索到N个精确结果(或5N个模糊结果)后自动暂停(0不暂停)，防止设备发烫和流量消耗过多"),
                        value: $settings.searchAutoPauseCount,
                        range: 0...50
                    )
                    stepperRow(
                        title: localized("搜索结果快取天数"),
                        description: localized("搜索时启用快取，避免重复搜索，预设快取 5 日"),
                        value: $settings.searchCacheDays,
                        range: 0...30
                    )
                    Toggle(
                        localized("换源时载入目录"),
                        isOn: $settings.changeSourceLoadToc
                    )
                } footer: {
                    Text(localized("换源搜索时顺便抓取每个来源配置的目录，点选来源配置可立即切换；代价是搜索期间的网路请求加倍"))
                        .dsSectionFooter()
                }
                .interfaceSectionSurface()
                Section {
                    Picker(selection: $coverDownloadLimit) {
                        ForEach(ExploreSettings.coverDownloadLimitOptions, id: \.self) { limit in
                            Text(limit == 0 ? localized("不限制") : limit.formatted()).tag(limit)
                        }
                    } label: {
                        Text(localized("封面并发数"))
                    }
                    .pickerStyle(.menu)
                    .accessibilityIdentifier("network.coverDownloadLimit")
                } footer: {
                    Text(localized("同时下载的封面上限，书架和书籍详情的封面也算在内。数字越低卷动时越不容易发热，但封面出现得慢一些。"))
                        .dsSectionFooter()
                }
                .interfaceSectionSurface()
                Section {
                    Toggle(localized("自动补齐书籍资料"), isOn: $settings.autoFillBookMetadata)
                        .accessibilityIdentifier("network.autoFillBookMetadata")
                        .onChange(of: settings.autoFillBookMetadata) { store.metadataFill.conditionsChanged() }
                    // Phase 6h: which places fill, in what order (Emby's 中继资料下载器).
                    NavigationLink {
                        MetadataFillSourcesView()
                    } label: {
                        Text(localized("资料来源"))
                    }
                    .accessibilityIdentifier("network.metadataFillSources")
                } footer: {
                    Text(localized("书名、作者与 ISBN 会送到「资料来源」里勾选的地方，用来补上空白的封面、简介与分类；只在 Wi-Fi 下进行。"))
                        .dsSectionFooter()
                }
                .interfaceSectionSurface()
            }
            .softScrollEdges()
            .themedAppSurface(for: .settings)
            .navigationTitle(localized("网路设置"))
            .toolbarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button {
                        dismiss()
                    } label: {
                        Image(systemName: "xmark")
                    }
                }
            }
        }
    }

    /// A settings row with a title, the current value, a native stepper, and a
    /// description. The value is shown next to the stepper (the stepper's own
    /// label stays hidden), and the stepper keeps its native appearance so the
    /// −/+ control blends into the grouped background.
    @ViewBuilder
    private func stepperRow(
        title: String,
        description: String,
        value: Binding<Int>,
        range: ClosedRange<Int>
    ) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 12) {
                Text(title)
                    .font(DSFont.body)
                    .foregroundColor(DSColor.textPrimary)
                Spacer()
                Text("\(value.wrappedValue)")
                    .font(DSFont.bodyBold)
                    .monospacedDigit()
                    .foregroundColor(DSColor.textSecondary)
                Stepper("", value: value, in: range)
                    .labelsHidden()
                    .fixedSize()
            }
            Text(description)
                .font(DSFont.caption)
                .foregroundColor(DSColor.textSecondary)
        }
        .padding(.vertical, 4)
    }
}

#Preview {
    NetworkSettingsView()
        .environmentObject(BookStore())
}
