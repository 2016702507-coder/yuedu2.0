import Foundation

/// Where a copy is read from, in a word: under the reader's title capsule and in 换源's list of
/// versions (maintainer 2026-10-26: every origin is a version like any other). A 来源配置's, a
/// module's or a library connection's own name; 青空文库 or Project Gutenberg; 网页汇入 for a page
/// the browser imported; 本机 for a file imported on this device.
@MainActor
enum BookOriginName {
    /// In `SourceRecord.derived(from:context:)`'s order: a library's file, a 青空文库 work, a
    /// module's book, a 来源配置's book, then what was imported.
    static func of(_ book: ReadingBook) -> String {
        if let remote = book.remoteSource {
            if remote.connectionID == PublicLibraryID.gutenberg.rawValue { return localized("Project Gutenberg") }
            // A removed connection leaves the file it gave.
            return RemoteLibraryConnectionStore.shared.connection(id: remote.connectionID)?.name ?? localized("本机")
        }
        if book.aozora != nil { return localized("青空文库") }
        if book.isOnline, let module = book.module {
            return RuleModuleLibrary.shared.installed(id: module.moduleID)?.module.title ?? localized("模组")
        }
        if book.isOnline, let sourceID = book.bookSourceId {
            return BookSourceStore.shared.source(id: sourceID).map(\.bookSourceName)
                .flatMap { $0.isEmpty ? nil : $0 } ?? localized("未知来源配置")
        }
        return book.isOnline ? localized("网页汇入") : localized("本机")
    }

    /// A version not read here yet, by the place that has it: a library connection's or a
    /// module's name, 青空文库 or Project Gutenberg; nil for a copy or a 来源配置's book, named
    /// from their own records.
    static func of(_ version: WorkDetailRoute) -> String? {
        switch version.opening {
        case .opdsEntry(_, let id), .webDAVFile(_, let id):
            RemoteLibraryConnectionStore.shared.connection(id: id)?.name ?? localized("远端书库")
        case .gutenberg: localized("Project Gutenberg")
        case .aozora: localized("青空文库")
        case .moduleBook(let book):
            RuleModuleLibrary.shared.installed(id: book.reference.moduleID)?.module.title ?? localized("模组")
        case .copy, .onlineBook, .bibliographic: nil
        }
    }
}
