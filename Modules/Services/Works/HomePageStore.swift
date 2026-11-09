import Combine
import Foundation

/// Why the home cannot be written this launch. The file's protection (an unreadable or
/// newer-build file is never overwritten) stays; the reader is now told about it instead
/// of editing a home that silently reverts on the next launch.
enum HomeSaveIssue: String, Sendable {
    /// `Data(contentsOf:)` failed: permissions, a directory where the file should be, I/O.
    case unreadable
    /// The file came from a build whose schema this one cannot name.
    case newerBuild
    /// The file decoded neither strictly nor leniently.
    case corrupt
    /// The atomic write itself threw (full storage, I/O, protection).
    case writeFailed
}

/// Unified library 5a: the Explore home, `explore_home.json`; since 5d-4 every 首页配置 in it
/// (`HomeConfigurations`, Phase 5 plan, decision 22).
///
/// - It is read once, when the store is made. `home` is nil until something saves one; the
///   home decides when to save `HomePageDefaults` (5c).
/// - `page`, `edit` and `save` act on the selected configuration, so 编辑首页, a section's long
///   press and 聚合设置's 首页栏目 edit whichever one 范围 shows.
/// - Writes replace the file atomically on one serial queue.
/// - A file of this version that does not decode is copied aside
///   (`explore_home.corrupt-<mtime>.json`) before anything is written over it.
/// - A file that cannot be read, or cannot be copied aside, is never written over.
/// - A file from a newer build is read section by section, skipping what does not decode, and
///   never written over: writing it back would drop what this build cannot name.
/// - The custom pages move in once (5d-4): when a file older than 5d-4 is read, or when the
///   first home is made. `custom_explore_pages.json` is left where it is.
/// - A 预设 still as the defaults of 2026-10-13 to 2026-10-25 made it takes the 2026-10-25
///   layouts once (`HomeDefaultsRhythmMigration`).
/// - 预设's official modules' lists follow the language, as the home reads it
///   (`HomeDefaultsLanguageSwap`).
/// - 为你推荐, deleted 2026-10-27, is taken off every 首页配置 that still has it
///   (`removeDeletedForYou`).
@MainActor
final class HomePageStore: ObservableObject {
    /// The app's home; the editor (5d) changes the same one the home draws.
    static let shared = HomePageStore(appliesDefaultsRhythmOnce: true)

    /// Every configuration; nil until the home is first made.
    @Published private(set) var home: HomeConfigurations?

    /// The selected configuration's sections.
    var page: HomePage? {
        home.map { HomePage(sections: $0.sections(of: $0.selectedID)) }
    }

    var selectedConfiguration: HomeConfigurationID { home?.selectedID ?? .defaults }

    /// 首页配置's page: the reader's own, with 预设 where it was moved to unless it was deleted.
    var configurations: [HomeConfigurationListing] {
        (home ?? HomeConfigurations(sections: [])).listings
    }

    /// Each 首页配置's photo, in a folder beside the file.
    let photos: HomeConfigurationPhotos
    /// 大图卡片's cards' photos, in another.
    let cardPhotos: HomeListCardPhotos

    /// Whether saves stay in memory this launch, because the file could not be read or comes
    /// from a newer build.
    private(set) var isReadOnly = false

    /// Why saving is unavailable, published so the home can show it. Kept separate from
    /// `isReadOnly`: a write that fails later is not read-only, but the reader must still know.
    @Published private(set) var saveIssue: HomeSaveIssue?

    /// The 最新 sections' 排除的来源 the file still holds from before 5d-3f, which
    /// `AggregationSettingsStore` adopts as 显示在最新. Read once, with the file.
    private(set) var legacyLatestExcluded: [SourceInstanceKey] = []

    private let fileURL: URL
    private let customPagesURL: URL
    private let defaults: UserDefaults
    private let queue = DispatchQueue(label: "com.yuedu.explore.home")
    /// Whether this store gives an untouched 预设 the 2026-10-25 layouts once; only the app's own
    /// does, so a test's home is read as it was saved.
    private let appliesDefaultsRhythmOnce: Bool

