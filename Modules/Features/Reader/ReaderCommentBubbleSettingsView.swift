import SwiftUI
import UIKit

/// 气泡设置: what the reader draws for a source's review marks — the 段评 count bubble and
/// the 本章说 / 作者说 / 神评论 cards, each on its own page with its own styles.
struct ReaderCommentBubbleSettingsView: View {
    @Bindable private var settings = GlobalSettings.shared
    /// Hands a 汇入样式 to whoever owns the first-level document picker
    /// (`ReaderSettingsView.requestStyleImporter`); nil hides 汇入.
    var onOpenImporter: ((ReaderStyleImportRoute) -> Void)?

    var body: some View {
        Form {
            Section {
                NavigationLink {
                    ReviewPanelStyleSettingsView()
                } label: {
                    SettingsRowLabel(
                        localized("段评与互动样式"),
                        systemImage: "text.bubble.fill"
                    )
                }
            } footer: {
                Text(localized("按区域自订段评面板、评论、热评、本章说与作者说的 CSS，可存多套样式并汇入汇出。"))
                    .dsSectionFooter()
            }
            .interfaceSectionSurface()

            Section {
                NavigationLink {
                    ReaderParagraphBubbleSettingsView(onOpenImporter: onOpenImporter.map { open in
                        { open(.commentBubble) }
                    })
                } label: {
                    SettingsValueLabel(
                        title: localized("段评气泡"),
                        systemImage: ReadingSettingsScopeItem.commentBubble.systemImage,
                        value: bubbleValue
                    )
                }

                ForEach(ReaderCommentCardKind.allCases) { kind in
                    NavigationLink {
                        ReaderCommentCardSettingsView(kind: kind, onOpenImporter: onOpenImporter.map { open in
                            { open(.commentCard(kind)) }
                        })
                    } label: {
                        SettingsValueLabel(
                            title: kind.localizedTitle,
                            systemImage: kind.systemImage,
                            value: cardValue(kind)
                        )
                    }
                }
            } footer: {
                Text(localized("内建「玻璃」的本章说与神评论字级固定、作者说随阅读字级缩放；自订模板跟随阅读字体与字级。"))
                    .dsSectionFooter()
            }
            .interfaceSectionSurface()
        }
        .softScrollEdges()
        .navigationTitle(localized("气泡设置"))
        .toolbarTitleDisplayMode(.inline)
        .readerGlassSettingsSurface()
    }

    private var bubbleValue: String {
        guard !settings.commentBubbleFollowsSourceSVG else { return localized("来源样式") }
        switch settings.commentBubblePresetMode {
        case .builtin, .square:
            return localized(settings.commentBubblePresetMode.titleKey)
        case .custom:
            let name = settings.commentBubbleCustomStyleName.trimmingCharacters(in: .whitespacesAndNewlines)
            return name.isEmpty ? localized("自订 SVG") : name
        }
    }

    private func cardValue(_ kind: ReaderCommentCardKind) -> String {
        switch settings.wornCommentCardTemplate(for: kind) {
        case nil: return localized("来源样式")
        case .builtin: return localized("玻璃")
        case .custom(let style): return style.name
        }
    }
}

#Preview {
    NavigationStack {
        ReaderCommentBubbleSettingsView(onOpenImporter: { _ in })
    }
}
