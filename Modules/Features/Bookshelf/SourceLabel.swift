import Foundation

/// The value of 书籍资讯's 「来源」 row: where a copy came from, read from its source record
/// (unified library 1a). The mapping is in the Phase 1 plan; 远端书库 is the one string it
/// added (maintainer, 2026-10-10).
enum SourceLabel {
    /// `moduleTitle`: an installed module's title by id (`RuleModuleLibrary.installed(id:)`).
    static func text(for book: ReadingBook, record: SourceRecord, moduleTitle: (String) -> String? = { _ in nil }) -> String {
        switch record.key.instance.type {
        case .bookSource:
            return localized("网路书籍")
        case .opds:
            return RemoteLibraryKind.opds.libraryTitle
        case .webDAV:
            return RemoteLibraryKind.webDAV.libraryTitle
        case .calibre:
            return RemoteLibraryKind.calibre.libraryTitle
        case .gutenberg:
            return localized("Project Gutenberg")
        case .aozora:
            return localized("青空文库")
        case .module:
            // A module's book: the module, or 模组 once it was removed.
            return moduleTitle(record.key.instance.id) ?? localized("模组")
        case .library, .bibliographic:
            if book.aozora != nil { return localized("青空文库") }
            // A remote copy whose connection was removed: its kind is gone with it.
            if book.remoteSource != nil { return localized("远端书库") }
            return isWebPage(book) ? localized("网页汇入") : localized("本机文件")
        }
    }

    /// A browser import (`addWebBrowsedBook`) or a page saved by URL (`importWeb`).
    private static func isWebPage(_ book: ReadingBook) -> Bool {
        if book.isOnline { return true }
        let source = book.source.lowercased()
        return source.hasPrefix("http://") || source.hasPrefix("https://")
    }
}
