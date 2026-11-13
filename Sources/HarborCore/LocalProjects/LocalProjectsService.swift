import Foundation

public struct LocalProjectsSnapshot: Equatable, Sendable {
    public let discoveredRepoCount: Int
    public let statuses: [LocalRepoStatus]
    public let syncedStatuses: [LocalRepoStatus]
    public let syncAttemptedStatuses: [LocalRepoStatus]
    public let fetchedPaths: Set<URL>

    public init(
        discoveredRepoCount: Int,
        statuses: [LocalRepoStatus],
        syncedStatuses: [LocalRepoStatus],
        syncAttemptedStatuses: [LocalRepoStatus] = [],
        fetchedPaths: Set<URL> = []
    ) {
        self.discoveredRepoCount = discoveredRepoCount
        self.statuses = statuses
        self.syncedStatuses = syncedStatuses
        self.syncAttemptedStatuses = syncAttemptedStatuses
        self.fetchedPaths = fetchedPaths
    }
}

public struct LocalProjectsService: Sendable {
    private let executableLocator: ExecutableLocator

    /// Initialize with a custom executable locator (for testing or cross-platform use)
    public init(executableLocator: ExecutableLocator) {
        self.executableLocator = executableLocator
    }

    /// Initialize with default executable locator (backward compatibility)
    public init() {
        #if os(macOS)
        self.executableLocator = MacOSExecutableLocator()
        #elseif os(Linux)
        self.executableLocator = POSIXExecutableLocator()
        #else
        self.executableLocator = MockExecutableLocator(path: nil)
        #endif
    }

    public func gitExecutableInfo() -> GitExecutableInfo {
        guard let url = executableLocator.locate(executable: "git") else {
            return GitExecutableInfo(
                path: "not found",
                version: nil,
                error: "Git executable not found",
                isSandboxed: executableLocator.isSandboxed
            )
        }
        let (version, error) = executableLocator.version(at: url)
        return GitExecutableInfo(
            path: url.path,
            version: version,
            error: error,
            isSandboxed: executableLocator.isSandboxed
        )
    }

    /// Static method for backward compatibility
    public static func gitExecutableInfo() -> GitExecutableInfo {
        LocalProjectsService().gitExecutableInfo()
    }

    public func discoverRepoRoots(
        rootPath: String,
        maxDepth: Int = LocalProjectsConstants.defaultMaxDepth
    ) -> [URL] {
        let fileManager = FileManager.default
        let expandedRoot = PathFormatter.expandTilde(rootPath)
        let rootURL = URL(fileURLWithPath: expandedRoot, isDirectory: true)
        return self.discoverRepoRoots(rootURL: rootURL, maxDepth: maxDepth, fileManager: fileManager)
    }

    /// Scans every folder, skipping ones that are missing, and drops repositories reached
    /// through more than one folder (overlapping roots, symlinks).
    public func discoverRepoRoots(
        rootPaths: [String],
        maxDepth: Int = LocalProjectsConstants.defaultMaxDepth
    ) -> [URL] {
        let found = rootPaths.flatMap { self.discoverRepoRoots(rootPath: $0, maxDepth: maxDepth) }
        return Self.dedupedByRealPath(found)
    }

    /// Keeps the first URL for each resolved real path, preserving order.
    public static func dedupedByRealPath(_ urls: [URL]) -> [URL] {
        var seen = Set<String>()
        return urls.filter { seen.insert($0.resolvingSymlinksInPath().standardizedFileURL.path).inserted }
    }

    public func discoverRepoRoots(
        rootURL: URL,
        maxDepth: Int = LocalProjectsConstants.defaultMaxDepth
    ) -> [URL] {
        self.discoverRepoRoots(rootURL: rootURL, maxDepth: maxDepth, fileManager: .default)
    }

