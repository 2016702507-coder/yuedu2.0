import SwiftUI

/// 会员卡密解锁面板。
///
/// 侧载版本的商店页没有可用的商品（没有真实 App 内购买），点「开通 Pro」只会停在
/// 失败或空白页，所以凡是需要会员的入口都改成这个面板：输入统一卡密即可解锁，
/// 解锁状态由 `CardKeyMembership` 存在本机。
struct CardKeyUnlockView: View {
    @Environment(\.dismiss) private var dismiss
    @ObservedObject private var membership = CardKeyMembership.shared
    @State private var input = ""
    @State private var wrongKey = false
    @State private var isSubmitting = false
    @FocusState private var isFocused: Bool

    var body: some View {
        VStack(spacing: 16) {
            Image(systemName: "crown.fill")
                .font(.system(size: 34, weight: .semibold))
                .foregroundStyle(.yellow)
                .padding(.top, 4)

            Text(localized("尊享会员"))
                .font(.title3.weight(.semibold))

            Text(localized("支援月卡（30 天）与永久卡，一个兑换码限一台装置"))
                .font(.footnote)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)

            if membership.isUnlocked {
                Text(statusText)
                    .font(.footnote.weight(.medium))
                    .foregroundStyle(.secondary)
            }

            TextField(localized("请输入兑换码"), text: $input)
                .textFieldStyle(.roundedBorder)
                // 卡密可能是大小写混排（兜底那条就是），全键盘 + 关掉自动大写和纠错，
                // 否则 iOS 会把首字母改成大写、或者把 I 纠成 l，输对了也校验不过。
                .keyboardType(.asciiCapable)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
                .focused($isFocused)
                .submitLabel(.done)
                .onSubmit(activate)

            if wrongKey {
                Text(localized(failureText))
                    .font(.footnote)
                    .foregroundStyle(.red)
                    .multilineTextAlignment(.center)
            }

            Button(action: activate) {
                if isSubmitting {
                    ProgressView()
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 6)
                } else {
                    Text(localized("激活"))
                        .font(.body.weight(.semibold))
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 6)
                }
            }
            .buttonStyle(.borderedProminent)
            .disabled(isSubmitting || input.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)

            Button(localized("取消"), role: .cancel) { dismiss() }
                .font(.footnote)

            Spacer(minLength: 0)
        }
        .padding(24)
        .presentationDetents([.height(430)])
        .presentationDragIndicator(.visible)
        .onAppear {
            isFocused = true
            // 打开面板就复验一次：若服务端已把这条卡密吊销，这里立刻收回会员，
            // 不用等 App 下次冷启动。
            Task { await membership.refreshIfNeeded(force: true) }
        }
        .onChange(of: membership.isUnlocked) { _, unlocked in
            if unlocked { dismiss() }
        }
    }

    /// 目前档位一行；未激活时不显示。
    private var statusText: String {
        switch membership.plan {
        case .forever:
            return localized("目前：永久会员")
        case .month:
            guard let days = membership.remainingDays, days > 0 else {
                return localized("目前：月卡会员")
            }
            return String(format: localized("目前：月卡会员 · 剩余 %d 天"), days)
        case .none:
            return ""
        }
    }

    /// 失败文案按原因区分：卡密对但设备不符时，提示「卡密错误」会让人一直重输。
    private var failureText: String {
        switch membership.lastFailureReason {
        case "device_mismatch": return "此兑换码已在其他装置启用"
        case "expired": return "此兑换码已到期，请换一张新兑换码"
        case "already_forever": return "已是永久会员，无需再激活"
        case "network": return "网路连线失败，请稍后重试"
        default: return "兑换码错误，请重新输入"
        }
    }

    private func activate() {
        guard !isSubmitting else { return }
        let key = input
        isSubmitting = true
        Task {
            let unlocked = await membership.activate(key)
            isSubmitting = false
            if unlocked {
                wrongKey = false
                SubscriptionStore.shared.cardKeyMembershipDidChange()
                dismiss()
            } else {
                wrongKey = true
            }
        }
    }
}

/// 需要会员的功能被挡下时显示的整页提示：说明这一页要卡密，并就地提供输入。
struct CardKeyLockedPrompt: View {
    let title: String
    let message: String

    @ObservedObject private var membership = CardKeyMembership.shared
    @State private var showsUnlock = false

    var body: some View {
        VStack(spacing: 16) {
            Image(systemName: "lock.fill")
                .font(.system(size: 38, weight: .semibold))
                .foregroundStyle(.secondary)

            Text(title)
                .font(.title3.weight(.semibold))

            Text(message)
                .font(.footnote)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)

            Button {
                showsUnlock = true
            } label: {
                Text(localized("输入兑换码"))
                    .font(.body.weight(.semibold))
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
            }
            .buttonStyle(.borderedProminent)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(32)
        .background(PageBackgroundView(scope: .settings).ignoresSafeArea())
        .navigationTitle(title)
        .toolbarTitleDisplayMode(.inline)
        .sheet(isPresented: $showsUnlock) {
            CardKeyUnlockView()
        }
        .onChange(of: membership.isUnlocked) { _, unlocked in
            if unlocked { showsUnlock = false }
        }
    }
}
