import Foundation

/// Removes the cache files older Harbor builds left behind, once. Harbor keeps no caches now,
/// so these are dead weight. Only exact paths Harbor's own code used to create are touched,
/// each named below with the code that made it; nothing is globbed.
enum LegacyCacheCleanup {
    static let doneKey = "Harbor.legacyCachesRemoved.v1"
    /// The UserDefaults key `ContributionCacheStore` wrote the 24-hour heatmap cache to.
    static let contributionDefaultsKey = "ContributionHeatmapCache"

    /// The files and folders to remove, relative to nothing: absolute URLs.
    /// - `Caches/<bundle id>/Cache.db`, `Cache.db-shm`, `Cache.db-wal`, `fsCachedData`:
    ///   the `URLCache` that `URLSession.shared` kept (GraphQL and sign-in calls).
    /// - `Application Support/<bundle id>/RepoDetailCache`: `RepoDetailCacheStore`'s JSON files.
    /// - `Caches/com.onevcat.Kingfisher.ImageCache.HarborAvatars`: the avatar disk cache that
    ///   `ImageCache(name: "HarborAvatars")` created.
    static func targets(library: URL, bundleID: String) -> [URL] {
        let caches = library.appending(path: "Caches", directoryHint: .isDirectory)
        let own = caches.appending(path: bundleID, directoryHint: .isDirectory)
        return [
            own.appending(path: "Cache.db"),
            own.appending(path: "Cache.db-shm"),
            own.appending(path: "Cache.db-wal"),
            own.appending(path: "fsCachedData", directoryHint: .isDirectory),
            library.appending(path: "Application Support", directoryHint: .isDirectory)
                .appending(path: bundleID, directoryHint: .isDirectory)
                .appending(path: "RepoDetailCache", directoryHint: .isDirectory),
            caches.appending(path: "com.onevcat.Kingfisher.ImageCache.HarborAvatars", directoryHint: .isDirectory)
        ]
    }

    /// Runs once per install (guarded by `doneKey`). Returns the paths it removed, for the log.
    @discardableResult
    static func runOnce(
        defaults: UserDefaults = .standard,
        fileManager: FileManager = .default,
        library: URL? = nil,
        bundleID: String = Bundle.main.bundleIdentifier ?? "com.sriinnu.harbor"
    ) -> [String] {
        guard defaults.bool(forKey: self.doneKey) == false else { return [] }
        let root = library ?? fileManager.urls(for: .libraryDirectory, in: .userDomainMask).first
        var removed: [String] = []
        if let root {
            for url in self.targets(library: root, bundleID: bundleID) where fileManager.fileExists(atPath: url.path) {
                if (try? fileManager.removeItem(at: url)) != nil { removed.append(url.path) }
            }
        }
        if defaults.object(forKey: self.contributionDefaultsKey) != nil {
            defaults.removeObject(forKey: self.contributionDefaultsKey)
            removed.append("UserDefaults:\(self.contributionDefaultsKey)")
        }
        defaults.set(true, forKey: self.doneKey)
        return removed
    }
}