    private func discoverRepoRoots(rootURL: URL, maxDepth: Int, fileManager: FileManager) -> [URL] {
        let rootURL = (rootURL as NSURL).filePathURL ?? rootURL
        var isDirectory: ObjCBool = false
        guard fileManager.fileExists(atPath: rootURL.path, isDirectory: &isDirectory),
              isDirectory.boolValue
        else {
            return []
        }
        return self.findGitRepos(in: rootURL, maxDepth: max(0, maxDepth), fileManager: fileManager)
    }

    public func snapshot(
        rootPath: String,
        maxDepth: Int = LocalProjectsConstants.defaultMaxDepth,
        autoSyncEnabled: Bool,
        maxRepoCount: Int? = nil,
        includeOnlyRepoNames: Set<String>? = nil,
        concurrencyLimit: Int = LocalProjectsConstants.defaultSnapshotConcurrencyLimit
    ) async -> LocalProjectsSnapshot {
        let repos = self.discoverRepoRoots(rootPath: rootPath, maxDepth: maxDepth)
        return await self.snapshot(
            repoRoots: repos,
            autoSyncEnabled: autoSyncEnabled,
            maxRepoCount: maxRepoCount,
            includeOnlyRepoNames: includeOnlyRepoNames,
            concurrencyLimit: concurrencyLimit
        )
    }

    public func snapshot(
        rootPaths: [String],
        maxDepth: Int = LocalProjectsConstants.defaultMaxDepth,
        autoSyncEnabled: Bool,
        maxRepoCount: Int? = nil,
        includeOnlyRepoNames: Set<String>? = nil,
        concurrencyLimit: Int = LocalProjectsConstants.defaultSnapshotConcurrencyLimit
    ) async -> LocalProjectsSnapshot {
        let repos = self.discoverRepoRoots(rootPaths: rootPaths, maxDepth: maxDepth)
        return await self.snapshot(
            repoRoots: repos,
            autoSyncEnabled: autoSyncEnabled,
            maxRepoCount: maxRepoCount,
            includeOnlyRepoNames: includeOnlyRepoNames,
            concurrencyLimit: concurrencyLimit
        )
    }

