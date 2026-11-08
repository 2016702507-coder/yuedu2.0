import SwiftUI
import UIKit

/// Keep navigation/reader state mounted while a separate, opaque window covers
/// every presentation in the scene, including an already-open full-screen reader.
struct TestFlightMembershipRoot<Content: View>: View {
    @ObservedObject private var access = TestFlightAccessController.shared
    @ObservedObject private var auth = FirebaseAuthManager.shared
    @Environment(\.scenePhase) private var scenePhase
    @ViewBuilder var content: () -> Content

    var body: some View {
        content()
        .background(TestFlightGateWindow(state: access.state))
        .task(id: "\(scenePhase)-\(auth.uid ?? "guest")") {
            guard scenePhase == .active else { return }
            await access.refresh()
        }
        .onChange(of: scenePhase) { _, phase in
            if phase == .background {
                access.invalidate()
            }
        }
        .onChange(of: auth.uid) { _, _ in
            access.invalidate()
            if access.isTestFlight { NowPlayingHub.shared.stop() }
        }
        .onChange(of: access.state) { _, state in
            if state == .ineligible || state == .unavailable || state == .signInRequired {
                NowPlayingHub.shared.stop()
            }
        }
    }
}

struct TestFlightGateWindow: UIViewRepresentable {
    let state: TestFlightAccessController.State

    final class Anchor: UIView {
        var attached: ((UIWindow?) -> Void)?
        override func didMoveToWindow() {
            super.didMoveToWindow()
            attached?(window)
        }
    }

    @MainActor
    final class Coordinator {
        weak var contentWindow: UIWindow?
        private var gateWindow: UIWindow?
        private var controller: UIHostingController<TestFlightMembershipGate>?
        var state: TestFlightAccessController.State = .checking
        private var previousInteraction = true
        private var previousAccessibilityHidden = false

        func update(window: UIWindow?) {
            guard let window, let scene = window.windowScene else { return }
            if contentWindow !== window {
                dismiss()
                contentWindow = window
            }
            guard !state.allowsUse else { dismiss(); return }
            if gateWindow == nil {
                previousInteraction = window.isUserInteractionEnabled
                previousAccessibilityHidden = window.accessibilityElementsHidden
                window.endEditing(true)
                window.isUserInteractionEnabled = false
                window.accessibilityElementsHidden = true
                let hosting = UIHostingController(rootView: TestFlightMembershipGate(state: state))
                // A window made for the scene fills it and follows it as it resizes.
                let gate = UIWindow(windowScene: scene)
                gate.windowLevel = .alert
                gate.rootViewController = hosting
                gateWindow = gate
                controller = hosting
                gate.makeKeyAndVisible()
            } else {
                controller?.rootView = TestFlightMembershipGate(state: state)
            }
        }

        func dismiss() {
            guard let gateWindow else { return }
            contentWindow?.isUserInteractionEnabled = previousInteraction
            contentWindow?.accessibilityElementsHidden = previousAccessibilityHidden
            if gateWindow.isKeyWindow { contentWindow?.makeKeyAndVisible() }
            gateWindow.isHidden = true
            gateWindow.rootViewController = nil
            self.gateWindow = nil
            controller = nil
        }
    }

    func makeCoordinator() -> Coordinator { Coordinator() }

    func makeUIView(context: Context) -> Anchor {
        let view = Anchor()
        view.isUserInteractionEnabled = false
        let coordinator = context.coordinator
        view.attached = { [weak coordinator] window in coordinator?.update(window: window) }
        return view
    }

    func updateUIView(_ view: Anchor, context: Context) {
        context.coordinator.state = state
        context.coordinator.update(window: view.window)
    }

    static func dismantleUIView(_ view: Anchor, coordinator: Coordinator) {
        view.attached = nil
        coordinator.dismiss()
    }
}

struct TestFlightMembershipGate: View {
    let state: TestFlightAccessController.State
    @ObservedObject private var auth = FirebaseAuthManager.shared
    @State private var showsLogin = false
    @State private var signOutError: String?

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    if state == .checking {
                        ProgressView(localized("正在验证测试资格"))
                    } else {
                        Text(message)
                            .foregroundStyle(DSColor.textSecondary)
                    }
                    if let signOutError { Text(signOutError).foregroundStyle(DSColor.textSecondary) }
                } footer: {
                    Text(localized("测试版每次启动或回到前景都需要连线验证。本机书籍与阅读进度会保留。"))
                        .dsSectionFooter()
                }
                Section {
                    Button(localized("会员：重新验证")) {
                        Task { await TestFlightAccessController.shared.refresh() }
                    }
                    .disabled(state == .checking)
                    if auth.isAuthenticated {
                        Button(localized("切换帐号")) {
                            Task {
                                do {
                                    try await auth.signOut()
                                    showsLogin = true
                                } catch {
                                    signOutError = error.localizedDescription
                                }
                            }
                        }
                    } else {
                        Button(localized("登入")) { showsLogin = true }
                    }
                    Link(localized("开启 App Store 正式版"), destination: URL(string: "https://apps.apple.com/app/id6772972358")!)
                }
            }
            .softScrollEdges()
            .navigationTitle(localized("TestFlight 使用资格"))
            .toolbarTitleDisplayMode(.inline)
            .sheet(isPresented: $showsLogin) { LoginView() }
        }
    }

    private var message: String {
        switch state {
        case .signInRequired:
            localized("请登入持有正式版永久会员的阅读帐号，以使用测试版。")
        case .ineligible:
            localized("此帐号没有有效的正式版永久会员，已暂停测试版使用资格。若已退款，测试资格会一并取消。")
        default:
            localized("目前无法连线验证测试资格，请确认网路后重试。")
        }
    }
}

#Preview {
    TestFlightMembershipGate(state: .ineligible)
}
