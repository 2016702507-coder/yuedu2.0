import SwiftUI
import Combine

struct WebDAVSyncView: View {

    @StateObject private var manager = WebDAVManager.shared
    @Bindable private var gs = GlobalSettings.shared

    @State private var showAlert = false
    @State private var alertTitle = ""
    @State private var alertMessage = ""
    @State private var showConflictAlert = false

    // MARK: - Body

    var body: some View {
        Form {
            serverSection
            actionsSection
            statusSection
        }
        .softScrollEdges()
        .navigationTitle(localized("WebDAV 同步"))
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
        .onChange(of: manager.pendingConflict != nil) { _, hasConflict in
            if hasConflict { showConflictAlert = true }
        }
        .alert(localized("侦测到备份冲突"), isPresented: $showConflictAlert) {
            Button(localized("使用云端备份"), role: .destructive) {
                Task { try? await manager.resolveConflict(keepRemote: true) }
            }
            Button(localized("保留本地资料"), role: .cancel) {
                Task { try? await manager.resolveConflict(keepRemote: false) }
            }
        } message: {
            if let c = manager.pendingConflict {
                Text(conflictMessage(c))
            }
        }
    }

    private func conflictMessage(_ c: SyncConflict) -> String {
        let fmt = DateFormatter()
        fmt.dateStyle = .short; fmt.timeStyle = .short
        let remoteDate = fmt.string(from: c.remote.backupDate)
        let localDate  = fmt.string(from: c.localLastSync)
        return String(format: localized("云端备份来自装置「%1$@」（%2$@）。本装置上次同步：%3$@。请选择要使用哪个版本。"),
                      c.remote.deviceName, remoteDate, localDate)
    }

    // MARK: - Sections

    private var serverSection: some View {
        Section(header: Text(localized("伺服器设置")).foregroundStyle(DSColor.textSecondary)) {
            HStack {
                Text(localized("网址"))
                    .foregroundColor(DSColor.textSecondary)
                TextField("https://example.com/dav", text: $manager.serverUrl)
                    .autocapitalization(.none)
                    .disableAutocorrection(true)
                    .keyboardType(.URL)
            }
            HStack {
                Text(localized("帐号"))
                    .foregroundColor(DSColor.textSecondary)
                TextField(localized("使用者名称"), text: $manager.username)
                    .autocapitalization(.none)
                    .disableAutocorrection(true)
            }
            HStack {
                Text(localized("密码"))
                    .foregroundColor(DSColor.textSecondary)
                SecureField(localized("密码"), text: $manager.password)
            }
        }
        .interfaceSectionSurface()
    }

    private var actionsSection: some View {
        Section(header: Text(localized("操作")).foregroundStyle(DSColor.textSecondary)) {
            Button {
                Task { await testConnection() }
            } label: {
                Label(localized("测试连线"), systemImage: "network")
                    .foregroundColor(DSColor.accent)
            }

            Button {
                Task { await runBackup() }
            } label: {
                Label(localized("备份到云端"), systemImage: "icloud.and.arrow.up")
                    .foregroundColor(DSColor.accent)
            }

            Button {
                Task { await runRestore() }
            } label: {
                Label(localized("从云端还原"), systemImage: "icloud.and.arrow.down")
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
            .clearGlassSurface(in: RoundedRectangle(cornerRadius: 16, style: .continuous))
            .cornerRadius(16)
        }
    }

    // MARK: - Actions

    private func testConnection() async {
        guard validateSettings() else { return }
        let ok = await manager.testConnection()
        await MainActor.run {
            alertTitle   = ok ? localized("连线成功") : localized("连线失败")
            alertMessage = ok
                ? localized("已成功连线至 WebDAV 伺服器")
                : localized("无法连线，请确认网址、帐号及密码")
            showAlert = true
        }
    }

    private func runBackup() async {
        guard validateSettings() else { return }
        do {
            try await manager.backup()
            await MainActor.run {
                alertTitle   = localized("备份成功")
                alertMessage = localized("资料已成功备份至云端")
                showAlert    = true
            }
        } catch {
            presentError(error)
        }
    }

    private func runRestore() async {
        guard validateSettings() else { return }
        do {
            try await manager.restore()
            await MainActor.run {
                alertTitle   = localized("还原成功")
                alertMessage = localized("资料已还原，书库与替换规则已即时更新")
                showAlert    = true
            }
        } catch {
            presentError(error)
        }
    }

    // MARK: - Helpers

    @discardableResult
    private func validateSettings() -> Bool {
        guard !manager.serverUrl.isEmpty else {
            alertTitle   = localized("设置不完整")
            alertMessage = localized("请填写伺服器网址")
            showAlert    = true
            return false
        }
        return true
    }

    private func presentError(_ error: Error) {
        Task { @MainActor in
            alertTitle   = localized("操作失败")
            alertMessage = error.localizedDescription
            showAlert    = true
        }
    }
}
