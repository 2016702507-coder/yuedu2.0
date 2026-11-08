import SwiftUI
import UIKit

/// Pro settings page for the custom app launch splash: a master switch plus a
/// light / dark image slot. Reached from 外观主题 (gated at that entry point), so
/// this page itself assumes access and only manages the images.
struct LaunchImageSettingsView: View {
    @Bindable private var settings = GlobalSettings.shared
    @State private var importAlert: LaunchImageImportAlert?

    private var hasAnyLaunchImage: Bool {
        settings.launchImageFileName(for: .light) != nil
            || settings.launchImageFileName(for: .dark) != nil
    }

    var body: some View {
        Form {
            Section {
                Toggle(localized("启用启动图"), isOn: $settings.launchImageEnabled)
            } footer: {
                if settings.launchImageEnabled && !hasAnyLaunchImage {
                    Text(localized("尚未导入任何启动图，请在下方选择图片。"))
                        .dsSectionFooter(color: .orange)
                } else {
                    Text(localized("开启后，每次启动 App 会短暂显示你设置的启动图。"))
                        .dsSectionFooter()
                }
            }
            .interfaceSectionSurface()

            Section {
                launchImageSlot(.light)
            } header: {
                Text(localized("浅色启动图"))
                    .foregroundStyle(DSColor.textSecondary)
            } footer: {
                Text(localized("浅色模式启动时显示。"))
                    .dsSectionFooter()
            }
            .interfaceSectionSurface()

            Section {
                launchImageSlot(.dark)
            } header: {
                Text(localized("深色启动图"))
                    .foregroundStyle(DSColor.textSecondary)
            } footer: {
                Text(localized("深色模式启动时显示。若只设置一张，另一模式会沿用。"))
                    .dsSectionFooter()
            }
            .interfaceSectionSurface()
        }
        .softScrollEdges()
        .navigationTitle(localized("启动图"))
        .toolbarTitleDisplayMode(.inline)
        .themedAppSurface(for: .settings)
        .alert(item: $importAlert) { alert in
            Alert(
                title: Text(localized("启动图汇入失败")),
                message: Text(alert.message),
                dismissButton: .default(Text(localized("确定")))
            )
        }
    }

    @ViewBuilder
    private func launchImageSlot(_ scheme: LaunchImageScheme) -> some View {
        let image = thumbnail(for: scheme)

        if let image {
            HStack(spacing: DSSpacing.md) {
                Image(uiImage: image)
                    .resizable()
                    .scaledToFill()
                    .frame(width: 60, height: 96)
                    .clipShape(RoundedRectangle(cornerRadius: DSRadius.lg, style: .continuous))
                    .overlay(
                        RoundedRectangle(cornerRadius: DSRadius.lg, style: .continuous)
                            .stroke(DSColor.textSecondary.opacity(0.25), lineWidth: 0.5)
                    )
                Text(localized("已设置"))
                    .font(DSFont.body)
                    .foregroundStyle(DSColor.textSecondary)
                Spacer(minLength: 0)
            }
            .padding(.vertical, DSSpacing.xs)
        }

        ImageSourcePickerButton(
            accessibilityTitle: localized(
                scheme == .dark ? "深色启动图" : "浅色启动图"
            ),
            onPick: { result in handlePick(result, for: scheme) }
        ) {
            Label(
                image == nil ? localized("选择图片") : localized("更换图片"),
                systemImage: "photo"
            )
        }

        if image != nil {
            Button(role: .destructive) {
                settings.clearLaunchImage(for: scheme)
            } label: {
                Label(localized("移除"), systemImage: "trash")
            }
        }
    }

    private func thumbnail(for scheme: LaunchImageScheme) -> UIImage? {
        guard let name = settings.launchImageFileName(for: scheme),
              let url = try? LaunchImageStorageManager.shared.fileURL(fileName: name),
              let image = UIImage(contentsOfFile: url.path) else {
            return nil
        }
        return image
    }

    private func handlePick(
        _ result: Result<PickedImageSource, PickedImageError>,
        for scheme: LaunchImageScheme
    ) {
        do {
            switch result {
            case .success(.data(let data)):
                try settings.importLaunchImage(data: data, for: scheme)
            case .success(.file(let url)):
                try settings.importLaunchImage(from: url, for: scheme)
            case .failure(let error):
                importAlert = LaunchImageImportAlert(message: localized(error.messageKey))
            }
        } catch let error as LaunchImageStorageError {
            importAlert = LaunchImageImportAlert(message: localized(error.messageKey))
        } catch {
            importAlert = LaunchImageImportAlert(message: localized("无法汇入启动图。"))
        }
    }
}

struct LaunchImageImportAlert: Identifiable {
    let id = UUID()
    let message: String
}

#Preview {
    NavigationStack {
        LaunchImageSettingsView()
    }
}
