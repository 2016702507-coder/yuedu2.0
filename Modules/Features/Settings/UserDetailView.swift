import CloudKit
import SwiftUI
import UIKit

struct UserDetailView: View {
    @Environment(\.dismiss) var dismiss
    @Bindable var gs = GlobalSettings.shared
    @EnvironmentObject private var subscriptionStore: SubscriptionStore
    @StateObject private var firestoreSync = FirestoreSyncManager.shared
    @State private var showLogin = false
    @State private var avatarErrorMessage: String?
    @State private var showSignOutConfirmation = false
    @State private var isSigningOut = false
    @State private var showDeleteAccountConfirmation = false
    @State private var isDeletingAccount = false
    @State private var deleteAccountErrorMessage: String?
    @State private var showReadingStats = false
    @State private var showPaywall = false
    @State private var showRenameAlert = false
    @State private var draftDisplayName = ""
    @State private var showDeletePasswordAlert = false
    @State private var deletePassword = ""
    @ObservedObject private var auth = FirebaseAuthManager.shared
    @State private var isLinking = false
    @State private var linkErrorMessage: String?
    @State private var showLinkEmailAlert = false
    @State private var linkEmail = ""
    @State private var linkPassword = ""
    /// Apple or Google link waiting for a password-only account's current password.
    @State private var passwordGatedLinkProvider: String?
    @State private var linkCurrentPassword = ""
    @State private var unlinkTarget: UnlinkTarget?

    /// Identifies which sign-in method the unlink confirmation is about.
    private struct UnlinkTarget: Identifiable {
        let id: String
        let title: String
    }

