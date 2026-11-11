import SwiftUI
import UniformTypeIdentifiers

private enum ReplaceRulePresentationRoute: Hashable {
    case add
    case importFile
}

// MARK: - List View

/// Manage user-configurable global replace rules.
/// Presented from Settings / Profile.
struct ReplaceRuleListView: View {

    @ObservedObject private var store = ReplaceRuleStore.shared
    @Bindable private var gs = GlobalSettings.shared
    @State private var showingAdd = false
    @State private var showingImportFile = false
    @State private var showLegacyActionChooser = false
    @State private var legacyActionSequence =
        DismissalSequencedPresentation<ReplaceRulePresentationRoute>()
    @State private var editingRule: ReplaceRule?
    @State private var importAlert: ReplaceRuleImportAlert?
    @State private var editMode = EditMode.inactive
    @State private var selectedRuleIDs = Set<String>()
    @State private var showBulkDeleteAlert = false
    @Environment(\.dismiss) private var dismiss
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private var isSelecting: Bool { editMode == .active }

    private var isAllSelected: Bool {
        !store.rules.isEmpty && store.rules.allSatisfy { selectedRuleIDs.contains($0.id) }
    }

    var body: some View {
        NavigationStack {
            Group {
                if store.rules.isEmpty {
                    VStack(spacing: 16) {
                        Image(systemName: "text.magnifyingglass")
                            .font(DSFont.fixed(size: 48))
                            .foregroundStyle(DSColor.textSecondary)
                        Text(localized("尚无替换规则"))
                            .foregroundStyle(DSColor.textSecondary)
                        Button(localized("新增规则")) { showingAdd = true }
                            .buttonStyle(.bordered)
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else {
                    // Native multi-select, as the bookshelf: binding the selection Set drives the
                    // system selection circles (and two-finger drag-select) in edit mode.
                    List(selection: $selectedRuleIDs) {
                        ForEach(store.rules) { rule in
                            ReplaceRuleRow(rule: rule, isSelecting: isSelecting) {
                                editingRule = rule
                            }
                            .tag(rule.id)
                            // Selecting shows the selection circles; without this `.onDelete`
                            // adds its red delete control beside each one. Swipe-to-delete
                            // outside selection is unaffected.
                            .deleteDisabled(isSelecting)
                            .interfaceSectionSurface()
                        }
                        .onDelete { offsets in
                            offsets.map { store.rules[$0].id }.forEach { store.delete(id: $0) }
                        }
                        .onMove { store.move(fromOffsets: $0, toOffset: $1) }
                    }
                    .softScrollEdges()
                    .listStyle(.plain)
                    // `themedAppSurface` below only hides the *list's* background; a `.plain`
                    // row still paints its own opaque `systemBackground` unless handed one.
                    // Same fix as 书源管理 / 语音朗读设置.
                }
            }
            .navigationTitle(localized("替换规则"))
            .toolbarTitleDisplayMode(.inline)
            .themedAppSurface(for: .settings)
            .toolbar { toolbar }
            // Deleting the last rule while selecting swaps the list for the empty state and
            // hides 编辑; leave selection so the next rule doesn't open in it.
            .onChange(of: store.rules.isEmpty) { _, isEmpty in
                if isEmpty { endSelection() }
            }
            .alert(localized("确认删除"), isPresented: $showBulkDeleteAlert) {
                Button(localized("删除"), role: .destructive) {
                    let ids = selectedRuleIDs
                    withAnimation(reduceMotion ? nil : DSAnimation.standard) {
                        store.delete(ids: ids)
                        selectedRuleIDs = []
                    }
                }
                Button(localized("取消"), role: .cancel) {}
            } message: {
                Text(String(format: localized("确定要删除 %d 条替换规则吗？"), selectedRuleIDs.count))
            }
            .sheet(
                isPresented: $showLegacyActionChooser,
                onDismiss: presentLegacyActionAfterChooserDismissal
            ) {
                AdaptiveSheetContainer(maxWidth: DSLayout.readableCompactWidth) {
                    DismissalSequencedActionChooser(
                        title: localized("新增或汇入"),
                        actions: [
                            DismissalSequencedAction(
                                route: .add,
                                title: localized("新增规则"),
                                systemImage: "plus"
                            ),
                            DismissalSequencedAction(
                                route: .importFile,
                                title: localized("汇入替换规则 JSON"),
                                systemImage: "square.and.arrow.down"
                            ),
                        ],
                        onSelect: { legacyActionSequence.select($0) }
                    )
                }
            }
            .sheet(isPresented: $showingAdd) {
                ReplaceRuleEditView(rule: nil) { store.add($0) }
            }
            .sheet(item: $editingRule) { rule in
                ReplaceRuleEditView(rule: rule) { store.update($0) }
            }
            .copiedFileImporter(
                isPresented: $showingImportFile,
                allowedContentTypes: [UTType.json, UTType.plainText]
            ) { result in
                handleImport(result)
            }
            .alert(item: $importAlert) { alert in
                Alert(
                    title: Text(localized(alert.title)),
                    message: Text(alert.message),
                    dismissButton: .default(Text(localized("完成")))
                )
            }
            // Outside `.toolbar` so the toolbar's EditButton and the List share one binding.
            .environment(\.editMode, $editMode)
        }
    }

    /// 新增或汇入, 编辑 and done; while selecting, 全选 and done, with delete in a bottom bar —
    /// the bookshelf's selection layout.
    @ToolbarContentBuilder
    private var toolbar: some ToolbarContent {
        if isSelecting {
            // Select-all kept as its own pill via the prominent + clear-tint trick so it
            // doesn't merge with the done button.
            ToolbarItem(placement: .topBarTrailing) {
                Button {
                    selectedRuleIDs = isAllSelected ? [] : Set(store.rules.map(\.id))
                } label: {
                    Text(localized(isAllSelected ? "全不选" : "全选"))
                        .font(DSFont.subheadline.weight(.medium))
                        .foregroundStyle(DSColor.textPrimary)
                }
                .buttonStyle(.borderedProminent)
                .tint(.clear)
            }
            ToolbarItem(placement: .topBarTrailing) {
                Button {
                    endSelection()
                } label: {
                    Image(systemName: "checkmark")
                        .font(DSFont.toolbarIcon)
                }
                .accessibilityLabel(localized("完成"))
            }
            ToolbarItem(placement: .bottomBar) {
                Button(role: .destructive) {
                    if !selectedRuleIDs.isEmpty { showBulkDeleteAlert = true }
                } label: {
                    Image(systemName: "trash")
                }
                .tint(.red)
                .disabled(selectedRuleIDs.isEmpty)
                .accessibilityLabel(localized("删除"))
            }
        } else {
            ToolbarItem(placement: .topBarLeading) {
                addOrImportToolbarControl
                .accessibilityLabel(localized("新增或汇入"))
            }
            if !store.rules.isEmpty {
                ToolbarItem(placement: .topBarTrailing) {
                    Button(localized("编辑")) {
                        withAnimation(reduceMotion ? nil : DSAnimation.standard) {
                            editMode = .active
                        }
                    }
                }
            }
            ToolbarItem(placement: .topBarTrailing) {
                Button {
                    dismiss()
                } label: {
                    Image(systemName: "checkmark")
                }
            }
        }
    }

    private func endSelection() {
        withAnimation(reduceMotion ? nil : DSAnimation.standard) {
            editMode = .inactive
            selectedRuleIDs = []
        }
    }

    @ViewBuilder
    private var addOrImportToolbarControl: some View {
        if MenuModalPresentationPolicy.requiresDismissalSequencedChooser {
            Button {
                legacyActionSequence.cancel()
                showLegacyActionChooser = true
            } label: {
                Image(systemName: "plus")
            }
        } else {
            Menu {
                Button {
                    showingAdd = true
                } label: {
                    Label(localized("新增规则"), systemImage: "plus")
                }

                Button {
                    showingImportFile = true
                } label: {
                    Label(
                        localized("汇入替换规则 JSON"),
                        systemImage: "square.and.arrow.down"
                    )
                }
            } label: {
                Image(systemName: "plus")
            }
        }
    }

    private func presentLegacyActionAfterChooserDismissal() {
        guard let route = legacyActionSequence.consumeAfterDismissal() else {
            return
        }
        switch route {
        case .add:
            showingAdd = true
        case .importFile:
            showingImportFile = true
        }
    }

    private func handleImport(_ result: Result<URL, Error>) {
        switch result {
        case .success(let url):
            let ok = url.startAccessingSecurityScopedResource()
            defer { if ok { url.stopAccessingSecurityScopedResource() } }

            do {
                let data = try Data(contentsOf: url)
                let count = try store.importFromLegadoData(data)
                importAlert = ReplaceRuleImportAlert(
                    title: "成功汇入",
                    message: String(format: localized("已汇入 %d 条替换规则"), count)
                )
            } catch {
                importAlert = ReplaceRuleImportAlert(
                    title: "汇入失败",
                    message: String(format: localized("替换规则汇入失败：%@"), error.localizedDescription)
                )
            }
        case .failure(let error):
            importAlert = ReplaceRuleImportAlert(
                title: "汇入失败",
                message: error.localizedDescription
            )
        }
    }
}

#Preview {
    ReplaceRuleListView()
}

private struct ReplaceRuleImportAlert: Identifiable {
    let id = UUID()
    let title: String
    let message: String
}

// MARK: - Row

private struct ReplaceRuleRow: View {