    /// - Parameter customPagesURL: the custom pages that move in; beside the home by default.
    init(fileURL: URL = StorageLocations.applicationSupportRoot.appendingPathComponent("explore_home.json"),
         customPagesURL: URL? = nil, defaults: UserDefaults = .standard, appliesDefaultsRhythmOnce: Bool = false) {
        self.fileURL = fileURL
        self.customPagesURL = customPagesURL
            ?? fileURL.deletingLastPathComponent().appendingPathComponent("custom_explore_pages.json")
        self.defaults = defaults
        self.appliesDefaultsRhythmOnce = appliesDefaultsRhythmOnce
        // 首页配置's form draws its photo at 96pt, three pixels a point.
        photos = HomeConfigurationPhotos(directory: fileURL.deletingLastPathComponent()
            .appendingPathComponent("HomeConfigurationPhotos", isDirectory: true),
            pixelSize: CGSize(width: 288, height: 288))
        // A 大图卡片 card is about 400pt across on a phone, three pixels a point.
        cardPhotos = HomeListCardPhotos(directory: fileURL.deletingLastPathComponent()
            .appendingPathComponent("HomeListCardPhotos", isDirectory: true),
            pixelSize: CGSize(width: 1200, height: (1200 / DSLayout.homeBannerAspect).rounded()))
        load()
        // A card's photo goes with its card, its section or its 首页配置, gone since the last
        // launch, or with a 新增栏目 left with 取消; never from a home this build only reads.
        if let home, !isReadOnly {
            cardPhotos.removePhotos(keeping: HomeListCardPhotoID.all(in: home))
        }
    }

    /// The selected configuration, or the defaults for this reader as 预设, saved now so they
    /// never change under them (5a step 3), with the custom pages moved in beside it. Only 预设's
    /// official modules' lists change after, when `languages` does (`followLanguage`).
    ///
    /// Call it only once the book-source library is read (`ExploreTabModel.isLoaded`): before
    /// that `mode` cannot tell a reader with sources from a new install, and the wrong order
    /// would be saved for good. The region is taken as it stands: a public-library section
    /// saved before the region is known has no row in China, where its provider is hidden.
    func pageOrDefaults(mode: ExploreMode, publicLibrariesAvailable: Bool, languages: [String]) -> HomePage {
        let context = HomePageDefaults.Context(mode: mode, publicLibrariesAvailable: publicLibrariesAvailable,
                                               languages: languages)
        if var home {
            if followLanguage(in: &home, context: context) {
                self.home = home
                write()
            }
            return HomePage(sections: home.sections(of: home.selectedID))
        }
        let defaultPage = HomePageDefaults.page(for: context)
        // They have the 2026-10-25 layouts already; a reader who changes them keeps theirs.
        if appliesDefaultsRhythmOnce, !isReadOnly { defaults.set(true, forKey: Self.defaultsRhythmKey) }
        var made = HomeConfigurations(sections: defaultPage.sections)
        made.defaultsLanguages = languages
        if !isReadOnly { moveCustomPages(into: &made) }
        home = made
        write()
        AppLogger.cache("⟐ explore home starts from its defaults", context: [
            "mode": mode.rawValue, "publicLibraries": "\(publicLibrariesAvailable)", "sections": "\(defaultPage.sections.count)",
            "configurations": "\(made.configurations.count)",
        ])
        return page ?? defaultPage
    }

    /// 编辑首页 and a section's long press (5d-2): changes the selected configuration. Nothing
    /// to change before the home has read or made one.
    func edit(_ change: (inout HomePage) -> Void) {
        guard var page else { return }
        change(&page)
        save(page)
    }

    /// Replaces the selected configuration's sections; before any home, makes one with them
    /// as 预设.
    func save(_ page: HomePage) {
        if var home {
            home.setSections(page.sections, of: home.selectedID)
            self.home = home
        } else {
            home = HomeConfigurations(sections: page.sections)
        }
        write()
    }

