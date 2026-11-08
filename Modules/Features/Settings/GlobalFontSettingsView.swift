import SwiftUI
import UniformTypeIdentifiers

struct GlobalFontSettingsView: View {
    @Bindable private var settings = GlobalSettings.shared
    @ObservedObject private var subscription = SubscriptionStore.shared
    @State private var showingImporter = false
    @State private var showsPaywall = false
    @State private var importError: GlobalFontImportError?
    @State private var fontToDelete: UserFontInfo?

    var body: some View {
        Form {
            Section {
                selectionButton(
                    title: localized("系统字体"),
                    postScriptName: nil,
                    previewFont: GlobalAppTypography.font(.body, postScriptName: nil)
                )
            } footer: {
                Text(localized("套用于 App 介面，阅读正文仍使用阅读设置。"))
                    .dsSectionFooter()
            }
            .interfaceSectionSurface()

            Section(header: Text(localized("已汇入字体")).foregroundStyle(DSColor.textSecondary)) {
                if settings.userFonts.isEmpty {
                    Text(localized("尚未汇入字体"))
                        .font(DSFont.subheadline)
                        .foregroundStyle(DSColor.textSecondary)
                } else {
                    ForEach(settings.userFonts) { font in
                        selectionButton(
                            title: font.displayName,
                            postScriptName: font.postScriptName,
                            previewFont: GlobalAppTypography.font(
                                .body,
                                postScriptName: font.postScriptName
                            )
                        )
                        .swipeActions {
                            Button(role: .destructive) {
                                fontToDelete = font
                            } label: {
                                Label(localized("删除"), systemImage: "trash")
                            }
                        }
                    }
                }
            }
            .interfaceSectionSurface()

            Section {
                // Pro: the entry locks, fonts imported earlier stay usable.
                let locked = !ReaderPremiumVisibilityPolicy(isProActive: subscription.isProActive).allowsFontImport
                Button {
                    if locked { showsPaywall = true } else { showingImporter = true }
                } label: {
                    HStack {
                        Label(localized("汇入字体..."), systemImage: locked ? "lock.fill" : "plus")
                        if locked {
                            Spacer(minLength: DSSpacing.md)
                            Text(localized("需要 Pro"))
                                .foregroundStyle(DSColor.textSecondary)
                        }
                    }
                }
            } footer: {
                Text(localized("汇入后，字体会同时出现在全局字体与阅读设置。"))
                    .dsSectionFooter()
            }
            .interfaceSectionSurface()
        }
        .softScrollEdges()
        .navigationTitle(localized("全局字体"))
        .toolbarTitleDisplayMode(.inline)
        .themedAppSurface(for: .settings)
        .sheet(isPresented: $showsPaywall) {
            CardKeyUnlockView()
        }
        .fileImporter(
            isPresented: $showingImporter,
            allowedContentTypes: Self.fontContentTypes,
            allowsMultipleSelection: false,
            onCompletion: handleImport
        )
        .alert(item: $importError) { error in
            Alert(
                title: Text(localized("字体汇入失败")),
                message: Text(error.message),
                dismissButton: .default(Text(localized("确定")))
            )
        }
        .alert(
            localized("删除此字体？"),
            isPresented: Binding(
                get: { fontToDelete != nil },
                set: { if !$0 { fontToDelete = nil } }
            ),
            presenting: fontToDelete
        ) { font in
            Button(localized("删除"), role: .destructive) {
                settings.deleteUserFont(font)
                fontToDelete = nil
            }
            Button(localized("取消"), role: .cancel) {
                fontToDelete = nil
            }
        } message: { font in
            Text(
                font.displayName
                    + "\n"
                    + localized("删除后，全局字体与阅读设置将无法再使用此字体。")
            )
        }
    }

    private func selectionButton(
        title: String,
        postScriptName: String?,
        previewFont: Font
    ) -> some View {
        let isSelected = settings.selectedGlobalFontPostScript == postScriptName
        return Button {
            settings.selectedGlobalFontPostScript = postScriptName
        } label: {
            HStack {
                Text(title)
                    .font(previewFont)
                    .foregroundStyle(DSColor.textPrimary)
                Spacer()
                if isSelected {
                    Image(systemName: "checkmark")
                        .foregroundStyle(DSColor.accent)
                }
            }
        }
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }

    private static let fontContentTypes: [UTType] = ReaderStyleImportRoute.fontContentTypes

    private func handleImport(_ result: Result<[URL], Error>) {
        do {
            guard let url = try result.get().first else { return }
            let shouldStopAccessing = url.startAccessingSecurityScopedResource()
            defer {
                if shouldStopAccessing {
                    url.stopAccessingSecurityScopedResource()
                }
            }
            try settings.importGlobalFont(from: url)
        } catch {
            importError = GlobalFontImportError(message: error.localizedDescription)
        }
    }
}

private struct GlobalFontImportError: Identifiable {
    let id = UUID()
    let message: String
}

#Preview {
    NavigationStack {
        GlobalFontSettingsView()
    }
}
