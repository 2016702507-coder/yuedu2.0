import SwiftUI
import UIKit

/// 設定首頁最上面那張「我」的卡：頭像、暱稱、簽名，以及一條閱讀統計。
///
/// maintainer, 2026-11-06：放在「尊享會員」之上，樣子照參考圖；名字和頭像可以改，
/// 只存在本機（`ReaderIdentityStore`）。統計是 `ReadingStatsStore` 裡的真實數字，
/// 口徑跟 閱讀統計 頁一致：時長 = 全部 session 相加，書籍 = 讀過的書去重，天數 = 有
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
            .accessibilityLabel(localized("編輯頭像與名稱"))
            .accessibilityHint(localized("只保存在這台裝置"))

            statsCard
        }
        // 4pt：Form 的分組本身已經內縮 16，加上這裡剛好離屏邊 20，和參考圖一致。
        .padding(.horizontal, 4)
        .padding(.top, 4)
        .padding(.bottom, 2)
        .sheet(isPresented: $showsEditor) {
            ReaderProfileEditorView()
        }
    }

    // MARK: - 頭像、名字、簽名

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

                    // 整行都可以點開編輯頁；這支筆只是告訴人「這裡可以改」。
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
            // 沒設過頭像就是劍來那張內建圖，不是灰色小人。
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

    // MARK: - 統計

    private var statsCard: some View {
        HStack(spacing: 0) {
            statColumn(value: durationValue, unit: durationUnit, label: localized("閱讀時長"))
            divider
            statColumn(value: "\(bookCount)", unit: localized("本"), label: localized("閱讀書籍"))
            divider
            statColumn(value: "\(dayCount)", unit: localized("天"), label: localized("閱讀天數"))
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

    // MARK: - 數字

    private var totalSeconds: TimeInterval {
        stats.totalDuration(in: stats.sessions)
    }

    private var totalMinutes: Int {
        max(0, Int((totalSeconds / 60).rounded()))
    }

    /// 不足一小時就報分鐘，滿一小時換成小時：一張卡上放不下「128 分鐘」。
    private var durationValue: String {
        guard totalMinutes >= 60 else { return "\(totalMinutes)" }
        let hours = Double(totalMinutes) / 60
        return hours == hours.rounded() ? "\(Int(hours))" : String(format: "%.1f", hours)
    }

    private var durationUnit: String {
        totalMinutes >= 60 ? localized("小時") : localized("分鐘")
    }

    private var bookCount: Int {
        Set(stats.sessions.map(\.bookId)).count
    }

    private var dayCount: Int {
        let calendar = Calendar.current
        return Set(stats.sessions.map { calendar.startOfDay(for: $0.startDate) }).count
    }
}

// MARK: - 編輯

/// 編輯頭像、暱稱、簽名。改的是草稿，按「完成」才寫進 `ReaderIdentityStore`，
/// 按「取消」整份丟掉 —— 包括剛選的頭像。
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
                    TextField(localized("暱稱"), text: $draftName)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                        .onChange(of: draftName) { _, newValue in
                            if newValue.count > ReaderIdentityStore.nameLimit {
                                draftName = String(newValue.prefix(ReaderIdentityStore.nameLimit))
                            }
                        }

                    TextField(localized("簽名"), text: $draftSignature)
                        .onChange(of: draftSignature) { _, newValue in
                            if newValue.count > ReaderIdentityStore.signatureLimit {
                                draftSignature = String(newValue.prefix(ReaderIdentityStore.signatureLimit))
                            }
                        }
                } footer: {
                    Text(localized("留空會顯示預設的暱稱與簽名。"))
                        .dsSectionFooter()
                }

                Section {
                    Button(localized("恢復預設"), role: .destructive) {
                        draftName = ""
                        draftSignature = ""
                        draftAvatar = nil
                    }
                } footer: {
                    Text(localized("頭像、暱稱與簽名只保存在這台裝置，不會上傳。"))
                        .dsSectionFooter()
                }
            }
            .navigationTitle(localized("編輯資料"))
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
            accessibilityTitle: localized("頭像"),
            extraActions: draftAvatar == nil ? [] : [
                ImageSourcePickerAction(
                    title: localized("恢復預設頭像"),
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

            Text(localized("更換頭像"))
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
