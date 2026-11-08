import SwiftUI

/// 官方模组 or 汇入的模组, each a page of its own on 模组.
enum RuleModuleGroup: Hashable {
    case official, imported
}

extension EnvironmentValues {
    /// 设置's one 新增模组 flow, so 模组, pushed from it, adds through it: its sheet and file
    /// importer are presented from the root, never a second pair from the pushed page (SwiftUI
    /// presents only one of two file importers on a view).
    @Entry var ruleModuleAddFlow: RuleModuleAddFlow?
}

/// 模组 (M6, maintainer 2026-10-17: 「模组要做到截图这样」): where every module comes from — 官方模组,
/// each subscribed repository, 汇入的模组. 新增模组 is its toolbar's, the one way to add a module
/// since 资源库 lost its own (maintainer, 2026-10-27): an address may hold a module or a repository.
/// 首页栏目引用, the home sections left pointing at a module no longer installed, was a row here
/// until the maintainer had it deleted the same day.
struct RuleModuleManagerView: View {
    @ObservedObject var library: RuleModuleLibrary
    @ObservedObject var repositories: RuleModuleRepositoryModel
    @ObservedObject private var availability = PublicLibraryAvailability.shared
    @Environment(\.ruleModuleAddFlow) private var addFlow
    /// Once per visit: back from a repository's page, the indexes are not read again.
    @State private var hasLoaded = false
    @State private var pendingUnsubscription: RuleModuleRepositoryModel.Repository?
    @State private var showsAddChooser = false
    @State private var addSequence = DismissalSequencedPresentation<RuleModuleAddRoute>()

    init(library: RuleModuleLibrary? = nil, repositories: RuleModuleRepositoryModel? = nil) {
        self.library = library ?? .shared
        self.repositories = repositories ?? .shared
    }

    var body: some View {
        Form {
            Section {
                NavigationLink(value: ExploreNavigationRoute.moduleGroup(.official)) {
                    RuleModuleOriginRow(title: localized("官方模组"), systemImage: "puzzlepiece.extension.fill", isVerified: true,
                                        subtitle: localized("随阅读一起提供的模组"), origin: localized("阅读"),
                                        count: AppOfficialModule.available(librariesAvailable: availability.isAvailable).count
                                            + library.official.count)
                }
                .accessibilityIdentifier("modules.official")

                ForEach(repositories.repositories) { repository in
                    NavigationLink(value: ExploreNavigationRoute.moduleRepository(repository.id)) {
                        RuleModuleOriginRow(title: repository.subscription.name, systemImage: "shippingbox",
                                            subtitle: subtitle(of: repository), origin: repository.id.absoluteString,
                                            count: repository.index?.modules.count)
                    }
                    .swipeActions {
                        Button(localized("取消订阅"), role: .destructive) { pendingUnsubscription = repository }
                    }
                    .accessibilityIdentifier("modules.repository.\(repository.id.absoluteString)")
                }

                NavigationLink(value: ExploreNavigationRoute.moduleGroup(.imported)) {
                    RuleModuleOriginRow(title: localized("汇入的模组"), systemImage: "arrow.down.circle.fill",
                                        subtitle: localized("你自己加入的模组"), origin: localized("汇入"),
                                        count: library.imported.count + library.failures.count)
                }
                .accessibilityIdentifier("modules.imported")
            } footer: {
                Text(localized("第三方模组由作者自行维护，阅读不审核其内容。加入前请确认来源可信；有问题的模组可以在「回馈与改进」回报。"))
                    .dsSectionFooter()
            }
            .interfaceSectionSurface()
        }
        .softScrollEdges()
        .navigationTitle(localized("模组"))
        .toolbarTitleDisplayMode(.inline)
        .themedAppSurface(for: .settings)
        .hidesRootTabBar()
        .toolbar {
            if addFlow != nil {
                ToolbarItem(placement: .topBarTrailing) { addControl }
            }
        }
        .confirmationDialog(pendingUnsubscription.map { String(format: localized("取消订阅「%@」？"), $0.subscription.name) } ?? "",
                            isPresented: Binding(get: { pendingUnsubscription != nil }, set: { if !$0 { pendingUnsubscription = nil } }),
                            titleVisibility: .visible, presenting: pendingUnsubscription) { repository in
            Button(localized("取消订阅"), role: .destructive) { repositories.unsubscribe(repository.id) }
            Button(localized("取消"), role: .cancel) {}
        } message: { _ in
            Text(localized("已安装的模组会留下。"))
        }
        .alert(localized("操作失败"), isPresented: Binding(get: { repositories.message != nil },
                                                          set: { if !$0 { repositories.message = nil } })) {
            Button(localized("确定"), role: .cancel) {}
        } message: {
            Text(repositories.message ?? "")
        }
        .task {
            guard !hasLoaded else { return }
            hasLoaded = true
            await library.loadIfNeeded()
            await repositories.load()
        }
    }

