import SwiftUI
import UIKit

/// 设置首页最上面那张「我」的卡：头像、暱称、签名，以及一条阅读统计。
///
/// maintainer, 2026-11-06：放在「尊享会员」之上，样子照参考图；名字和头像可以改，
/// 只存在本机（`ReaderIdentityStore`）。统计是 `ReadingStatsStore` 里的真实数字，
/// 口径跟 阅读统计 页一致：时长 = 全部 session 相加，书籍 = 读过的书去重，天数 = 有
/// session 的自然日去重。
struct ReaderProfileHeader: View {
    @ObservedObject private var identity = ReaderIdentityStore.shared
    @ObservedObject private var stats = ReadingStatsStore.shared
    @State private var showsEditor = false

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Button {
                showsEditor = true
            } label: {
                identityRow
            }
            .buttonStyle(.plain)
            .accessibilityLabel(localized("编辑头像与名称"))
            .accessibilityHint(localized("只保存在这台装置"))

            statsCard
        }
        // 4pt：Form 的分组本身已经内缩 16，加上这里刚好离屏边 20，和参考图一致。
        .padding(.horizontal, 4)
        .padding(.top, 4)
        .padding(.bottom, 2)
        .sheet(isPresented: $showsEditor) {
            ReaderProfileEditorView()
        }
    }

    // MARK: - 头像、名字、签名

    private var identityRow: some View {
        HStack(alignment: .center, spacing: 16) {
            avatar

            VStack(alignment: .leading, spacing: 6) {
                HStack(spacing: 6) {
                    Text(identity.displayName)
                        .font(DSFont.fixed(size: 26, weight: .bold))
                        .foregroundStyle(DSColor.textPrimary)
                        .lineLimit(1)
                        .minimumScaleFactor(0.65)

                    // 整行都可以点开编辑页；这支笔只是告诉人「这里可以改」。
                    Image(systemName: "pencil")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(DSColor.textTertiary)
                        .accessibilityHidden(true)
                }

                Text(identity.displaySignature)
                    .font(DSFont.fixed(size: 13))
                    .foregroundStyle(DSColor.textSecondary)
                    .lineLimit(2)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Spacer(minLength: 0)
        }
        .contentShape(Rectangle())
    }

    private var avatar: some View {
        Group {
            // 没设过头像就是剑来那张内建图，不是灰色小人。
            if let image = identity.avatar ?? ReaderDefaultAvatar.image {
                Image(uiImage: image)
                    .resizable()
                    .scaledToFill()
            } else {
                ZStack {
                    DSColor.surfaceTertiary
                    Image(systemName: "person.fill")
                        .font(.system(size: 30))
                        .foregroundStyle(DSColor.textTertiary)
                }
            }
        }
        .frame(width: 76, height: 76)
        .clipShape(Circle())
        .overlay(
            Circle().strokeBorder(DSColor.border.opacity(0.7), lineWidth: 0.5)
        )
    }

    // MARK: - 统计

    private var statsCard: some View {
        HStack(spacing: 0) {
            statColumn(value: durationValue, unit: durationUnit, label: localized("阅读时长"))
            divider
            statColumn(value: "\(bookCount)", unit: localized("本"), label: localized("阅读书籍"))
            divider
            statColumn(value: "\(dayCount)", unit: localized("天"), label: localized("阅读天数"))
        }
        .padding(.vertical, 15)
        .interfaceCardSurface(in: RoundedRectangle(cornerRadius: 22, style: .continuous))
        .clipShape(RoundedRectangle(cornerRadius: 22, style: .continuous))
    }

    private func statColumn(value: String, unit: String, label: String) -> some View {
        VStack(spacing: 5) {
            HStack(alignment: .firstTextBaseline, spacing: 3) {
                Text(value)
                    .font(DSFont.fixed(size: 27, weight: .bold))
                    .foregroundStyle(DSColor.textPrimary)
                    .monospacedDigit()
                Text(unit)
                    .font(DSFont.fixed(size: 11))
                    .foregroundStyle(DSColor.textPrimary.opacity(0.72))
            }
            Text(label)
                .font(DSFont.fixed(size: 12))
                .foregroundStyle(DSColor.textSecondary)
        }
        .frame(maxWidth: .infinity)
        .accessibilityElement(children: .combine)
    }

    private var divider: some View {
        Rectangle()
            .fill(DSColor.separator)
            .frame(width: 0.5, height: 32)
    }

    // MARK: - 数字

    private var totalSeconds: TimeInterval {
        stats.totalDuration(in: stats.sessions)
    }

    private var totalMinutes: Int {
        max(0, Int((totalSeconds / 60).rounded()))
    }

    /// 不足一小时就报分钟，满一小时换成小时：一张卡上放不下「128 分钟」。
    private var durationValue: String {
        guard totalMinutes >= 60 else { return "\(totalMinutes)" }
        let hours = Double(totalMinutes) / 60
        return hours == hours.rounded() ? "\(Int(hours))" : String(format: "%.1f", hours)
    }

    private var durationUnit: String {
        totalMinutes >= 60 ? localized("小时") : localized("分钟")
    }

    private var bookCount: Int {
        Set(stats.sessions.map(\.bookId)).count
    }

    private var dayCount: Int {
        let calendar = Calendar.current
        return Set(stats.sessions.map { calendar.startOfDay(for: $0.startDate) }).count
    }
}

