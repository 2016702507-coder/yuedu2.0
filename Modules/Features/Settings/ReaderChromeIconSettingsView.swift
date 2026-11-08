import SwiftUI
import UniformTypeIdentifiers

/// 外观 → 阅读界面 → 自定义 → 按钮图示. Which reader buttons are drawn and what
/// artwork each one uses.
///
/// The tools are the bottom bar's capsule; the actions are the book card that opens
/// from the cover circle, and the AI ones the bottom bar's 更多.
struct ReaderChromeIconSettingsView: View {
    @Bindable private var settings = GlobalSettings.shared
    @State private var importError: ReaderChromeIconImportError?

    var body: some View {
        Form {
            section(
                items: ReaderChromeToolItem.allCases,
                headerKey: "底部工具",
                footerKey: "关掉的按钮会整个离开工具列。主题固定显示——它是回到阅读设置的唯一入口。"
            )
            section(
                items: ReaderChromeActionItem.allCases.filter { !$0.isInMoreMenu },
                headerKey: "书籍动作",
                footerKey: "这些动作都在点封面圆圈之后的书卡里。原本就不适用这本书的动作仍然不会出现。"
            )
            section(
                items: ReaderChromeActionItem.allCases.filter(\.isInMoreMenu),
                headerKey: "更多",
                footerKey: "这些动作在底部工具列的「更多」里。"
            )
        }
        .softScrollEdges()
        .scrollContentBackground(.hidden)
        .navigationTitle(localized("按钮图示"))
        .toolbarTitleDisplayMode(.inline)
        .themedAppSurface(for: .settings)
        .alert(item: $importError) { error in
            Alert(
                title: Text(localized("图标导入失败")),
                message: Text(error.message),
                dismissButton: .default(Text(localized("确定")))
            )
        }
    }

    private func section<Item: ReaderChromeIconItem>(
        items: [Item],
        headerKey: String,
        footerKey: String
    ) -> some View {
        Section {
            ForEach(items) { item in
                row(for: item)
            }
        } header: {
            Text(localized(headerKey))
                .font(DSFont.headline)
                .foregroundStyle(DSColor.textPrimary)
        } footer: {
            Text(localized(footerKey))
                .dsSectionFooter()
        }
        .interfaceSectionSurface()
    }

    private func row<Item: ReaderChromeIconItem>(for item: Item) -> some View {
        let asset = settings.readerChromeIcon(for: item)
        return VStack(spacing: DSSpacing.sm) {
            HStack(spacing: DSSpacing.md) {
                glyphPreview(for: item)

                VStack(alignment: .leading, spacing: DSSpacing.xs) {
                    Text(localized(item.titleKey))
                        .foregroundStyle(DSColor.textPrimary)
                    Text(asset?.originalFileName ?? localized("未选择图片"))
                        .font(DSFont.caption)
                        .foregroundStyle(asset == nil ? DSColor.textSecondary : DSColor.accent)
                        .lineLimit(1)
                }

                Spacer(minLength: DSSpacing.md)

                ImageSourcePickerButton(
                    accessibilityTitle: localized(item.titleKey),
                    contentTypes: Self.iconContentTypes,
                    extraActions: asset == nil ? [] : [
                        ImageSourcePickerAction(
                            title: localized("移除图片"),
                            systemImage: "trash",
                            isDestructive: true,
                            action: { settings.deleteReaderChromeIcon(for: item) }
                        )
                    ],
                    onPick: { result in handleIconPick(result, item: item) }
                ) {
                    Label(localized("选择图片"), systemImage: "photo")
                        .labelStyle(.iconOnly)
                        .font(DSFont.subheadline)
                }
                .buttonStyle(.bordered)
            }

            if item.isAlwaysVisible {
                HStack {
                    Text(localized("显示"))
                        .font(DSFont.subheadline)
                        .foregroundStyle(DSColor.textSecondary)
                    Spacer(minLength: DSSpacing.md)
                    Text(localized("固定显示"))
                        .font(DSFont.caption)
                        .foregroundStyle(DSColor.textSecondary)
                }
            } else {
                Toggle(isOn: visibleBinding(for: item)) {
                    Text(localized("显示"))
                        .font(DSFont.subheadline)
                        .foregroundStyle(DSColor.textSecondary)
                }
            }
        }
        .padding(.vertical, DSSpacing.xs)
    }

    @ViewBuilder
    private func glyphPreview<Item: ReaderChromeIconItem>(for item: Item) -> some View {
        if let image = settings.readerChromeIconImage(for: item) {
            Image(uiImage: image)
                .renderingMode(.original)
                .resizable()
                .scaledToFit()
                .frame(width: 28, height: 28)
                .frame(width: 44, height: 44)
        } else {
            Image(systemName: item.defaultSystemImage)
                .font(DSFont.fixed(size: 22, weight: .regular))
                .foregroundStyle(DSColor.textPrimary)
                .frame(width: 44, height: 44)
        }
    }

    private func visibleBinding<Item: ReaderChromeIconItem>(for item: Item) -> Binding<Bool> {
        Binding(
            get: { settings.isReaderChromeItemVisible(item) },
            set: { settings.setReaderChromeItem(item, visible: $0) }
        )
    }

    private func handleIconPick<Item: ReaderChromeIconItem>(
        _ result: Result<PickedImageSource, PickedImageError>,
        item: Item
    ) {
        do {
            switch result {
            case .success(.data(let data)):
                try settings.importReaderChromeIcon(
                    data: data,
                    // Photos gives no file name; the row shows this under the title.
                    originalFileName: localized("相簿图片"),
                    item: item
                )
            case .success(.file(let url)):
                try settings.importReaderChromeIcon(from: url, item: item)
            case .failure(let error):
                importError = ReaderChromeIconImportError(message: localized(error.messageKey))
            }
        } catch {
            importError = ReaderChromeIconImportError(message: error.localizedDescription)
        }
    }

    private static let iconContentTypes: [UTType] = [
        .image,
        UTType(filenameExtension: "webp") ?? .data,
    ]
}

private struct ReaderChromeIconImportError: Identifiable {
    let id = UUID()
    let message: String
}

#Preview {
    NavigationStack {
        ReaderChromeIconSettingsView()
    }
}