    public func snapshot(
        repoRoots: [URL],
        autoSyncEnabled: Bool,
        maxRepoCount: Int? = nil,
        includeOnlyRepoNames: Set<String>? = nil,
        concurrencyLimit: Int = LocalProjectsConstants.defaultSnapshotConcurrencyLimit,
        fetchTargets: Set<URL> = []
    ) async -> LocalProjectsSnapshot {
        let git = GitRunner(executableLocator: executableLocator)

        guard repoRoots.isEmpty == false else {
            return LocalProjectsSnapshot(discoveredRepoCount: 0, statuses: [], syncedStatuses: [], fetchedPaths: [])
        }

        let filtered = includeOnlyRepoNames.map { allowList in
            repoRoots.filter { allowList.contains($0.lastPathComponent) }
        } ?? repoRoots

        let limitedRepos: [URL] = if let maxRepoCount, maxRepoCount > 0 {
            Array(filtered.prefix(maxRepoCount))
        } else {
            filtered
        }

        let chunkSize = max(1, concurrencyLimit)
        let chunks = stride(from: 0, to: limitedRepos.count, by: chunkSize).map { start in
            Array(limitedRepos[start ..< min(start + chunkSize, limitedRepos.count)])
        }

        struct Processed {
            let status: LocalRepoStatus
            let didSync: Bool
            let didSyncAttempt: Bool
            let didFetch: Bool
        }

        func loadStatus(at repoURL: URL) -> LocalRepoStatus? {
            let branch = currentBranch(at: repoURL, git: git)
            let statusOutput = statusOutput(at: repoURL, git: git)
            let isClean = statusOutput?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ?? false
            let dirtyCounts = statusOutput.flatMap(parseDirtyCounts(from:))
            let dirtyFiles = statusOutput.map { parseDirtyFiles(from: $0, limit: LocalProjectsConstants.dirtyFileLimit) } ?? []
            let (ahead, behind) = aheadBehind(at: repoURL, git: git)
            let syncState = LocalSyncState.resolve(isClean: isClean, ahead: ahead, behind: behind)
            let remote = remoteInfo(at: repoURL, git: git)
            let repoName = remote?.name ?? repoURL.lastPathComponent
            let fullName = remote?.fullName
            let worktreeName = worktreeName(at: repoURL)
            let upstreamBranch = upstreamBranch(at: repoURL, git: git)
            return LocalRepoStatus(
                path: repoURL,
                name: repoName,
                fullName: fullName,
                branch: branch,
                isClean: isClean,
                aheadCount: ahead,
                behindCount: behind,
                syncState: syncState,
                dirtyCounts: dirtyCounts,
                dirtyFiles: dirtyFiles,
                worktreeName: worktreeName,
                upstreamBranch: upstreamBranch
            )
        }

        func fetchPrune(at repoURL: URL) -> Bool {
            (try? git.run(["fetch", "--prune"], in: repoURL)) != nil
        }

        func pullFastForward(at repoURL: URL) -> Bool {
            (try? git.run(["pull", "--ff-only"], in: repoURL)) != nil
        }

        func headSHA(at repoURL: URL) -> String? {
            (try? git.run(["rev-parse", "HEAD"], in: repoURL))
                .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
        }

        var processed: [Processed] = []
        processed.reserveCapacity(limitedRepos.count)

        for chunk in chunks {
            await withTaskGroup(of: Processed?.self) { group in
                for repoURL in chunk {
                    // Each repo's git work (a fetch can take minutes) runs on its own thread, not
                    // on the cooperative pool, so a slow remote can't stall the rest of the app.
                    group.addTask {
                        await Blocking.run(qos: .utility) {
                            guard var status = loadStatus(at: repoURL) else { return nil }
                            var didSync = false
                            var didSyncAttempt = false
                            var didFetch = false
                            if fetchTargets.contains(repoURL) {
                                didFetch = fetchPrune(at: repoURL)
                                if didFetch {
                                    status = loadStatus(at: repoURL) ?? status
                                }
                            }
                            if autoSyncEnabled, fetchTargets.contains(repoURL), status.isClean, status.branch != "detached" {
                                let before = headSHA(at: repoURL)
                                if pullFastForward(at: repoURL) {
                                    didSyncAttempt = true
                                    let after = headSHA(at: repoURL)
                                    if let before, let after, before != after {
                                        didSync = true
                                        status = loadStatus(at: repoURL) ?? status
                                    }
                                }
                            }
                            return Processed(status: status, didSync: didSync, didSyncAttempt: didSyncAttempt, didFetch: didFetch)
                        }
                    }
                }

                for await item in group {
                    if let item {
                        processed.append(item)
                    }
                }
            }
        }

        var statuses = processed.map(\.status)
        let syncedStatuses = processed.filter(\.didSync).map(\.status)
        let syncAttemptedStatuses = processed.filter(\.didSyncAttempt).map(\.status)
        let fetchedPaths = Set(processed.filter(\.didFetch).map(\.status.path))

        statuses.sort { lhs, rhs in
            if lhs.displayName != rhs.displayName { return lhs.displayName < rhs.displayName }
            return lhs.path.path < rhs.path.path
        }

        return LocalProjectsSnapshot(
            discoveredRepoCount: repoRoots.count,
            statuses: statuses,
            syncedStatuses: syncedStatuses,
            syncAttemptedStatuses: syncAttemptedStatuses,
            fetchedPaths: fetchedPaths
        )
    }

