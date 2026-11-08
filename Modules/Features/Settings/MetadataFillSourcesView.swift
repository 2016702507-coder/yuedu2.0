import SwiftUI

/// 设置 → 网路设置 → 资料来源 (Phase 6h): the places 自动补齐书籍资料 asks, as Emby's
/// 中继资料下载器 (maintainer, 2026-10-15) — each checked or not, dragged into priority order.
/// Every change is saved at once, and the filler starts again with it (`MetadataFillCoordinator`).
struct MetadataFillSourcesView: View {
    @ObservedObject private var orderStore: MetadataFillOrderStore
    @ObservedObject private var modules: RuleModuleLibrary
    @State private var order: MetadataFillOrder

    init(orderStore: MetadataFillOrderStore? = nil, modules: RuleModuleLibrary? = nil) {
        let orderStore = orderStore ?? .shared
        let modules = modules ?? .shared
        self.orderStore = orderStore
        self.modules = modules
        _order = State(initialValue: orderStore.order(modules: modules.fillingModules.map(\.id)))
    }

    private var moduleIDs: [String] { modules.fillingModules.map(\.id) }

    var body: some View {
        List {
            Section {
                ForEach($order.entries) { $entry in
                    Toggle(name(of: entry.place), isOn: $entry.isEnabled)
                        .accessibilityIdentifier("metadataFill.place.\(entry.place.storageKey)")
                        // Reordering without dragging (VoiceOver, Switch Control).
                        .accessibilityAction(named: localized("上移")) { move(entry.place, by: -1) }
                        .accessibilityAction(named: localized("下移")) { move(entry.place, by: 1) }
                }
                .onMove { from, to in order.entries.move(fromOffsets: from, toOffset: to) }
            } footer: {
                Text(localized("排在前面的先补，只补还空著的栏位；取消勾选不会删掉已经补上的资料。"))
                    .dsSectionFooter()
            }
            .interfaceSectionSurface()
        }
        // Always arranging, as Emby's list is: the handles are the list's only control.
        .environment(\.editMode, .constant(.active))
        .softScrollEdges()
        .themedAppSurface(for: .settings)
        .navigationTitle(localized("资料来源"))
        .toolbarTitleDisplayMode(.inline)
        .task { await modules.loadIfNeeded() }
        .onChange(of: moduleIDs) { _, ids in order = orderStore.order(modules: ids) }
        .onChange(of: order) { _, order in
            guard order != orderStore.order(modules: moduleIDs) else { return }
            orderStore.save(order)
        }
    }

    private func name(of place: MetadataFillPlace) -> String {
        switch place {
        case .bookSources: localized("来源配置")
        case .module(let id): modules.installed(id: id)?.module.title ?? id
        }
    }

    private func move(_ place: MetadataFillPlace, by offset: Int) {
        guard let index = order.entries.firstIndex(where: { $0.place == place }) else { return }
        let target = index + offset
        guard order.entries.indices.contains(target) else { return }
        order.entries.swapAt(index, target)
    }
}

#Preview("资料来源") {
    NavigationStack {
        MetadataFillSourcesView(orderStore: MetadataFillOrderStore(defaults: UserDefaults(suiteName: "preview.metadataFill")!),
                                modules: RuleModulePreviewData.library(["每周新书", "书评精选"]))
    }
}