// MARK: - 编辑

/// 编辑头像、暱称、签名。改的是草稿，按「完成」才写进 `ReaderIdentityStore`，
/// 按「取消」整份丢掉 —— 包括刚选的头像。
struct ReaderProfileEditorView: View {
    @Environment(\.dismiss) private var dismiss
    @ObservedObject private var identity = ReaderIdentityStore.shared

    @State private var draftName = ""
    @State private var draftSignature = ""
    @State private var draftAvatar: UIImage?
    @State private var didLoadDraft = false

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    HStack {
                        Spacer(minLength: 0)
                        avatarPicker
                        Spacer(minLength: 0)
                    }
                    .listRowBackground(Color.clear)
                }

                Section {
                    TextField(localized("暱称"), text: $draftName)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                        .onChange(of: draftName) { _, newValue in
                            if newValue.count > ReaderIdentityStore.nameLimit {
                                draftName = String(newValue.prefix(ReaderIdentityStore.nameLimit))
                            }
                        }

                    TextField(localized("签名"), text: $draftSignature)
                        .onChange(of: draftSignature) { _, newValue in
                            if newValue.count > ReaderIdentityStore.signatureLimit {
                                draftSignature = String(newValue.prefix(ReaderIdentityStore.signatureLimit))
                            }
                        }
                } footer: {
                    Text(localized("留空会显示预设的暱称与签名。"))
                        .dsSectionFooter()
                }

                Section {
                    Button(localized("恢复预设"), role: .destructive) {
                        draftName = ""
                        draftSignature = ""
                        draftAvatar = nil
                    }
                } footer: {
                    Text(localized("头像、暱称与签名只保存在这台装置，不会上传。"))
                        .dsSectionFooter()
                }
            }
            .navigationTitle(localized("编辑资料"))
            .navigationBarTitleDisplayMode(.inline)
            .themedAppSurface(for: .settings)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(localized("取消")) { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button(localized("完成")) {
                        identity.commit(
                            name: draftName,
                            signature: draftSignature,
                            avatar: draftAvatar
                        )
                        dismiss()
                    }
                    .fontWeight(.semibold)
                }
            }
            .onAppear(perform: loadDraftIfNeeded)
        }
    }

    private var avatarPicker: some View {
        ImageSourcePickerButton(
            accessibilityTitle: localized("头像"),
            extraActions: draftAvatar == nil ? [] : [
                ImageSourcePickerAction(
                    title: localized("恢复预设头像"),
                    systemImage: "arrow.uturn.backward",
                    isDestructive: true,
                    action: { draftAvatar = nil }
                )
            ],
            onPick: handlePick
        ) {
            avatarPreview
        }
    }

    private var avatarPreview: some View {
        VStack(spacing: 8) {
            Group {
                if let image = draftAvatar ?? ReaderDefaultAvatar.image {
                    Image(uiImage: image)
                        .resizable()
                        .scaledToFill()
                } else {
                    ZStack {
                        DSColor.surfaceTertiary
                        Image(systemName: "person.fill")
                            .font(.system(size: 36))
                            .foregroundStyle(DSColor.textTertiary)
                    }
                }
            }
            .frame(width: 92, height: 92)
            .clipShape(Circle())
            .overlay(
                Circle().strokeBorder(DSColor.border.opacity(0.7), lineWidth: 0.5)
            )

            Text(localized("更换头像"))
                .font(DSFont.caption)
                .foregroundStyle(DSColor.accent)
        }
        .padding(.vertical, 8)
        .contentShape(Rectangle())
    }

    private func loadDraftIfNeeded() {
        guard !didLoadDraft else { return }
        draftName = identity.name
        draftSignature = identity.signature
        draftAvatar = identity.avatar
        didLoadDraft = true
    }

    private func handlePick(_ result: Result<PickedImageSource, PickedImageError>) {
        switch result {
        case .success(.data(let data)):
            if let image = UIImage(data: data) { draftAvatar = image }
        case .success(.file(let url)):
            let scoped = url.startAccessingSecurityScopedResource()
            defer { if scoped { url.stopAccessingSecurityScopedResource() } }
            if let data = try? Data(contentsOf: url), let image = UIImage(data: data) {
                draftAvatar = image
            }
        case .failure:
            break
        }
    }
}
