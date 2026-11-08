import Foundation

enum CacheCategory: String, CaseIterable, Identifiable, Sendable {
    case chapters
    case ttsAudio
    case mangaImages
    case video
    case covers
    case diagnostics
    case remoteBooks

    var id: String { rawValue }

    var titleKey: String {
        switch self {
        case .chapters: return "章节快取"
        case .ttsAudio: return "听书音频快取"
        case .mangaImages: return "漫画图片快取"
        case .video: return "影片快取"
        case .covers: return "封面图片快取"
        case .diagnostics: return "诊断纪录"
        case .remoteBooks: return "远端书籍快取"
        }
    }

    var clearTitleKey: String {
        switch self {
        case .chapters: return "清除章节快取"
        case .ttsAudio: return "清除音频快取"
        case .mangaImages: return "清除漫画快取"
        case .video: return "清除影片快取"
        case .covers: return "清除封面快取"
        case .diagnostics: return "清除诊断纪录"
        case .remoteBooks: return "清除远端书籍快取"
        }
    }

    var detailKey: String {
        switch self {
        case .chapters: return "小说正文内容的离线快取"
        case .ttsAudio: return "TTS 合成的音频文件快取"
        case .mangaImages: return "漫画页面图片的离线快取"
        case .video: return "影片选集缩图等影片相关快取"
        case .covers: return "书籍封面图片的快取"
        case .diagnostics: return "设置 → 回馈中心 → 诊断纪录 显示的日志与崩溃记录"
        case .remoteBooks: return "线上阅读暂存；清除时保留正在阅读的内容、进度与离线副本"
        }
    }

    var systemImage: String {
        switch self {
        case .chapters: return "doc.text"
        case .ttsAudio: return "waveform"
        case .mangaImages: return "photo.on.rectangle.angled"
        case .video: return "play.rectangle"
        case .covers: return "photo"
        case .diagnostics: return "stethoscope"
        case .remoteBooks: return "books.vertical"
        }
    }
}

struct CacheStorageRoots: Equatable, Sendable {
    var chapters: URL
    var ttsAudio: URL
    var mangaImages: URL
    /// Episode stills taken from video streams (`VideoEpisodeStills`); regenerable.
    var videoStills: URL
    var covers: URL
    /// Network covers saved behind the pipeline's memory. Counted and cleared with
    /// `covers`: to the user both are 封面图片快取.
    var networkCovers: URL
    var diagnostics: URL
    var remoteBooks: URL

    init(
        chapters: URL,
        ttsAudio: URL,
        mangaImages: URL,
        covers: URL,
        videoStills: URL? = nil,
        diagnostics: URL,
        remoteBooks: URL? = nil,
        networkCovers: URL? = nil
    ) {
        self.chapters = chapters
        self.ttsAudio = ttsAudio
        self.mangaImages = mangaImages
        self.videoStills = videoStills
            ?? chapters.deletingLastPathComponent().appendingPathComponent("VideoStills", isDirectory: true)
        self.covers = covers
        self.networkCovers = networkCovers ?? chapters.deletingLastPathComponent().appendingPathComponent("NetworkCovers", isDirectory: true)
        self.diagnostics = diagnostics
        self.remoteBooks = remoteBooks ?? chapters.deletingLastPathComponent().appendingPathComponent("RemoteLibrary", isDirectory: true)
    }

    static var live: CacheStorageRoots {
        CacheStorageRoots(
            chapters: StorageLocations.onlineCache,
            ttsAudio: StorageLocations.ttsAudioCache,
            mangaImages: StorageLocations.mangaCache,
            covers: StorageLocations.covers,
            videoStills: StorageLocations.videoStillCache,
            diagnostics: StorageLocations.diagnostics,
            remoteBooks: StorageLocations.remoteLibraryCache,
            networkCovers: StorageLocations.networkCoverCache
        )
    }

    subscript(category: CacheCategory) -> URL {
        switch category {
        case .chapters: return chapters
        case .ttsAudio: return ttsAudio
        case .mangaImages: return mangaImages
        case .video: return videoStills
        case .covers: return covers
        case .diagnostics: return diagnostics
        case .remoteBooks: return remoteBooks
        }
    }
}