    // MARK: 首页配置

    func select(_ id: HomeConfigurationID) {
        change { $0.selected = id == .defaults ? nil : id }
    }

    /// 新增首页配置 from a template: 空白模板 with no section; 预设配置 with the defaults the app
    /// keeps for this reader, whatever their 预设 has become (maintainer, 2026-10-23: they emptied
    /// 预设 and 预设配置 copied it, empty). The new one is selected.
    func createConfiguration(named name: String, from template: HomeConfigurationTemplate,
                             defaults context: HomePageDefaults.Context) {
        let sections = switch template {
        case .blank: [HomeSection]()
        case .defaults: HomePageDefaults.page(for: context).sections
        }
        change { home in
            let id = home.create(named: name, sections: sections)
            AppLogger.cache("⟐ 首页配置 made from a template", context: [
                "configuration": id.rawValue, "template": template.rawValue, "mode": context.mode.rawValue,
                "sections": "\(sections.count)",
            ])
        }
    }

    func renameConfiguration(_ id: HomeConfigurationID, to name: String) {
        change { $0.rename(id, to: name) }
    }

    /// Its photo goes with it; the last one left is kept (`HomeConfigurations.delete`).
    func deleteConfiguration(_ id: HomeConfigurationID) {
        guard configurations.count > 1, configurations.contains(where: { $0.id == id }) else { return }
        change { $0.delete(id) }
        photos.removePhoto(for: id)
    }

    /// 首页配置's 编辑: the list reordered, 预设 among the reader's own.
    func moveConfigurations(fromOffsets offsets: IndexSet, toOffset destination: Int) {
        change { $0.move(fromOffsets: offsets, toOffset: destination) }
    }

    /// 加入首页配置.
    func addCategory(_ reference: ExploreCategoryReference, to id: HomeConfigurationID) {
        change { $0.addCategory(reference, to: id) }
    }

    func contains(_ reference: ExploreCategoryReference, in id: HomeConfigurationID) -> Bool {
        home?.contains(reference, in: id) ?? false
    }

    private func change(_ body: (inout HomeConfigurations) -> Void) {
        guard var home else { return }
        body(&home)
        self.home = home
        write()
    }

    private func write() {
        guard let home else { return }
        guard !isReadOnly else {
            AppLogger.cache("⟐ explore home not saved: the file is read-only this launch",
                            context: ["configurations": "\(home.configurations.count)"])
            return
        }
        let url = fileURL
        // An edit is saved as soon as it is made. The queue write is asynchronous, so a reader
        // who edits and immediately leaves the app may be suspended (or killed from the app
        // switcher) while the bytes are still in flight — the next launch then reads the old
        // file and the edit is gone. A background task keeps the process alive until this
        // write has landed, mirroring `BookSourceStore.flushPendingWrites()`.
        let hold = BackgroundTaskHold(name: "exploreHome.persist")
        queue.async { [weak self] in
            defer { hold.release() }
            var failed = false
            do {
                let encoder = JSONEncoder()
                encoder.outputFormatting = [.sortedKeys]
                let data = try encoder.encode(home)
                try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
                try data.write(to: url, options: .atomic)
            } catch {
                failed = true
                AppLogger.cache("⟐ explore home could not be saved", error: error,
                                context: ["sections": "\(home.sections.count)"])
            }
            Task { @MainActor [weak self] in
                guard let self else { return }
                if failed {
                    self.saveIssue = .writeFailed
                } else if self.saveIssue == .writeFailed {
                    // A later edit saved fine: the warning has served its purpose.
                    self.saveIssue = nil
                }
            }
        }
    }

    /// Drains queued writes under a background task before the app can be suspended. Called
    /// from the scene phase as it leaves `.active`; the book sources and shelf metadata have
    /// the same guard, and the home's edits are user data too.
    func flushPendingWrites() {
        let hold = BackgroundTaskHold(name: "exploreHome.flush")
        queue.async { hold.release() }
    }

