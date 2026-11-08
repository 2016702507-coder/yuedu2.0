import SwiftUI

// Search 9d: 聚合设置's 数据来源, as Emby's 聚合资料 lists its data sources — one row per purpose
// with how many of its places are checked, each opening the checklist of those places.

/// The places a purpose can use, and how many it does: 「3/5」.
struct DataSourceCount: Equatable {
    var checked: Int
    var total: Int

    var text: String { "\(checked)/\(total)" }

    /// VoiceOver hears it as words, not a fraction.
    var spoken: String { String(format: localized("已勾选 %1$d 个，共 %2$d 个"), checked, total) }
}

/// 搜寻来源's places: the saved OPDS and Calibre libraries, Gutenberg and 青空文库 where offered
/// (WebDAV has no search), then the installed modules that search (Open Library
/// among them since OL3). 来源配置 are not listed: they keep their own switch and the search's
/// 来源配置 chip.
@MainActor
enum SearchSourcePlaces {
    static func places(connections: [RemoteLibraryConnection], librariesAvailable: Bool,
                       modules: [ModuleProvider]) -> [LibraryListing] {
        let libraries = LibraryListing.available(connections: connections, librariesAvailable: librariesAvailable)
            .filter { $0.key.type != .webDAV }
        let searching = modules.filter { $0.module.search != nil }.map {
            LibraryListing(key: $0.instance, name: $0.module.title, systemImage: "puzzlepiece.extension")
        }
        return libraries + searching
    }

    /// Checked of the places.
    static func count(_ places: [LibraryListing], shown: (SourceInstanceKey) -> Bool) -> DataSourceCount {
        DataSourceCount(checked: places.filter { shown($0.key) }.count, total: places.count)
    }
}

/// The 数据来源 section of 聚合设置.
struct AggregationDataSourcesSection: View {
    @ObservedObject private var store = AggregationSettingsStore.shared
    @ObservedObject private var connections = RemoteLibraryConnectionStore.shared
    @ObservedObject private var availability = PublicLibraryAvailability.shared
    @ObservedObject private var modules = RuleModuleLibrary.shared
    @ObservedObject private var fillOrder = MetadataFillOrderStore.shared

    private var searchCount: DataSourceCount {
        let places = SearchSourcePlaces.places(connections: connections.catalogs, librariesAvailable: availability.isAvailable,
                                               modules: SourceProviderRegistry.moduleProviders(in: modules))
        return SearchSourcePlaces.count(places, shown: store.isShownInSearch)
    }

    private var latestCount: DataSourceCount {
        let libraries = LibraryListing.available(connections: connections.catalogs,
                                                 librariesAvailable: availability.isAvailable)
        return DataSourceCount(checked: libraries.filter { store.isShownInLatest($0.key) }.count, total: libraries.count)
    }

    private var fillCount: DataSourceCount {
        let entries = fillOrder.order(modules: modules.fillingModules.map(\.id)).entries
        return DataSourceCount(checked: entries.filter(\.isEnabled).count, total: entries.count)
    }

    var body: some View {
        Section {
            row(localized("搜寻来源"), count: searchCount, id: "aggregation.dataSources.search") { SearchSourcesView() }
            row(localized("最新来源"), count: latestCount, id: "aggregation.dataSources.latest") { LatestSourcesView() }
            row(localized("资料来源"), count: fillCount, id: "aggregation.dataSources.metadata") { MetadataFillSourcesView() }
        } header: {
            Text(localized("数据来源"))
        }
        .interfaceSectionSurface()
        .task { await modules.loadIfNeeded() }
    }

    private func row<Destination: View>(_ title: String, count: DataSourceCount, id: String,
                                        @ViewBuilder destination: @escaping () -> Destination) -> some View {
        NavigationLink {
            destination()
        } label: {
            LabeledContent(title, value: count.text)
                .foregroundStyle(DSColor.textPrimary)
        }
        .accessibilityValue(count.spoken)
        .accessibilityIdentifier(id)
    }
}

/// 搜寻来源: the places a sent search asks, each checked or not.
struct SearchSourcesView: View {
    @ObservedObject private var store = AggregationSettingsStore.shared
    @ObservedObject private var connections = RemoteLibraryConnectionStore.shared
    @ObservedObject private var availability = PublicLibraryAvailability.shared
    @ObservedObject private var modules = RuleModuleLibrary.shared

    var body: some View {
        let places = SearchSourcePlaces.places(connections: connections.catalogs, librariesAvailable: availability.isAvailable,
                                               modules: SourceProviderRegistry.moduleProviders(in: modules))
        List {
            Section {
                ForEach(places) { place in
                    Toggle(isOn: Binding(get: { store.isShownInSearch(place.key) },
                                         set: { store.setShownInSearch($0, for: place.key) })) {
                        SettingsRowLabel(place.name, systemImage: place.systemImage)
                    }
                    .accessibilityIdentifier("aggregation.search.\(place.key.type.rawValue).\(place.key.id)")
                }
            } footer: {
                Text(localized("按下搜寻时，关键字会送到勾选的地方；Open Library 找到的书只有资料。来源配置在搜索页的「来源配置」选。"))
                    .dsSectionFooter()
            }
            .interfaceSectionSurface()
        }
        .softScrollEdges()
        .themedAppSurface(for: .settings)
        .navigationTitle(localized("搜寻来源"))
        .toolbarTitleDisplayMode(.inline)
        .task { await modules.loadIfNeeded() }
    }
}

/// 最新来源: 显示在最新 for every library, the same switches 最新's own options show.
struct LatestSourcesView: View {
    @ObservedObject private var store = AggregationSettingsStore.shared
    @ObservedObject private var connections = RemoteLibraryConnectionStore.shared
    @ObservedObject private var availability = PublicLibraryAvailability.shared

    var body: some View {
        let libraries = LibraryListing.available(connections: connections.catalogs,
                                                 librariesAvailable: availability.isAvailable)
        List {
            if libraries.isEmpty {
                ContentUnavailableView { UnavailableLabel(localized("没有书库"), systemImage: "building.columns") }
                    .listRowBackground(Color.clear)
            } else {
                Section {
                    ForEach(libraries) { library in
                        Toggle(isOn: Binding(get: { store.isShownInLatest(library.key) },
                                             set: { store.setShownInLatest($0, for: library.key) })) {
                            SettingsRowLabel(library.name, systemImage: library.systemImage)
                        }
                        .accessibilityIdentifier("aggregation.latest.\(library.key.type.rawValue).\(library.key.id)")
                    }
                } footer: {
                    Text(localized("每个首页配置的最新都用这份设置。"))
                        .dsSectionFooter()
                }
                .interfaceSectionSurface()
            }
        }
        .softScrollEdges()
        .themedAppSurface(for: .settings)
        .navigationTitle(localized("最新来源"))
        .toolbarTitleDisplayMode(.inline)
    }
}

#Preview("数据来源") {
    NavigationStack {
        List { AggregationDataSourcesSection() }
    }
}

#Preview("搜寻来源") {
    NavigationStack { SearchSourcesView() }
}

#Preview("最新来源") {
    NavigationStack { LatestSourcesView() }
}