    let rule: ReplaceRule
    let isSelecting: Bool
    let onTap: () -> Void
    @ObservedObject private var store = ReplaceRuleStore.shared
    @Bindable private var gs = GlobalSettings.shared

    var body: some View {
        HStack {
            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 6) {
                    Text(rule.name.isEmpty ? localized("未命名规则") : rule.name)
                        .font(DSFont.subheadline)
                        .bold()
                        .foregroundColor(rule.enabled ? .primary : .secondary)

                    if rule.scope != "global" {
                        Text(localized("来源配置"))
                            .font(DSFont.caption2)
                            .padding(.horizontal, 4)
                            .padding(.vertical, 1)
                            .background(DSColor.highlight)
                            .foregroundColor(DSColor.accent)
                            .cornerRadius(3)
                    }
                    if rule.isRegex {
                        Text("Regex")
                            .font(DSFont.caption2)
                            .padding(.horizontal, 4)
                            .padding(.vertical, 1)
                            .background(Color.purple.opacity(0.12))
                            .foregroundColor(.purple)
                            .cornerRadius(3)
                    }
                }
                Text(rule.pattern)
                    .font(.system(.caption, design: .monospaced))
                    .foregroundStyle(DSColor.textSecondary)
                    .lineLimit(1)
                if !rule.replacement.isEmpty {
                    Text("→ \(rule.replacement)")
                        .font(.system(.caption, design: .monospaced))
                        .foregroundColor(.green)
                        .lineLimit(1)
                }
            }
            Spacer()
            Toggle("", isOn: Binding(
                get: { rule.enabled },
                set: { var r = rule; r.enabled = $0; store.update(r) }
            ))
            .labelsHidden()
        }
        .contentShape(Rectangle())
        // While selecting, a tap belongs to the List's selection, not the editor; the toggle
        // (a subview) stays live either way.
        .gesture(TapGesture().onEnded { onTap() }, including: isSelecting ? .subviews : .all)
    }
}