    /// After the reader chooses to rebuild: move the old file aside, lift the read-only guard
    /// and let `pageOrDefaults` make and save a fresh home. Moving needs no read, so even a
    /// file this build cannot decode or open is kept rather than overwritten. If the move
    /// fails the home stays read-only — never write over bytes we could not preserve.
    func recoverFromReadOnly() {
        guard isReadOnly else { return }
        if FileManager.default.fileExists(atPath: fileURL.path) {
            let backup = fileURL.deletingLastPathComponent()
                .appendingPathComponent("explore_home.rebuild-\(Int(Date().timeIntervalSince1970)).json")
            do {
                try FileManager.default.moveItem(at: fileURL, to: backup)
                AppLogger.cache("⟐ explore home kept aside before a rebuild",
                                context: ["backup": backup.lastPathComponent])
            } catch {
                AppLogger.cache("⟐ explore home could not be kept aside; it stays read-only", error: error)
                return
            }
        }
        isReadOnly = false
        saveIssue = nil
        home = nil
    }

    /// A failed write is not read-only: the in-memory home is intact, so try the same save
    /// again once the reader asks (for example after freeing storage).
    func retrySave() {
        guard saveIssue == .writeFailed else { return }
        saveIssue = nil
        write()
    }

    #if DEBUG
    /// Drains queued writes, for tests.
    nonisolated func waitForPendingWritesForTesting() {
        queue.sync {}
    }
    #endif

    // MARK: - 为你推荐, deleted

    /// Takes 为你推荐 off 预设 and every 首页配置 (`HomeSectionBinding.isDeletedForYou`; maintainer,
    /// 2026-10-27): its sections, the 顶部轮播图 among them, and its cards in a section of lists,
    /// whose section goes with its last card. On every read, not once: nothing puts it on a home
    /// any more, so a home without it is left as it is. Returns whether any was taken off.
    @discardableResult
    private func removeDeletedForYou(from home: inout HomeConfigurations) -> Bool {
        var removed = 0
        func strip(_ sections: inout [HomeSection]) {
            sections = sections.compactMap { section in
                if section.binding.isDeletedForYou {
                    removed += 1
                    return nil
                }
                guard case .lists(let cards) = section.binding else { return section }
                let kept = cards.filter { !$0.binding.isDeletedForYou }
                guard kept.count < cards.count else { return section }
                removed += cards.count - kept.count
                guard !kept.isEmpty else { return nil }
                var section = section
                section.binding = .lists(kept)
                return section
            }
        }
        strip(&home.sections)
        for index in home.configurations.indices { strip(&home.configurations[index].sections) }
        guard removed > 0 else { return false }
        AppLogger.cache("⟐ 为你推荐 taken off the saved home", context: ["removed": "\(removed)"])
        return true
    }

    // MARK: - The 2026-10-25 layouts

    /// Set once 预设 has been looked at for the 2026-10-25 layouts, or made with them.
    static let defaultsRhythmKey = "home.defaultsRhythm20261025"

    /// An untouched 预设 takes the 2026-10-25 layouts once (`HomeDefaultsRhythmMigration`), so a
    /// reader who puts a section back the way it was keeps it. Not on a file this build only
    /// reads. Returns whether a section changed.
    @discardableResult
    private func applyDefaultsRhythmOnce(to home: inout HomeConfigurations) -> Bool {
        guard appliesDefaultsRhythmOnce, !isReadOnly, !defaults.bool(forKey: Self.defaultsRhythmKey) else { return false }
        defaults.set(true, forKey: Self.defaultsRhythmKey)
        guard !home.defaultsDeleted, let outcome = HomeDefaultsRhythmMigration.apply(to: home.sections) else {
            AppLogger.cache("⟐ 预设 keeps its layouts: not the defaults of 2026-10-13 to 2026-10-25", context: [
                "sections": "\(home.sections.count)", "defaultsDeleted": "\(home.defaultsDeleted)",
            ])
            return false
        }
        home.sections = outcome.sections
        AppLogger.cache("⟐ 预设 takes the 2026-10-25 layouts", context: [
            "changed": "\(outcome.changed)", "kept": "\(outcome.kept)",
        ])
        return outcome.changed > 0
    }

