import CloudKit
import SwiftUI

struct ICloudSyncView: View {
    @StateObject private var manager = ICloudSyncManager.shared
    @Bindable private var gs = GlobalSettings.shared

    @State private var showAlert = false
    @State private var alertTitle = ""
    @State private var alertMessage = ""
    @State private var showDeleteConfirmation = false

    private var iCloudReady: Bool { manager.accountStatus == .available }

    var body: some View {
        Form {
            accountSection
            autoSyncSection
            actionsSection
            statusSection
            deleteSection
        }
        .softScrollEdges()
        .navigationTitle(localized("iCloud 同步"))
        .toolbarTitleDisplayMode(.inline)
        .themedAppSurface(for: .settings)
        .disabled(manager.isSyncing)
        .overlay {
            if manager.isSyncing {
                syncingOverlay
            }
        }
        .alert(alertTitle, isPresented: $showAlert) {
            Button(localized("确定"), role: .cancel) {}
        } message: {
            Text(alertMessage)
        }
        .task {
            _ = await manager.refreshAccountStatus()
        }
    }

    private var accountSection: some View {
        Section {
            HStack {
                Label(manager.statusTitle(isAppSignedIn: true), systemImage: statusIcon)
                    .foregroundColor(statusColor)
                Spacer()
                if iCloudReady {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundColor(.green)
                }
            }
        } header: {
            Text(localized("帐号状态"))
                .foregroundStyle(DSColor.textSecondary)
        } footer: {
            if !iCloudReady {
                Text(localized("请确认系统设置中已登入 iCloud，且 iCloud Drive/CloudKit 可用"))
                    .dsSectionFooter()
            }
        }
        .interfaceSectionSurface()
    }

    private var autoSyncSection: some View {
        Section {
            Toggle(localized("自动同步"), isOn: $gs.iCloudAutoSync)
                .tint(DSColor.accent)
                .onChange(of: gs.iCloudAutoSync) { _, on in
                    if on, iCloudReady { Task { try? await manager.sync(reason: "toggle-on") } }
                }
        } footer: {
            Text(localized("启动与切背景时自动同步书库、来源配置、替换规则、书档、阅读设置、气泡样式与自订阅读背景。多台装置会合并，不会互相覆盖。"))
                .dsSectionFooter()
        }
        .interfaceSectionSurface()
    }

    private var actionsSection: some View {
        Section(header: Text(localized("操作")).foregroundStyle(DSColor.textSecondary)) {
            Button {
                Task { await runSync() }
            } label: {
                Label(localized("立即同步"), systemImage: "arrow.triangle.2.circlepath.icloud")
                    .foregroundColor(DSColor.accent)
            }
            .disabled(!iCloudReady)

            Button {
                Task { await refreshStatus() }
            } label: {
                Label(localized("检查 iCloud 状态"), systemImage: "checkmark.icloud")
                    .foregroundColor(DSColor.accent)
            }
        }
        .interfaceSectionSurface()
    }

    private var statusSection: some View {
        Section(header: Text(localized("状态")).foregroundStyle(DSColor.textSecondary)) {
            if let date = manager.lastSyncDate {
                HStack {
                    Text(localized("上次同步"))
                        .foregroundColor(DSColor.textSecondary)
                    Spacer()
                    Text(date, style: .relative)
                        .foregroundColor(DSColor.textPrimary)
                }
            }

            if !manager.statusMessage.isEmpty {
                Text(manager.statusMessage)
                    .foregroundColor(DSColor.textSecondary)
                    .font(DSFont.footnote)
            }
        }
        .interfaceSectionSurface()
    }

    /// Apart from the other actions, at the bottom: it cannot be undone.
    private var deleteSection: some View {
        Section {
            Button(role: .destructive) {
                showDeleteConfirmation = true
            } label: {
                Label(localized("删除 iCloud 上的资料"), systemImage: "trash")
            }
            .disabled(!iCloudReady)
        }
        .interfaceSectionSurface()
        .alert(localized("删除 iCloud 上的资料？"), isPresented: $showDeleteConfirmation) {
            Button(localized("删除"), role: .destructive) {
                Task { await runDeleteRemoteData() }
            }
            Button(localized("取消"), role: .cancel) {}
        } message: {
            Text(localized("会删除 iCloud 上的书库、来源配置、替换规则、书档、阅读设置、气泡样式与阅读背景，并关闭这台装置的自动同步。这台装置上的资料不受影响；其他装置开著自动同步时，会再上传它们的资料。"))
        }
    }

    private var statusIcon: String {
        iCloudReady ? "icloud.fill" : "exclamationmark.icloud"
    }

    private var statusColor: Color {
        switch manager.accountStatus {
        case .available:
            return DSColor.accent
        case .noAccount, .restricted, .temporarilyUnavailable:
            return .orange
        default:
            return .secondary
        }
    }

    private var syncingOverlay: some View {
        ZStack {
            Color.black.opacity(0.35)
                .ignoresSafeArea()
            VStack(spacing: 12) {
                ProgressView()
                    .progressViewStyle(.circular)
                    .scaleEffect(1.4)
                Text(manager.statusMessage)
                    .foregroundColor(.white)
                    .font(DSFont.subheadline)
            }
            .padding(24)
            .background(.ultraThinMaterial)
            .cornerRadius(16)
        }
    }

    private func refreshStatus() async {
        let status = await manager.refreshAccountStatus()
        await MainActor.run {
            alertTitle = status == .available ? localized("iCloud 可用") : localized("iCloud 无法使用")
            alertMessage = manager.statusTitle(isAppSignedIn: true)
            showAlert = true
        }
    }

    private func runSync() async {
        do {
            try await manager.sync(reason: "manual")
            await MainActor.run {
                alertTitle = localized("同步成功")
                alertMessage = localized("书库、来源配置与替换规则已更新")
                showAlert = true
            }
        } catch {
            presentError(error)
        }
    }

    private func runDeleteRemoteData() async {
        // Off first: a sync on the way to the background would upload it all again,
        // mid-deletion or right after.
        await MainActor.run { gs.iCloudAutoSync = false }
        do {
            try await manager.deleteRemoteData()
            await MainActor.run {
                alertTitle = localized("已删除 iCloud 上的同步资料")
                alertMessage = localized("这台装置的自动同步已关闭。")
                showAlert = true
            }
        } catch {
            presentError(error)
        }
    }

    private func presentError(_ error: Error) {
        Task { @MainActor in
            alertTitle = localized("操作失败")
            alertMessage = error.localizedDescription
            showAlert = true
        }
    }
}

#Preview {
    NavigationStack {
        ICloudSyncView()
    }
}
