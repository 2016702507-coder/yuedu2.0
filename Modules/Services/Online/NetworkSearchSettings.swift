import Foundation

enum NetworkSearchSettings {
    static func clampedConcurrency(_ value: Int) -> Int {
        min(30, max(1, value))
    }

    /// Ceiling for offline downloads, which read the same 网路设置 → 并发数 knob as search.
    /// A search spreads its N requests over N different sites; a download aims all N at the
    /// ONE host the book's source lives on, so the same number is far less polite there.
    /// Legado drives both from a single `threadCount` (default 16), but its MD3 fork clamps
    /// the cache path with `maxDownloadConcurrency = 8` — follow that ceiling so raising the
    /// knob for search cannot turn a download into a hammer on a single site.
    static let maximumDownloadConcurrency = 8

    static func clampedDownloadConcurrency(_ value: Int) -> Int {
        min(maximumDownloadConcurrency, max(1, value))
    }
}

/// 网路设置 →「自动暂停」. `0` means never pause, whatever the number of sources: the settings
/// page promises「0不暂停」, and a hidden "10 once you have 300+ sources" override made 换源 stop
/// after ten results for a shelf of 1559 sources (feedback #16, maintainer 2026-10-18). Heat and
/// data use are bounded by 并发数 (and 搜索's thermal / low-power `SearchDevicePacing`), not here.
struct SearchAutoPausePolicy {
    let exactThreshold: Int

    /// The policy the user configured in 网路设置 — the one way every search reads it.
    @MainActor
    static var configured: SearchAutoPausePolicy {
        SearchAutoPausePolicy(count: GlobalSettings.shared.searchAutoPauseCount)
    }

    init(count: Int) {
        exactThreshold = max(0, count)
    }

    var isEnabled: Bool {
        exactThreshold > 0
    }

    func shouldPause(exactCount: Int, fuzzyCount: Int) -> Bool {
        guard isEnabled else { return false }
        if exactCount >= exactThreshold { return true }
        return fuzzyCount >= exactThreshold * 5
    }
}