    // MARK: - The language

    /// 预设's official modules' lists follow the language (`HomeDefaultsLanguageSwap`); the
    /// reader's own 首页配置 are theirs. A 预设 saved before 2026-10-27 did not say whose lists it
    /// holds, so its lists say it: when they include the language's, or there are none, nothing
    /// changes. Not on a file this build only reads. Returns whether the file changed.
    private func followLanguage(in home: inout HomeConfigurations, context: HomePageDefaults.Context) -> Bool {
        guard !isReadOnly, !home.defaultsDeleted, home.defaultsLanguages != context.languages else { return false }
        let held = home.defaultsLanguages
            ?? HomeDefaultsLanguageSwap.languages(of: home.sections, publicLibrariesAvailable: context.publicLibrariesAvailable)
        if home.defaultsLanguages == nil, held.isEmpty || held.contains(where: context.languages.contains) {
            home.defaultsLanguages = context.languages
            AppLogger.cache("⟐ 预设's lists taken as the language's", context: [
                "lists": held.joined(separator: ","), "language": context.languages.joined(separator: ","),
            ])
            return true
        }
        let outcome = HomeDefaultsLanguageSwap.apply(to: home.sections, from: held, to: context)
        home.sections = outcome.sections
        home.defaultsLanguages = context.languages
        AppLogger.cache("⟐ 预设 follows the language", context: [
            "from": held.joined(separator: ","), "to": context.languages.joined(separator: ","),
            "removed": "\(outcome.removed)", "added": "\(outcome.added)",
        ])
        return true
    }

    // MARK: - Custom pages

    /// The custom pages as configurations; the 首页页面 the reader had chosen, if a page,
    /// becomes the selected one (the deleted setting, `ExploreSettings.legacyLandingKey`).
    /// A file that could not be read is tried again on the next launch.
    private func moveCustomPages(into home: inout HomeConfigurations) {
        switch LegacyCustomExplorePages.read(customPagesURL) {
        case .absent:
            home.customPagesPending = false
        case .unreadable:
            home.customPagesPending = true
            return
        case .pages(let pages):
            home.adopt(pages)
            home.customPagesPending = false
            AppLogger.cache("⟐ custom pages moved into 首页配置", context: ["pages": "\(pages.count)"])
        }
        let pagePrefix = "page:"
        if let landing = defaults.string(forKey: ExploreSettings.legacyLandingKey), landing.hasPrefix(pagePrefix) {
            let id = UUID(uuidString: String(landing.dropFirst(pagePrefix.count))).map(HomeConfigurationID.init)
            if home.selected == nil, let id, home.configurations.contains(where: { $0.id == id }) { home.selected = id }
            defaults.removeObject(forKey: ExploreSettings.legacyLandingKey)
        }
    }

    // MARK: - File

    private struct Version: Decodable { var schemaVersion: Int }

    /// The part of a pre-5d-3f file that `HomeSectionBinding` no longer reads.
    private struct LegacyLatest: Decodable {
        struct Section: Decodable {
            struct Binding: Decodable {
                var type: String
                var excluded: [SourceInstanceKey]?
            }
            var binding: Binding
        }
        var sections: [Section]

        var excluded: [SourceInstanceKey] {
            var keys: [SourceInstanceKey] = []
            for section in sections where section.binding.type == "latest" {
                for key in section.binding.excluded ?? [] where !keys.contains(key) { keys.append(key) }
            }
            return keys
        }
    }

    /// A newer build's file: the sections that decode.
    private struct LenientPage: Decodable {
        var sections: [HomeSection]
        var skipped = 0

        private enum CodingKeys: String, CodingKey { case sections }
        private struct Skipped: Decodable {}