struct CacheStorageSnapshot: Equatable, Sendable {
    var chapters: Int64 = 0
    var ttsAudio: Int64 = 0
    var mangaImages: Int64 = 0
    var videoStills: Int64 = 0
    var covers: Int64 = 0
    var diagnostics: Int64 = 0
    var remoteBooks: Int64 = 0

    subscript(category: CacheCategory) -> Int64 {
        switch category {
        case .chapters: return chapters
        case .ttsAudio: return ttsAudio
        case .mangaImages: return mangaImages
        case .video: return videoStills
        case .covers: return covers
        case .diagnostics: return diagnostics
        case .remoteBooks: return remoteBooks
        }
    }

    var total: Int64 {
        chapters + ttsAudio + mangaImages + videoStills + covers + diagnostics + remoteBooks
    }
}

enum CacheManagementError: LocalizedError, Equatable {
    case clearFailed(category: CacheCategory, message: String)

    var errorDescription: String? {
        switch self {
        case let .clearFailed(category, message):
            return "Unable to clear \(category.rawValue) cache: \(message)"
        }
    }
}

/// The books behind `CacheStorageRoots.covers`. That directory holds the covers books
/// downloaded beside covers nothing can fetch again, an imported book's own artwork among
/// them, so 快取管理 asks the books which files those are before deleting and tells them
/// afterwards. Feedback #116: covers were deleted wholesale while every book kept pointing
/// at its file, and nothing ever fetched one back.
@MainActor
protocol SavedCoverOwner: AnyObject {
    /// Files in `covers` no download brings back; clearing keeps them. Nil while the books
    /// are not all known (an unreadable shelf file): no file can then be shown to be
    /// replaceable, and the directory is left alone.
    func irreplaceableCoverFilenames() -> Set<String>?
    /// `covers` has just been cleared: fetch back the covers books still show.
    func downloadedCoversRemoved()
}

/// Owns the cache-management use cases exposed by Settings.
///
/// Only app-maintained, re-downloadable artifacts are included here. Imported
/// books, local manga archives, audiobook files, settings, and sync payloads are
/// deliberately outside these roots and are never removed by this service.
final class CacheManagementService: @unchecked Sendable {
    private let coverOwner: any SavedCoverOwner
    private let fileManager: FileManager
    private let roots: CacheStorageRoots
    /// The live writer behind the diagnostics directory, when there is one. Tests
    /// pass `nil` so clearing stays inside their own fixture instead of reaching
    /// through the singleton to the real device log.
    private let diagnosticLog: DiagnosticLog?
    private let remoteLibraryCache: RemoteLibraryCache
    /// Told when the downloaded-cover directory is emptied, so no screen keeps
    /// drawing a deleted cover and no load already reading one can put it back.
    private let coverPipeline: CoverImagePipeline
    /// Told once the stills directory is emptied, so 选集 cards stop drawing the bitmaps
    /// they hold and take their stills again. A closure because the owner
    /// (`VideoEpisodeStills`) is main-actor isolated and tests have no player.
    private let videoStillsCleared: @Sendable () -> Void

    init(
        coverOwner: any SavedCoverOwner,
        fileManager: FileManager = .default,
        roots: CacheStorageRoots = .live,
        diagnosticLog: DiagnosticLog? = .shared,
        remoteLibraryCache: RemoteLibraryCache? = nil,
        coverPipeline: CoverImagePipeline = .shared,
        videoStillsCleared: @escaping @Sendable () -> Void = {
            Task { @MainActor in VideoEpisodeStills.shared.forgetClearedStills() }
        }
    ) {
        self.coverOwner = coverOwner
        self.fileManager = fileManager
        self.roots = roots
        self.diagnosticLog = diagnosticLog
        self.coverPipeline = coverPipeline
        self.videoStillsCleared = videoStillsCleared
        self.remoteLibraryCache = remoteLibraryCache
            ?? (roots.remoteBooks == StorageLocations.remoteLibraryCache ? .shared : RemoteLibraryCache(root: roots.remoteBooks))
    }

