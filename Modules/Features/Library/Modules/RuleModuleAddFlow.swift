import Combine
import SwiftUI
import UniformTypeIdentifiers

/// The three ways in to 新增模组 (Phase 6e).
enum RuleModuleAddRoute: CaseIterable, Hashable {
    case address, file, clipboard

    var titleKey: String {
        switch self {
        case .address: "从网址"
        case .file: "从档案"
        case .clipboard: "从剪贴簿"
        }
    }

    var systemImage: String {
        switch self {
        case .address: "network"
        case .file: "doc.badge.plus"
        case .clipboard: "doc.on.clipboard"
        }
    }
}

/// 新增模组, from 设置's 模组 (its toolbar; 资源库's ••• and empty card until 2026-10-27). The
/// source disclaimer comes first, as for a 来源配置 (`SourceDisclaimerGate`). The file picker is
/// presented from the page itself, never from a sheet: on iOS 17 a sheet cannot present it
/// (`BookSourceImportPresentationPolicy`).
@MainActor
final class RuleModuleAddFlow: ObservableObject {
    @Published var showsSheet = false
    @Published var showsFileImporter = false
    /// The sheet's address field: shown when the module comes from an address typed in.
    @Published private(set) var asksForAddress = false
    @Published private var disclaimer = SourceDisclaimerGate<RuleModuleAddRoute>()

    let model: RuleModuleImportModel

    init(model: RuleModuleImportModel? = nil) {
        self.model = model ?? RuleModuleImportModel()
    }

    static let contentTypes: [UTType] = [.json, .plainText]

    var showsDisclaimer: Bool {
        get { disclaimer.isPresented }
        set { disclaimer.isPresented = newValue }
    }

    /// Opens a route; a menu's choice reaches here only once the menu or its chooser has gone.
    func begin(_ route: RuleModuleAddRoute, clipboard: () -> String? = { UIPasteboard.general.string }) {
        guard let route = disclaimer.pass(route) else { return }
        model.reset()
        switch route {
        case .address:
            asksForAddress = true
            showsSheet = true
        case .file:
            showsFileImporter = true
        case .clipboard:
            asksForAddress = false
            showsSheet = true
            let text = clipboard()
            Task { await model.read(clipboard: text) }
        }
    }

    func acceptDisclaimer() {
        disclaimer.accept()
    }

    func afterDisclaimerDismissal() {
        disclaimer.afterDismissal().map { begin($0) }
    }

    /// The picker has gone: the file is shown in the sheet.
    func picked(_ result: Result<URL, any Error>) {
        asksForAddress = false
        model.read(file: result)
        showsSheet = true
    }
}

extension View {
    func ruleModuleAddFlow(_ flow: RuleModuleAddFlow) -> some View {
        modifier(RuleModuleAddFlowModifier(flow: flow))
    }
}

private struct RuleModuleAddFlowModifier: ViewModifier {
    @ObservedObject var flow: RuleModuleAddFlow

    func body(content: Content) -> some View {
        content
            .sheet(isPresented: $flow.showsSheet) {
                RuleModuleImportSheet(model: flow.model, title: localized("新增模组"), asksForAddress: flow.asksForAddress)
            }
            .fileImporter(isPresented: $flow.showsFileImporter, allowedContentTypes: RuleModuleAddFlow.contentTypes) {
                flow.picked($0)
            }
            .fullScreenCover(isPresented: $flow.showsDisclaimer, onDismiss: flow.afterDisclaimerDismissal) {
                SourceDisclaimerView { flow.acceptDisclaimer() }
            }
    }
}

/// 新增模组's items inside an iOS 18 menu.
struct RuleModuleAddMenuItems: View {
    let flow: RuleModuleAddFlow

    var body: some View {
        ForEach(RuleModuleAddRoute.allCases, id: \.self) { route in
            Button {
                flow.begin(route)
            } label: {
                Label(localized(route.titleKey), systemImage: route.systemImage)
            }
        }
    }
}