        init(from decoder: Decoder) throws {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            var list = try container.nestedUnkeyedContainer(forKey: .sections)
            var decoded: [HomeSection] = []
            while !list.isAtEnd {
                // A failed decode leaves the container on the same element, so it can be
                // stepped over; the count is logged by `load`.
                do {
                    decoded.append(try list.decode(HomeSection.self))
                } catch {
                    _ = try list.decode(Skipped.self)
                    skipped += 1
                }
            }
            sections = decoded
        }
    }

    private func load() {
        guard FileManager.default.fileExists(atPath: fileURL.path) else { return }
        let data: Data
        do {
            data = try Data(contentsOf: fileURL)
        } catch {
            AppLogger.cache("⟐ explore home could not be read; it will not be written over", error: error)
            isReadOnly = true
            saveIssue = .unreadable
            return
        }
        do {
            let version = try JSONDecoder().decode(Version.self, from: data).schemaVersion
            if version > HomePage.currentSchemaVersion {
                let lenient = try JSONDecoder().decode(LenientPage.self, from: data)
                home = HomeConfigurations(sections: lenient.sections)
                isReadOnly = true
                saveIssue = .newerBuild
                AppLogger.cache("⟐ explore home comes from a newer build; reading it without writing", context: [
                    "schemaVersion": "\(version)", "sections": "\(lenient.sections.count)", "skipped": "\(lenient.skipped)",
                ])
                return
            }
            var read: HomeConfigurations
            if version < 2 {
                // Before 5d-4: the one home, which becomes 预设, and the custom pages move in.
                read = HomeConfigurations(sections: try JSONDecoder().decode(HomePage.self, from: data).sections)
                readLegacyLatestExcluded(data)
                moveCustomPages(into: &read)
                removeDeletedForYou(from: &read)
                applyDefaultsRhythmOnce(to: &read)
                home = read
                write()
                return
            }
            read = try JSONDecoder().decode(HomeConfigurations.self, from: data)
            // Before the layouts, which recognise a 预设 by its sections without 为你推荐.
            let removed = removeDeletedForYou(from: &read)
            let restyled = applyDefaultsRhythmOnce(to: &read)
            if read.customPagesPending {
                moveCustomPages(into: &read)
                home = read
                if !read.customPagesPending || removed || restyled { write() }
                return
            }
            home = read
            if removed || restyled { write() }
        } catch {
            AppLogger.cache("⟐ explore home could not be decoded", error: error)
            isReadOnly = !keepAside(data)
            // `keepAside` saved the bytes, so a rebuild is safe; still show why the home
            // came back empty rather than silently reverting on every launch.
            if isReadOnly { saveIssue = .corrupt }
        }
    }

    private func readLegacyLatestExcluded(_ data: Data) {
        do {
            legacyLatestExcluded = try JSONDecoder().decode(LegacyLatest.self, from: data).excluded
        } catch {
            // The page itself decoded; only the old list is lost, and with it nothing to move.
            AppLogger.cache("⟐ explore home's old 排除的来源 could not be read", error: error)
        }
    }

    /// Copies an undecodable file next to itself, named after its modification time so a
    /// second launch finds the copy it already made. Returns whether the bytes are safe.
    private func keepAside(_ data: Data) -> Bool {
        let modified: Date
        do {
            modified = try FileManager.default.attributesOfItem(atPath: fileURL.path)[.modificationDate] as? Date ?? Date()
        } catch {
            AppLogger.cache("⟐ explore home's modification date could not be read", error: error)
            modified = Date()
        }
        let copy = fileURL.deletingLastPathComponent()
            .appendingPathComponent("explore_home.corrupt-\(Int(modified.timeIntervalSince1970)).json")
        if FileManager.default.fileExists(atPath: copy.path) { return true }
        do {
            try data.write(to: copy, options: .withoutOverwriting)
            AppLogger.cache("⟐ explore home kept aside as \(copy.lastPathComponent)")
            return true
        } catch {
            AppLogger.cache("⟐ undecodable explore home could not be kept aside; it will not be written over", error: error)
            return false
        }
    }
}