// MARK: - Edit View

struct ReplaceRuleEditView: View {

    @State private var rule: ReplaceRule
    let onSave: (ReplaceRule) -> Void
    @Environment(\.dismiss) private var dismiss
    @Bindable private var gs = GlobalSettings.shared

    init(rule: ReplaceRule?, onSave: @escaping (ReplaceRule) -> Void) {
        _rule = State(initialValue: rule ?? ReplaceRule(name: "", pattern: ""))
        self.onSave = onSave
    }

    var body: some View {
        NavigationStack {
            Form {
                Section(header: Text(localized("基本")).foregroundStyle(DSColor.textSecondary)) {
                    TextField(localized("规则名称"), text: $rule.name)
                    Toggle(localized("启用"), isOn: $rule.enabled)
                }
                .interfaceSectionSurface()

                Section(header: Text(localized("匹配")).foregroundStyle(DSColor.textSecondary)) {
                    Toggle(localized("正则表达式"), isOn: $rule.isRegex)
                    TextField(localized("匹配模式"), text: $rule.pattern)
                        .font(DSFont.fixed(size: 14, design: .monospaced))
                        .autocapitalization(.none)
                        .disableAutocorrection(true)
                    TextField(localized("替换为（空白=删除）"), text: $rule.replacement)
                        .font(DSFont.fixed(size: 14, design: .monospaced))
                        .autocapitalization(.none)
                }
                .interfaceSectionSurface()

                Section(header: Text(localized("作用范围")).foregroundStyle(DSColor.textSecondary)) {
                    Picker(localized("范围"), selection: $rule.scope) {
                        Text(localized("全局")).tag("global")
                        if rule.scope != "global" {
                            Text(rule.scope).tag(rule.scope)
                        }
                    }
                    .pickerStyle(.inline)
                }
                .interfaceSectionSurface()
            }
            .softScrollEdges()
            .navigationTitle(rule.name.isEmpty ? localized("新增规则") : rule.name)
            .toolbarTitleDisplayMode(.inline)
            .themedAppSurface(for: .settings)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button {
                        dismiss()
                    } label: {
                        Image(systemName: "xmark")
                    }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        onSave(rule)
                        dismiss()
                    } label: {
                        Image(systemName: "checkmark")
                    }
                    .disabled(rule.pattern.isEmpty)
                }
            }
        }
    }
}
