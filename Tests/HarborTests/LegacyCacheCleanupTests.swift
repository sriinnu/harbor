import Foundation
@testable import Harbor
import Testing

struct LegacyCacheCleanupTests {
    private func makeLibrary() throws -> URL {
        let root = FileManager.default.temporaryDirectory.appending(path: "HarborCleanup-\(UUID().uuidString)", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        return root
    }

    private func touch(_ url: URL, directory: Bool = false) throws {
        if directory {
            try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
            try Data("x".utf8).write(to: url.appending(path: "entry"))
        } else {
            try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
            try Data("x".utf8).write(to: url)
        }
    }

    @Test
    func targets_areExactlyTheKnownPaths() {
        let library = URL(filePath: "/L", directoryHint: .isDirectory)
        #expect(LegacyCacheCleanup.targets(library: library, bundleID: "com.sriinnu.harbor").map(\.path) == [
            "/L/Caches/com.sriinnu.harbor/Cache.db",
            "/L/Caches/com.sriinnu.harbor/Cache.db-shm",
            "/L/Caches/com.sriinnu.harbor/Cache.db-wal",
            "/L/Caches/com.sriinnu.harbor/fsCachedData",
            "/L/Application Support/com.sriinnu.harbor/RepoDetailCache",
            "/L/Caches/com.onevcat.Kingfisher.ImageCache.HarborAvatars"
        ])
    }

    @Test
    func runOnce_removesOnlyThoseFiles_andOnlyOnce() throws {
        let library = try makeLibrary()
        defer { try? FileManager.default.removeItem(at: library) }
        let defaults = try #require(UserDefaults(suiteName: "HarborCleanup-\(UUID().uuidString)"))
        let own = library.appending(path: "Caches/com.sriinnu.harbor")
        for name in ["Cache.db", "Cache.db-shm", "Cache.db-wal"] { try touch(own.appending(path: name)) }
        try touch(own.appending(path: "fsCachedData"), directory: true)
        try touch(own.appending(path: "org.sparkle-project.Sparkle/keep"))
        try touch(library.appending(path: "Application Support/com.sriinnu.harbor/RepoDetailCache"), directory: true)
        try touch(library.appending(path: "Application Support/com.sriinnu.harbor/settings.json"))
        try touch(library.appending(path: "Caches/com.onevcat.Kingfisher.ImageCache.HarborAvatars"), directory: true)
        try touch(library.appending(path: "Caches/com.onevcat.Kingfisher.ImageCache.Other"), directory: true)
        defaults.set(Data("old".utf8), forKey: LegacyCacheCleanup.contributionDefaultsKey)

        let removed = LegacyCacheCleanup.runOnce(defaults: defaults, library: library, bundleID: "com.sriinnu.harbor")
        let relative = removed.map { $0.replacingOccurrences(of: library.path + "/", with: "") }
        #expect(relative == [
            "Caches/com.sriinnu.harbor/Cache.db",
            "Caches/com.sriinnu.harbor/Cache.db-shm",
            "Caches/com.sriinnu.harbor/Cache.db-wal",
            "Caches/com.sriinnu.harbor/fsCachedData",
            "Application Support/com.sriinnu.harbor/RepoDetailCache",
            "Caches/com.onevcat.Kingfisher.ImageCache.HarborAvatars",
            "UserDefaults:ContributionHeatmapCache"
        ])
        let fm = FileManager.default
        #expect(fm.fileExists(atPath: own.appending(path: "org.sparkle-project.Sparkle/keep").path))
        #expect(fm.fileExists(atPath: library.appending(path: "Application Support/com.sriinnu.harbor/settings.json").path))
        #expect(fm.fileExists(atPath: library.appending(path: "Caches/com.onevcat.Kingfisher.ImageCache.Other").path))
        #expect(defaults.object(forKey: LegacyCacheCleanup.contributionDefaultsKey) == nil)

        // Second launch: the flag is set, so a file that appears later is left alone.
        try touch(own.appending(path: "Cache.db"))
        #expect(LegacyCacheCleanup.runOnce(defaults: defaults, library: library, bundleID: "com.sriinnu.harbor").isEmpty)
        #expect(fm.fileExists(atPath: own.appending(path: "Cache.db").path))
    }
}