    private func subtitle(of repository: RuleModuleRepositoryModel.Repository) -> String {
        switch repository.state {
        case .loading: localized("读取中")
        case .loaded(let index): String(format: localized("%d 个模组"), index.modules.count)
        case .failed(let message): message
        }
    }

    /// 新增模组's three ways in. A native menu from iOS 18; on iOS 17 a chooser, since the
    /// sheet or file picker would be dropped while the menu dismisses
    /// (`Technotes/iOS17MenuModalPresentation.md`).
    @ViewBuilder
    private var addControl: some View {
        if MenuModalPresentationPolicy.requiresDismissalSequencedChooser {
            Button {
                addSequence.cancel()
                showsAddChooser = true
            } label: {
                Image(systemName: "doc.badge.plus").accessibilityHidden(true)
            }
            .accessibilityLabel(localized("新增模组"))
            .accessibilityIdentifier("modules.add")
            .sheet(isPresented: $showsAddChooser, onDismiss: {
                addSequence.consumeAfterDismissal().map { addFlow?.begin($0) }
            }) {
                AdaptiveSheetContainer(maxWidth: DSLayout.readableCompactWidth) {
                    DismissalSequencedActionChooser(
                        title: localized("新增模组"),
                        actions: RuleModuleAddRoute.allCases.map {
                            DismissalSequencedAction(route: $0, title: localized($0.titleKey), systemImage: $0.systemImage)
                        },
                        onSelect: { addSequence.select($0) })
                }
            }
        } else if let addFlow {
            Menu {
                RuleModuleAddMenuItems(flow: addFlow)
            } label: {
                Image(systemName: "doc.badge.plus").accessibilityHidden(true)
            }
            .accessibilityLabel(localized("新增模组"))
            .accessibilityIdentifier("modules.add")
        }
    }
}

/// One row of 模组: where modules come from, what it is, and how many it holds.
struct RuleModuleOriginRow: View {
    let title: String
    let systemImage: String
    var isVerified = false
    let subtitle: String
    /// 来源：…; nil for a row that is not a place modules come from.
    let origin: String?
    /// Shown trailing; nil while it is not known.
    let count: Int?

    var body: some View {
        HStack(spacing: DSSpacing.md) {
            Image(systemName: systemImage)
                .font(DSFont.title2)
                .foregroundStyle(.tint)
                .frame(width: DSLayout.minimumTapTarget)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: DSSpacing.xxs) {
                HStack(spacing: DSSpacing.xs) {
                    Text(title)
                        .font(DSFont.headline)
                        .foregroundStyle(DSColor.textPrimary)
                    if isVerified {
                        Image(systemName: "checkmark.seal.fill")
                            .foregroundStyle(DSColor.success)
                            .accessibilityHidden(true)
                    }
                }
                Text(subtitle)
                    .font(DSFont.subheadline)
                    .foregroundStyle(DSColor.textSecondary)
                if let origin {
                    Text(String(format: localized("来源：%@"), origin))
                        .font(DSFont.footnote)
                        .foregroundStyle(DSColor.textSecondary)
                        .lineLimit(1)
                        .truncationMode(.middle)
                }
            }
            Spacer(minLength: DSSpacing.sm)
            if let count {
                Text(count, format: .number)
                    .foregroundStyle(DSColor.textSecondary)
                    .accessibilityHidden(true)
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(isVerified ? [title, localized("官方")].joined(separator: ", ") : title)
        .accessibilityValue(accessibilityValue)
    }

    private var accessibilityValue: String {
        var parts = [subtitle]
        if let origin { parts.append(String(format: localized("来源：%@"), origin)) }
        if let count { parts.append(String(format: localized("%d 个"), count)) }
        return parts.joined(separator: ", ")
    }
}

#Preview("模组") {
    NavigationStack {
        RuleModuleManagerView(library: RuleModulePreviewData.officialLibrary())
            .environment(\.ruleModuleAddFlow, RuleModuleAddFlow())
    }
}
