import Foundation
import SwiftUI

/// The one route a highlight-rule pack from another reader takes, whether it was picked
/// with 正则高亮's 汇入规则 or shared in from Files: parse, wear, and merge into the
/// user's rules. The result is an ordinary reading-settings plan, applied like any other
/// 正则高亮 import.
@MainActor
enum HighlightPackImportService {
    static func plan(
        _ data: Data,
        format: HighlightPackImporter.Format,
        fallbackName: String?
    ) async throws -> ReaderSettingsImportPlan {
        let settings = GlobalSettings.shared
        let wearsPro = SubscriptionStore.shared.hasAccess(.readerThemePacks)
        // Reeden's `{primaryColor}` is its reading scheme's accent; ours is the theme's.
        let context = HighlightPackImporter.Context(
            lightPrimaryHex: settings.appearanceTheme(for: .light, isProActive: wearsPro).accent.rgbHex,
            darkPrimaryHex: settings.appearanceTheme(for: .dark, isProActive: wearsPro).accent.rgbHex,
            bodySize: Double(ReaderConfig.shared.fontSize)
        )
        let pack = try await HighlightPackImporter.parse(
            data,
            format: format,
            context: context,
            assetStore: .shared
        )
        guard !pack.rules.isEmpty else {
            // Every rule was skipped; the notes say why, which "nothing to import" would not.
            throw HighlightPackPlanError.nothingUsable(notes: pack.notes)
        }
        return ReaderSettingsImportPlan(
            layout: nil,
            chapterTitleStyle: nil,
            regexHighlights: settings.regexHighlightConfiguration.addingImported(
                HighlightPackImporter.worn(pack.rules),
                replacingSameText: true
            ),
            dialogueBubbleStyle: nil,
            contentName: pack.name ?? fallbackName,
            notes: pack.notes
        )
    }
}

enum HighlightPackPlanError: LocalizedError {
    case nothingUsable(notes: [String])

    var errorDescription: String? {
        switch self {
        case .nothingUsable(let notes):
            return ([localized("这个高亮规则包里没有本 App 能使用的规则。")] + notes)
                .joined(separator: "\n")
        }
    }
}