    private func findGitRepos(in root: URL, maxDepth: Int, fileManager: FileManager) -> [URL] {
        var results: [URL] = []

        func scan(_ url: URL, depth: Int) {
            if self.isGitRepo(url, fileManager: fileManager) {
                results.append(url)
                return
            }

            guard depth < maxDepth else { return }

            let children: [URL]
            do {
                children = try fileManager.contentsOfDirectory(
                    at: url,
                    includingPropertiesForKeys: [.isDirectoryKey, .isSymbolicLinkKey],
                    options: [.skipsHiddenFiles]
                )
            } catch {
                return
            }

            for child in children {
                let name = child.lastPathComponent
                if name.hasPrefix(".") { continue }

                let values = try? child.resourceValues(forKeys: [.isDirectoryKey, .isSymbolicLinkKey])
                if values?.isSymbolicLink == true { continue }
                guard values?.isDirectory == true else { continue }

                scan(child, depth: depth + 1)
            }
        }

        scan(root, depth: 0)
        return results
    }

    private func isGitRepo(_ url: URL, fileManager: FileManager) -> Bool {
        let gitURL = url.appendingPathComponent(".git")
        return fileManager.fileExists(atPath: gitURL.path)
    }
}

private struct GitRunner: Sendable {
    /// Long enough for a slow fetch, short enough that a stuck git never freezes a refresh.
    private static let timeout: TimeInterval = 120

    private let executableLocator: ExecutableLocator

    init(executableLocator: ExecutableLocator) {
        self.executableLocator = executableLocator
    }

    func run(_ arguments: [String], in directory: URL) throws -> String {
        guard let gitURL = executableLocator.locate(executable: "git") else {
            throw GitRunnerError.executableNotFound
        }
        let result = try GitProcess.run(gitURL: gitURL, arguments: arguments, in: directory, timeout: Self.timeout)
        if result.status != 0 {
            throw GitRunnerError.commandFailed(output: result.stdout, error: result.stderr)
        }
        return result.stdout
    }
}

private enum GitRunnerError: Error {
    case commandFailed(output: String, error: String)
    case executableNotFound
}

private struct GitRemote: Sendable {
    let host: String
    let owner: String
    let name: String

    var fullName: String { "\(self.owner)/\(self.name)" }

    static func parse(_ value: String) -> GitRemote? {
        if value.contains("://") {
            return self.parseURL(value)
        }
        return self.parseScp(value)
    }

    private static func parseURL(_ value: String) -> GitRemote? {
        guard let url = URL(string: value),
              let host = url.host
        else { return nil }
        let parts = url.path.split(separator: "/").map(String.init)
        guard parts.count >= 2 else { return nil }
        let owner = parts[parts.count - 2]
        let name = self.stripGitSuffix(parts.last ?? "")
        return GitRemote(host: host, owner: owner, name: name)
    }

    private static func parseScp(_ value: String) -> GitRemote? {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        let parts = trimmed.split(separator: ":", maxSplits: 1).map(String.init)
        guard parts.count == 2 else { return nil }
        let hostPart = parts[0].split(separator: "@").last.map(String.init) ?? parts[0]
        let path = parts[1]
        let pathParts = path.split(separator: "/").map(String.init)
        guard pathParts.count >= 2 else { return nil }
        let owner = pathParts[pathParts.count - 2]
        let name = self.stripGitSuffix(pathParts.last ?? "")
        return GitRemote(host: hostPart, owner: owner, name: name)
    }

    private static func stripGitSuffix(_ value: String) -> String {
        value.hasSuffix(".git") ? String(value.dropLast(4)) : value
    }
}

private func currentBranch(at repoURL: URL, git: GitRunner) -> String {
    guard let raw = try? git.run(["rev-parse", "--abbrev-ref", "HEAD"], in: repoURL) else {
        return "unknown"
    }
    let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
    return trimmed == "HEAD" ? "detached" : trimmed
}

private func statusOutput(at repoURL: URL, git: GitRunner) -> String? {
    try? git.run(["status", "--porcelain"], in: repoURL)
}

