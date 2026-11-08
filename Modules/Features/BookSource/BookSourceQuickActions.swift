import SwiftUI

// MARK: - Per-source actions (Legado's explore long-press menu)

/// The actions Legado's explore page offers on a source — 编辑、置顶、登入、搜索、
/// 刷新、删除, identical across the original, legado-E and MD3 — plus 设置源变量.
/// 探索 shows them on every source in its list; 刷新 only where there is a loaded
/// page to reload.
struct BookSourceActionMenuItems: View {
    let source: BookSource
    let onEdit: () -> Void
    let onPinToTop: () -> Void
    let onLogin: () -> Void
    let onSearch: () -> Void
    let onRefresh: (() -> Void)?
    let onSetVariable: () -> Void
    let onDelete: () -> Void

    private var hasLogin: Bool {
        !source.loginUrl.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    var body: some View {
        Button(action: onEdit) {
            Label(localized("编辑"), systemImage: "square.and.pencil")
        }
        Button(action: onPinToTop) {
            Label(localized("置顶"), systemImage: "arrow.up.to.line")
        }
        if hasLogin {
            Button(action: onLogin) {
                Label(localized("登入"), systemImage: "person.crop.circle")
            }
        }
        Button(action: onSearch) {
            Label(localized("搜索"), systemImage: "magnifyingglass")
        }
        if let onRefresh {
            Button(action: onRefresh) {
                Label(localized("刷新"), systemImage: "arrow.clockwise")
            }
        }
        Button(action: onSetVariable) {
            Label(localized("设置源变量"), systemImage: "curlybraces")
        }
        Divider()
        Button(role: .destructive, action: onDelete) {
            Label(localized("删除"), systemImage: "trash")
        }
    }
}

/// A sheet a per-source action opens.
enum BookSourceActionSheet: Identifiable {
    case edit(BookSource)
    case login(BookSource)
    case variable(BookSource)

    var id: String {
        switch self {
        case .edit(let source): "edit-\(source.id)"
        case .login(let source): "login-\(source.id)"
        case .variable(let source): "variable-\(source.id)"
        }
    }
}

extension View {
    /// Presents the sheets and the delete confirmation behind `BookSourceActionMenuItems`.
    func bookSourceActionSheets(
        sheet: Binding<BookSourceActionSheet?>,
        pendingDeletion: Binding<BookSource?>
    ) -> some View {
        self
            .sheet(item: sheet) { action in
                switch action {
                case .edit(let source):
                    AdaptiveSheetContainer(maxWidth: DSLayout.readableExpandedWidth) {
                        BookSourceEditView(source: source) { updated in
                            BookSourceStore.shared.update(updated)
                        }
                    }
                case .login(let source):
                    BookSourceLoginSheet(source: source) { sheet.wrappedValue = nil }
                case .variable(let source):
                    AdaptiveSheetContainer(maxWidth: DSLayout.readablePanelWidth) {
                        RuntimeVariableEditorView(
                            title: localized("设置源变量"),
                            comment: SourceVariableEditing.comment(source: source),
                            initialValue: SourceVariableEditing.currentValue(for: source)
                        ) { value in
                            SourceVariableEditing.save(value, for: source)
                            return nil
                        }
                    }
                }
            }
            .confirmationDialog(
                localized("删除来源配置"),
                isPresented: Binding(
                    get: { pendingDeletion.wrappedValue != nil },
                    set: { if !$0 { pendingDeletion.wrappedValue = nil } }
                ),
                titleVisibility: .visible,
                presenting: pendingDeletion.wrappedValue
            ) { source in
                Button(localized("删除"), role: .destructive) {
                    _ = BookSourceStore.shared.delete(id: source.id)
                }
                Button(localized("取消"), role: .cancel) {}
            } message: { source in
                Text(source.bookSourceName)
            }
    }
}

/// A source's login: its own login form when it defines `loginUi`, otherwise the
/// login page in a web view.
struct BookSourceLoginSheet: View {
    let source: BookSource
    let onDone: () -> Void

    var body: some View {
        if source.loginUi.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
           let webLogin = SourceWebLogin(bookSource: source) {
            SourceLoginWebView(login: webLogin, onDismiss: onDone)
        } else {
            BookSourceFormLoginView(source: source, onDismiss: onDone)
        }
    }
}
