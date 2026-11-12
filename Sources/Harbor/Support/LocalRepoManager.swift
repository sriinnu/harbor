import Foundation
import HarborCore

actor LocalRepoManager {
    private let notifier = LocalSyncNotifier.shared
    private var lastFetchByPath: [String: Date] = [:]

    struct SnapshotResult: Sendable {
        let discoveredCount: Int
        let repoIndex: LocalRepoIndex
        let accessDenied: Bool
    }

    struct SnapshotOptions: Sendable {
        let autoSyncEnabled: Bool
        let fetchInterval: TimeInterval
        let preferredPathsByFullName: [String: String]
        let matchRepoNames: Set<String>
        let forceRescan: Bool
    }

    func snapshot(
        rootPaths: [String],
        rootBookmarks: [String: Data],
        options: SnapshotOptions
    ) async -> SnapshotResult {
        let paths = rootPaths.filter { $0.isEmpty == false }
        guard paths.isEmpty == false else {
            return SnapshotResult(discoveredCount: 0, repoIndex: .empty, accessDenied: false)
        }

        let now = Date()
        var accessDenied = false
        var scopedURLs: [URL] = []
        var found: [URL] = []
        defer {
            for url in scopedURLs { url.stopAccessingSecurityScopedResource() }
        }

        for rootPath in paths {
            let bookmark = rootBookmarks[rootPath]
            let fallbackURL = URL(fileURLWithPath: PathFormatter.expandTilde(rootPath), isDirectory: true)
            let resolvedBookmark = bookmark.flatMap(SecurityScopedBookmark.resolve)
            let scopedURL = resolvedBookmark ?? fallbackURL

            let didStart = scopedURL.startAccessingSecurityScopedResource()
            if didStart { scopedURLs.append(scopedURL) }

            // One folder losing access must not hide the others.
            if bookmark != nil, resolvedBookmark == nil || didStart == false {
                accessDenied = true
                continue
            }

            // Security-scoped bookmarks can resolve to file reference URLs (`/.file/id=…`).
            // FileManager APIs expect a path-based file URL for traversal.
            let rootURL = (scopedURL as NSURL).filePathURL ?? scopedURL
            found += LocalProjectsService().discoverRepoRoots(
                rootURL: rootURL,
                maxDepth: LocalProjectsConstants.defaultMaxDepth
            )
        }

        let repoRoots = LocalProjectsService.dedupedByRealPath(found)

        // Only repos that match a GitHub repo on screen are read; every refresh reads them
        // again, side by side (`snapshotConcurrencyLimit` at a time).
        let matchKeys = Set(options.matchRepoNames.map { $0.lowercased() })
        let refreshRoots = repoRoots.filter { matchKeys.contains($0.lastPathComponent.lowercased()) }

        let fetchTargets = self.fetchTargets(
            repoRoots: refreshRoots,
            fetchInterval: options.fetchInterval,
            now: now
        )

        let refreshedSnapshot = await LocalProjectsService().snapshot(
            repoRoots: refreshRoots,
            autoSyncEnabled: options.autoSyncEnabled,
            includeOnlyRepoNames: nil,
            concurrencyLimit: AppLimits.LocalRepo.snapshotConcurrencyLimit,
            fetchTargets: fetchTargets
        )

        for path in refreshedSnapshot.fetchedPaths {
            self.lastFetchByPath[path.path] = now
        }

        let enrichedRefreshed = refreshedSnapshot.statuses.map { status in
            status.withLastFetch(self.lastFetchByPath[status.path.path])
        }

        for status in refreshedSnapshot.syncAttemptedStatuses {
            await self.notifier.notifySync(for: status)
        }

        let allStatuses = enrichedRefreshed
        return SnapshotResult(
            discoveredCount: repoRoots.count,
            repoIndex: LocalRepoIndex(
                statuses: allStatuses,
                preferredPathsByFullName: options.preferredPathsByFullName
            ),
            accessDenied: accessDenied
        )
    }

    private func needsFetch(for repoURL: URL, now: Date, interval: TimeInterval) -> Bool {
        guard interval > 0 else { return false }
        let lastFetch = self.lastFetchByPath[repoURL.path]
        guard let lastFetch else { return true }
        return now.timeIntervalSince(lastFetch) >= interval
    }

    private func fetchTargets(
        repoRoots: [URL],
        fetchInterval: TimeInterval,
        now: Date
    ) -> Set<URL> {
        guard fetchInterval > 0 else { return [] }
        return Set(repoRoots.filter { self.needsFetch(for: $0, now: now, interval: fetchInterval) })
    }
}