private func parseDirtyCounts(from output: String) -> LocalDirtyCounts? {
    var added: Set<String> = []
    var modified: Set<String> = []
    var deleted: Set<String> = []

    for rawLine in output.split(whereSeparator: \.isNewline) {
        let line = String(rawLine)
        guard line.count >= 3 else { continue }
        let status = String(line.prefix(2))
        var path = String(line.dropFirst(3)).trimmingCharacters(in: .whitespacesAndNewlines)
        if let arrowRange = path.range(of: " -> ") {
            path = String(path[arrowRange.upperBound...])
        }
        guard path.isEmpty == false else { continue }

        if status == "??" {
            added.insert(path)
            continue
        }

        if status.contains("D") {
            deleted.insert(path)
            continue
        }

        if status.contains("A") {
            added.insert(path)
            continue
        }

        if status.contains("M") || status.contains("R") || status.contains("C") || status.contains("T") || status.contains("U") {
            modified.insert(path)
        }
    }

    if added.isEmpty, modified.isEmpty, deleted.isEmpty { return nil }
    return LocalDirtyCounts(added: added.count, modified: modified.count, deleted: deleted.count)
}

private func parseDirtyFiles(from output: String, limit: Int) -> [String] {
    guard limit > 0 else { return [] }
    var files: [String] = []
    files.reserveCapacity(limit)

    for rawLine in output.split(whereSeparator: \.isNewline) {
        guard files.count < limit else { break }
        let line = String(rawLine)
        guard line.count >= 3 else { continue }
        let status = String(line.prefix(2))
        var path = String(line.dropFirst(3)).trimmingCharacters(in: .whitespacesAndNewlines)
        if let arrowRange = path.range(of: " -> ") {
            path = String(path[arrowRange.upperBound...])
        }
        guard path.isEmpty == false else { continue }
        let isDirtyStatus = status == "??"
            || status.contains("M")
            || status.contains("A")
            || status.contains("D")
            || status.contains("R")
            || status.contains("C")
            || status.contains("T")
            || status.contains("U")
        if isDirtyStatus {
            files.append(path)
        }
    }

    return files
}

private func aheadBehind(at repoURL: URL, git: GitRunner) -> (ahead: Int?, behind: Int?) {
    guard let output = try? git.run(["rev-list", "--left-right", "--count", "@{u}...HEAD"], in: repoURL) else {
        return (nil, nil)
    }
    let parts = output.split(whereSeparator: { $0 == " " || $0 == "\t" || $0 == "\n" })
    guard parts.count >= 2,
          let behind = Int(parts[0]),
          let ahead = Int(parts[1])
    else { return (nil, nil) }
    return (ahead, behind)
}

private func remoteInfo(at repoURL: URL, git: GitRunner) -> GitRemote? {
    guard let raw = try? git.run(["remote", "get-url", "origin"], in: repoURL) else {
        return nil
    }
    return GitRemote.parse(raw.trimmingCharacters(in: .whitespacesAndNewlines))
}

private func upstreamBranch(at repoURL: URL, git: GitRunner) -> String? {
    guard let raw = try? git.run(["rev-parse", "--abbrev-ref", "--symbolic-full-name", "@{u}"], in: repoURL) else {
        return nil
    }
    let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
    return trimmed.isEmpty ? nil : trimmed
}

private func worktreeName(at repoURL: URL) -> String? {
    let gitPath = repoURL.appendingPathComponent(".git")
    var isDirectory: ObjCBool = false
    guard FileManager.default.fileExists(atPath: gitPath.path, isDirectory: &isDirectory),
          isDirectory.boolValue == false
    else {
        return nil
    }
    guard let contents = try? String(contentsOf: gitPath, encoding: .utf8) else { return nil }
    guard let range = contents.range(of: "worktrees/") else { return nil }
    let suffix = contents[range.upperBound...]
    let name = suffix.split(whereSeparator: { $0 == "\n" || $0 == "\r" || $0 == "/" }).first
    return name.map(String.init)
}