    func snapshot() async -> CacheStorageSnapshot {
        let keptCovers = await coverOwner.irreplaceableCoverFilenames()
        return CacheStorageSnapshot(
            chapters: byteCount(in: roots.chapters),
            ttsAudio: byteCount(in: roots.ttsAudio),
            mangaImages: byteCount(in: roots.mangaImages),
            videoStills: byteCount(in: roots.videoStills),
            covers: clearableCoverBytes(keeping: keptCovers) + byteCount(in: roots.networkCovers),
            diagnostics: byteCount(in: roots.diagnostics),
            remoteBooks: byteCount(in: roots.remoteBooks)
        )
    }

    func clear(_ category: CacheCategory) async throws {
        // The diagnostics directory has a live writer behind it. Deleting the files
        // from under it would race the batched append; `DiagnosticLog.clear()` does
        // the same work on the queue that owns those files.
        if category == .diagnostics, let diagnosticLog {
            diagnosticLog.clear()
            return
        }
        do {
            if category == .remoteBooks {
                try remoteLibraryCache.clearInactive()
                return
            }
            if category == .covers {
                try await clearCovers()
                return
            }
            if category == .video {
                try clearDirectory(roots.videoStills)
                videoStillsCleared()
                return
            }
            try clearDirectory(roots[category])
        } catch {
            AppLogger.error(
                "CacheManagementService failed to clear \(category.rawValue)",
                error: error
            )
            throw CacheManagementError.clearFailed(
                category: category,
                message: error.localizedDescription
            )
        }
    }

    func clearAll() async throws {
        for category in CacheCategory.allCases {
            try await clear(category)
        }
    }

    /// Deletes every file in `covers` but those the books cannot fetch again, and all of
    /// `networkCovers`; then the books fetch back the covers they show.
    private func clearCovers() async throws {
        let kept = await coverOwner.irreplaceableCoverFilenames()
        if kept == nil {
            AppLogger.cache("⟐ saved covers kept: the shelf did not load completely", level: .notice)
        }
        let deletion = Result {
            if let kept { try clearDirectory(roots.covers, keeping: kept) }
            try clearDirectory(roots.networkCovers)
        }
        // Also when the delete stopped partway: whatever did go must not keep drawing from
        // memory, and the books fetch it back. Told only now, so nothing they fetch back is
        // deleted after.
        coverPipeline.invalidateDownloadedBookCovers()
        await coverOwner.downloadedCoversRemoved()
        try deletion.get()
    }

    /// What clearing `covers` frees, without the files it keeps: a size that stays after
    /// 清除 reads as a broken button.
    private func clearableCoverBytes(keeping kept: Set<String>?) -> Int64 {
        guard let kept else { return 0 }
        return byteCount(in: roots.covers) { !kept.contains($0.lastPathComponent) }
    }

    private func byteCount(in directory: URL, counting isCounted: (URL) -> Bool = { _ in true }) -> Int64 {
        guard let enumerator = fileManager.enumerator(
            at: directory,
            includingPropertiesForKeys: [.fileSizeKey, .isRegularFileKey]
        ) else { return 0 }

        var total: Int64 = 0
        for case let fileURL as URL in enumerator {
            guard
                let values = try? fileURL.resourceValues(
                    forKeys: [.fileSizeKey, .isRegularFileKey]
                ),
                values.isRegularFile == true,
                isCounted(fileURL)
            else { continue }
            total += Int64(values.fileSize ?? 0)
        }
        return total
    }

    private func clearDirectory(_ directory: URL, keeping kept: Set<String> = []) throws {
        guard fileManager.fileExists(atPath: directory.path) else {
            try fileManager.createDirectory(
                at: directory,
                withIntermediateDirectories: true
            )
            return
        }

        let contents = try fileManager.contentsOfDirectory(
            at: directory,
            includingPropertiesForKeys: nil,
            options: []
        )
        for item in contents where !kept.contains(item.lastPathComponent) {
            try fileManager.removeItem(at: item)
        }
    }
}