    var body: some View {
        List {
            Section {
                VStack(spacing: 16) {
                    AccountAvatarView(size: 100)

                    if gs.isLoggedIn {
                        ImageSourcePickerButton(
                            accessibilityTitle: localized("修改头像"),
                            onPick: handleAvatarPick
                        ) {
                            Label(localized("修改头像"), systemImage: "photo")
                                .font(DSFont.fixed(size: 13, weight: .semibold))
                        }
                        .disabled(isSigningOut)
                    }

                    VStack(spacing: 8) {
                        HStack(spacing: 4) {
                            Image(systemName: syncStatusIcon)
                                .accessibilityHidden(true)
                            Text(gs.isLoggedIn ? firestoreSync.statusTitle : localized("登入后可同步进度"))
                                .font(DSFont.fixed(size: 12, weight: .semibold))
                        }
                        .accessibilityElement(children: .combine)
                        .padding(.horizontal, 12).padding(.vertical, 6)
                        .background(syncStatusColor.opacity(0.1))
                        .foregroundColor(syncStatusColor)
                        .clipShape(Capsule())

                        if gs.isLoggedIn, let date = firestoreSync.lastSyncDate {
                            Text(String(format: localized("上次同步 %@"), date.formatted(date: .abbreviated, time: .shortened)))
                                .font(DSFont.fixed(size: 10))
                                .foregroundStyle(DSColor.textSecondary)
                        }

                        if !gs.isLoggedIn {
                            Text(localized("登入后可跨设备同步书籍与进度"))
                                .font(DSFont.fixed(size: 10))
                                .foregroundStyle(DSColor.textSecondary)

                            Button {
                                showLogin = true
                            } label: {
                                Text(localized("登入 / 注册"))
                                    .font(DSFont.fixed(size: 15, weight: .semibold))
                                    .foregroundStyle(DSColor.textOnAccent)
                                    .frame(maxWidth: .infinity)
                                    .padding(.vertical, 12)
                                    .background(DSColor.accent)
                                    .clipShape(RoundedRectangle(cornerRadius: 12))
                            }
                            .padding(.top, 8)
                        }

                        if let avatarErrorMessage {
                            Text(avatarErrorMessage)
                                .font(DSFont.footnote)
                                .foregroundColor(.red)
                                .multilineTextAlignment(.center)
                        }
                    }
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 10)
                // Same surface as every other section here. This used to pin the card to
                // an opaque `DSColor.surface` — correct for Light/Dark, but it predates
                // `interfaceSectionSurface`, so once the other sections started following
                // 毛玻璃／分组卡片／透明度 this one stayed flat white above them.
                .interfaceSectionSurface()
            }

            Section {
                Button {
                    // The one Pro page: the offer without Pro, the member page with it
                    // (plan, subscription management, the lifetime upgrade, restore).
                    showPaywall = true
                } label: {
                    HStack(spacing: DSSpacing.md) {
                        // The app's own icon, as on the Pro page it opens: Pro is this app.
                        AppIconImage(size: DSLayout.settingsRowIconSize)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(localized("阅读Pro"))
                                .foregroundStyle(DSColor.textPrimary)
                            Text(proRowSubtitle)
                                .font(DSFont.caption)
                                .foregroundStyle(DSColor.textSecondary)
                        }
                        Spacer(minLength: 0)
                        if subscriptionStore.isProActive {
                            Text(localized("已启用"))
                                .font(DSFont.caption.weight(.semibold))
                                .foregroundStyle(DSColor.success)
                        }
                        Image(systemName: "chevron.right")
                            .font(DSFont.fixed(size: 13, weight: .semibold))
                            .foregroundStyle(DSColor.textSecondary.opacity(0.5))
                            .accessibilityHidden(true)
                    }
                }
                .buttonStyle(.plain)
                .accessibilityIdentifier("settings_pro_row")
            }
            .interfaceSectionSurface()

            Section(header: Text(localized("阅读工具")).foregroundStyle(DSColor.textSecondary)) {
                Button {
                    showReadingStats = true
                } label: {
                    HStack {
                        SettingsRowLabel(localized("阅读统计"), systemImage: "chart.bar.fill")
                        Spacer()
                        Image(systemName: "chevron.right")
                            .font(DSFont.fixed(size: 13, weight: .semibold))
                            .foregroundStyle(DSColor.textTertiary)
                    }
                }
                .buttonStyle(.plain)
            }
            .interfaceSectionSurface()

            if gs.isLoggedIn {
                Section(header: Text(localized("帐号资讯")).foregroundStyle(DSColor.textSecondary)) {
                    Button {
                        draftDisplayName = gs.accountDisplayName
                        showRenameAlert = true
                    } label: {
                        HStack {
                            Text(localized("用户名"))
                                .foregroundStyle(DSColor.textPrimary)
                            Spacer()
                            Text(gs.accountDisplayName.isEmpty ? localized("未设置") : gs.accountDisplayName)
                                .foregroundStyle(DSColor.textSecondary)
                                .lineLimit(1)
                            Image(systemName: "chevron.right")
                                .font(DSFont.fixed(size: 13, weight: .semibold))
                                .foregroundStyle(DSColor.textSecondary.opacity(0.5))
                        }
                    }
                    .disabled(isSigningOut || isDeletingAccount)

                    if !gs.accountEmail.isEmpty {
                        HStack {
                            Text(localized("帐号"))
                                .foregroundStyle(DSColor.textPrimary)
                            Spacer()
                            Text(gs.accountEmail)
                                .foregroundStyle(DSColor.textSecondary)
                                .lineLimit(1)
                                .truncationMode(.middle)
                        }
                    }
                }
                .interfaceSectionSurface()

                Section {
                    linkRow(title: "Google", providerID: "google.com")
                    linkRow(title: "Apple", providerID: "apple.com")
                    linkRow(title: localized("电子邮件"), providerID: "password")

                    if let linkErrorMessage {
                        VStack(alignment: .leading, spacing: DSSpacing.sm) {
                            Text(linkErrorMessage)
                                .font(DSFont.footnote)
                                .foregroundColor(.red)

                            if auth.hasPendingSignInCredential {
                                Button(localized("改用该帐号登入")) {
                                    switchToPendingAccount()
                                }
                                .font(DSFont.fixed(size: 15, weight: .semibold))
                                .disabled(isLinking)
                            }
                        }
                    }
                } header: {
                    Text(localized("连结登入方式"))
                        .foregroundStyle(DSColor.textSecondary)
                } footer: {
                    Text(localized("连结后可用任一方式登入同一个帐号，并且至少要保留一种。"))
                        .dsSectionFooter()
                }
                .interfaceSectionSurface()

                Section {
                    Button(role: .destructive) {
                        showSignOutConfirmation = true
                    } label: {
                        HStack {
                            Text(localized("退出当前帐号"))
                            Spacer()
                            if isSigningOut {
                                ProgressView()
                            }
                        }
                    }
                    .disabled(isSigningOut)
                    .alert(
                        localized("登出帐号"),
                        isPresented: $showSignOutConfirmation
                    ) {
                        Button(localized("登出"), role: .destructive) {
                            performSignOut(revokeGoogleAccess: true)
                        }

                        Button(localized("取消"), role: .cancel) {}
                    } message: {
                        Text(localized("登出后此装置会停止使用目前帐号同步。"))
                    }
                }
                .interfaceSectionSurface()

                Section {
                    Button(role: .destructive) {
                        showDeleteAccountConfirmation = true
                    } label: {
                        HStack {
                            Text(localized("删除帐号"))
                            Spacer()
                            if isDeletingAccount {
                                ProgressView()
                            }
                        }
                    }
                    .disabled(isDeletingAccount || isSigningOut)
                    .alert(
                        localized("删除帐号"),
                        isPresented: $showDeleteAccountConfirmation
                    ) {
                        Button(localized("永久删除帐号"), role: .destructive) {
                            performAccountDeletion()
                        }

                        Button(localized("取消"), role: .cancel) {}
                    } message: {
                        Text(localized("删除帐号将登出此装置，并永久删除已同步的书库、来源配置、替换规则、RSS 与头像资料。此操作无法复原。"))
                    }
                } footer: {
                    VStack(alignment: .leading, spacing: DSSpacing.xs) {
                        Text(localized("无法复原。本机的内容档不会被删除。"))
                            .dsSectionFooter()
                        if let deleteAccountErrorMessage {
                            Text(deleteAccountErrorMessage)
                                .dsSectionFooter(color: DSColor.destructive)
                        }
                    }
                }
                .interfaceSectionSurface()
            }
        }
        .softScrollEdges()
        .listStyle(.insetGrouped)
        .themedAppSurface(for: .settings)
        .navigationTitle(localized("个人资料"))
        .toolbarTitleDisplayMode(.inline)
        .hidesRootTabBar()
        .sheet(isPresented: $showReadingStats) {
            AdaptiveSheetContainer(maxWidth: DSLayout.readableListWidth) {
                ReadingStatsView()
            }
        }
        .sheet(isPresented: $showPaywall) {
            CardKeyUnlockView()
        }
        .fullScreenCover(isPresented: $showLogin) {
            LoginView {
                showLogin = false
            }
        }
        .alert(localized("修改用户名"), isPresented: $showRenameAlert) {
            TextField(localized("用户名"), text: $draftDisplayName)
            Button(localized("储存")) {
                gs.updateAccountDisplayName(draftDisplayName)
            }
            Button(localized("取消"), role: .cancel) {}
        } message: {
            Text(localized("名称会先储存在此装置，并同步至帐号；同步失败时仍会保留。"))
        }
        .alert(localized("确认删除帐号"), isPresented: $showDeletePasswordAlert) {
            SecureField(localized("请输入密码"), text: $deletePassword)
                .textInputAutocapitalization(.never)
            Button(localized("永久删除帐号"), role: .destructive) {
                let password = deletePassword
                deletePassword = ""
                runAccountDeletion(emailPassword: password)
            }
            Button(localized("取消"), role: .cancel) { deletePassword = "" }
        } message: {
            Text(localized("请输入密码以确认删除帐号"))
        }
        .alert(
            localized("解除连结"),
            isPresented: Binding(
                get: { unlinkTarget != nil },
                set: { if !$0 { unlinkTarget = nil } }
            ),
            presenting: unlinkTarget
        ) { target in
            Button(localized("解除连结"), role: .destructive) {
                performUnlink(target.id)
                unlinkTarget = nil
            }
            Button(localized("取消"), role: .cancel) { unlinkTarget = nil }
        } message: { target in
            Text("\(target.title)\n\(localized("解除后就不能再用这个方式登入此帐号，帐号本身与已同步的资料不受影响。"))")
        }
        .alert(
            localized("输入目前的密码"),
            isPresented: Binding(
                get: { passwordGatedLinkProvider != nil },
                set: { if !$0 { passwordGatedLinkProvider = nil } }
            ),
            presenting: passwordGatedLinkProvider
        ) { providerID in
            SecureField(localized("请输入密码"), text: $linkCurrentPassword)
                .textInputAutocapitalization(.never)
            Button(localized("继续")) {
                let password = linkCurrentPassword
                linkCurrentPassword = ""
                passwordGatedLinkProvider = nil
                performFederatedLink(providerID, currentPassword: password)
            }
            Button(localized("取消"), role: .cancel) {
                linkCurrentPassword = ""
                passwordGatedLinkProvider = nil
            }
        } message: { _ in
            Text(localized("连结新的登入方式前，请先输入这个帐号的密码。"))
        }
        .alert(localized("连结电子邮件"), isPresented: $showLinkEmailAlert) {
            TextField(localized("请输入您的 Email"), text: $linkEmail)
                .keyboardType(.emailAddress)
                .textInputAutocapitalization(.never)
            SecureField(localized("请输入密码"), text: $linkPassword)
                .textInputAutocapitalization(.never)
            Button(localized("连结")) {
                let email = linkEmail
                let password = linkPassword
                linkEmail = ""
                linkPassword = ""
                performLink { try await auth.linkEmail(email: email, password: password) }
            }
            Button(localized("取消"), role: .cancel) {
                linkEmail = ""
                linkPassword = ""
            }
        } message: {
            Text(localized("连结后可用任一方式登入同一个帐号"))
        }
    }

    @ViewBuilder
    private func linkRow(title: String, providerID: String) -> some View {
        HStack(spacing: DSSpacing.md) {
            Text(title)
                .foregroundStyle(DSColor.textPrimary)
            Spacer(minLength: 0)
            if auth.linkedProviderIDs.contains(providerID) {
                Label(localized("已连结"), systemImage: "checkmark.circle.fill")
                    .font(DSFont.fixed(size: 13, weight: .semibold))
                    .foregroundColor(.green)

                if auth.canUnlinkProvider {
                    Button(localized("解除连结"), role: .destructive) {
                        unlinkTarget = UnlinkTarget(id: providerID, title: title)
                    }
                    .font(DSFont.fixed(size: 15, weight: .semibold))
                    .disabled(isLinking)
                    .accessibilityLabel(String(format: localized("%@ 解除连结"), title))
                }
            } else if isLinking {
                ProgressView()
            } else {
                Button(localized("连结")) { startLink(providerID) }
                    .font(DSFont.fixed(size: 15, weight: .semibold))
                    .accessibilityLabel(String(format: localized("%@ 连结"), title))
            }
        }
        .buttonStyle(.borderless)
    }

    private func startLink(_ providerID: String) {
        if providerID == "password" {
            linkErrorMessage = nil
            auth.clearPendingSignInCredential()
            showLinkEmailAlert = true
            return
        }
        if auth.linkingRequiresPassword {
            linkErrorMessage = nil
            passwordGatedLinkProvider = providerID
            return
        }
        performFederatedLink(providerID, currentPassword: nil)
    }

    private func performFederatedLink(_ providerID: String, currentPassword: String?) {
        performLink {
            if providerID == "google.com" {
                try await auth.linkGoogle(currentPassword: currentPassword)
            } else {
                try await auth.linkApple(currentPassword: currentPassword)
            }
        }
    }

    private func performLink(_ operation: @escaping () async throws -> Void) {
        isLinking = true
        linkErrorMessage = nil
        auth.clearPendingSignInCredential()
        Task {
            do {
                try await operation()
            } catch {
                linkErrorMessage = AuthErrorReporter.describe(error)
            }
            isLinking = false
        }
    }

    private func performUnlink(_ providerID: String) {
        isLinking = true
        linkErrorMessage = nil
        Task {
            do {
                try await auth.unlink(providerID: providerID)
            } catch {
                linkErrorMessage = AuthErrorReporter.describe(error)
            }
            isLinking = false
        }
    }

    /// Escape hatch for "this identity belongs to another account": sign into that
    /// account rather than leaving the user with no way forward.
    private func switchToPendingAccount() {
        isLinking = true
        linkErrorMessage = nil
        Task {
            do {
                try await auth.signInWithPendingCredential()
            } catch {
                linkErrorMessage = AuthErrorReporter.describe(error)
            }
            isLinking = false
        }
    }

    /// Under 阅读Pro: what Pro unlocks, led by AI — or the plan they hold. Lifetime is not
    /// a subscription, and Pro from the Yuedu account or the iCloud mirror names no plan
    /// on this Apple Account, so each gets its own line.
    private var proRowSubtitle: String {
        guard subscriptionStore.isProActive else { return localized("解锁 AI 阅读助手与高级个人化") }
        switch subscriptionStore.ownedPlan {
        case .lifetime?: return localized("永久会员，感谢支持")
        case .monthly?: return localized("已订阅，感谢支持")
        case nil: return localized("感谢你的支持")
        }
    }

    private var syncStatusIcon: String {
        guard gs.isLoggedIn else { return "cloud.slash" }
        if case .failed = firestoreSync.state {
            return "exclamationmark.icloud"
        }
        return "cloud.fill"
    }

    private var syncStatusColor: Color {
        guard gs.isLoggedIn else { return DSColor.accent }
        switch firestoreSync.state {
        case .synced, .syncing:
            return DSColor.accent
        case .failed:
            return .orange
        default:
            return .secondary
        }
    }

    private func performSignOut(revokeGoogleAccess: Bool) {
        isSigningOut = true
        Task {
            do {
                try await FirebaseAuthManager.shared.signOut(revokeGoogleAccess: revokeGoogleAccess)
                dismiss()
            } catch {
                avatarErrorMessage = error.localizedDescription
            }
            isSigningOut = false
        }
    }

    private func performAccountDeletion() {
        // Email accounts need the password to re-authenticate before deletion;
        // Google/Apple re-authenticate interactively inside deleteAccount().
        if FirebaseAuthManager.shared.deletionRequiresPassword {
            showDeletePasswordAlert = true
        } else {
            runAccountDeletion(emailPassword: nil)
        }
    }

    private func runAccountDeletion(emailPassword: String?) {
        isDeletingAccount = true
        deleteAccountErrorMessage = nil

        Task {
            do {
                try await FirebaseAuthManager.shared.deleteAccount(emailPassword: emailPassword)
                dismiss()
            } catch {
                deleteAccountErrorMessage = error.localizedDescription
            }
            isDeletingAccount = false
        }
    }

    /// Both sources end up as raw bytes: the avatar is re-encoded to a 512pt
    /// JPEG before it is stored or uploaded, so the source container never
    /// reaches the profile.
    private func handleAvatarPick(_ result: Result<PickedImageSource, PickedImageError>) {
        switch result {
        case .success(.data(let data)):
            applyAvatar(data: data)
        case .success(.file(let url)):
            guard let data = try? Data(contentsOf: url) else {
                avatarErrorMessage = localized("无法读取头像图片")
                return
            }
            applyAvatar(data: data)
        case .failure:
            avatarErrorMessage = localized("无法读取头像图片")
        }
    }

    private func applyAvatar(data: Data) {
        guard let avatarData = normalizedAvatarData(from: data) else {
            avatarErrorMessage = localized("无法读取头像图片")
            return
        }
        avatarErrorMessage = nil
        gs.updateAccountAvatar(data: avatarData)
        Task { @MainActor in
            do {
                _ = try await firestoreSync.uploadAvatar(data: avatarData)
            } catch {
                avatarErrorMessage = error.localizedDescription
            }
        }
    }

    private func normalizedAvatarData(from data: Data) -> Data? {
        guard let image = UIImage(data: data) else { return nil }
        let maxSide: CGFloat = 512
        let longestSide = max(image.size.width, image.size.height)
        let scale = min(1, maxSide / max(longestSide, 1))
        let targetSize = CGSize(width: image.size.width * scale, height: image.size.height * scale)

        let renderer = UIGraphicsImageRenderer(size: targetSize)
        let resized = renderer.image { _ in
            image.draw(in: CGRect(origin: .zero, size: targetSize))
        }
        return resized.jpegData(compressionQuality: 0.85)
    }
}

struct AccountAvatarView: View {
    @Bindable private var gs = GlobalSettings.shared
    @ObservedObject private var auth = FirebaseAuthManager.shared
    let size: CGFloat

    var body: some View {
        AccountAvatarImageView(
            size: size,
            avatarData: gs.accountAvatarData,
            photoURLString: gs.accountPhotoURL,
            isLoggedIn: gs.isLoggedIn,
            gatewayRouteActive: auth.activeRoute == .gateway
        )
    }
}

#Preview {
    NavigationStack {
        UserDetailView()
            .environmentObject(SubscriptionStore.shared)
    }
}
