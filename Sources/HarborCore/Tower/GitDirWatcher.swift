import CoreServices
import Foundation

/// File-level FSEvents on repos' common `.git` directories, and nothing else: never a working
/// tree, whose build output would flood the stream. Events are triggers to recompute a repo,
/// not deltas to apply, so a coalesced or dropped event costs nothing.
public final class GitDirWatcher: @unchecked Sendable {
    private let queue = DispatchQueue(label: "harbor.git-watch")
    private var stream: FSEventStreamRef?
    private let handler: @Sendable (Set<String>) -> Void
    /// `.git` directory (resolved) to the repo path it belongs to.
    private let repoByGitDir: [String: String]

    /// - Parameters:
    ///   - gitDirs: repo path to that repo's absolute common git directory.
    ///   - handler: the repo paths that saw a relevant change, after `latency`.
    public init(gitDirs: [String: String], latency: TimeInterval = 0.5, handler: @escaping @Sendable (Set<String>) -> Void) {
        self.handler = handler
        var map: [String: String] = [:]
        for (repo, dir) in gitDirs { map[Self.resolved(dir)] = repo }
        self.repoByGitDir = map
        guard !map.isEmpty else { return }
        var context = FSEventStreamContext(
            version: 0, info: Unmanaged.passUnretained(self).toOpaque(), retain: nil, release: nil, copyDescription: nil
        )
        let callback: FSEventStreamCallback = { _, info, count, paths, _, _ in
            guard let info else { return }
            let watcher = Unmanaged<GitDirWatcher>.fromOpaque(info).takeUnretainedValue()
            let list = unsafeBitCast(paths, to: NSArray.self) as? [String] ?? []
            watcher.receive(Array(list.prefix(count)))
        }
        let flags = UInt32(kFSEventStreamCreateFlagFileEvents | kFSEventStreamCreateFlagUseCFTypes | kFSEventStreamCreateFlagNoDefer)
        guard let stream = FSEventStreamCreate(
            nil, callback, &context, Array(map.keys) as CFArray,
            FSEventStreamEventId(kFSEventStreamEventIdSinceNow), latency, flags
        ) else { return }
        FSEventStreamSetDispatchQueue(stream, self.queue)
        FSEventStreamStart(stream)
        self.stream = stream
    }

    public func stop() {
        guard let stream = self.stream else { return }
        FSEventStreamStop(stream)
        FSEventStreamInvalidate(stream)
        FSEventStreamRelease(stream)
        self.stream = nil
    }

    deinit { self.stop() }

    private func receive(_ paths: [String]) {
        var repos = Set<String>()
        for path in paths {
            if let gitDir = self.repoByGitDir.keys.first(where: { path == $0 || path.hasPrefix($0 + "/") }),
               Self.isRelevant(path, gitDir: gitDir), let repo = self.repoByGitDir[gitDir] {
                repos.insert(repo)
            }
        }
        if !repos.isEmpty { self.handler(repos) }
    }

    /// Worktree registrations, per-worktree HEAD and index, branch and remote refs, packed-refs,
    /// FETCH_HEAD. Object writes, lock files and reflogs are noise. `objects/` and `logs/` are
    /// matched relative to the watched `.git` directory (and `worktrees/<id>/logs/`), never
    /// anywhere in the absolute path: a repo under `~/work/logs/api` is still a repo.
    static func isRelevant(_ path: String, gitDir: String) -> Bool {
        if path.hasSuffix(".lock") { return false }
        let relative = path.hasPrefix(gitDir + "/") ? String(path.dropFirst(gitDir.count + 1)) : ""
        let parts = relative.split(separator: "/", omittingEmptySubsequences: true)
        if parts.first == "objects" || parts.first == "logs" { return false }
        if parts.count >= 3, parts[0] == "worktrees", parts[2] == "logs" { return false }
        return true
    }

    /// The path as FSEvents reports it: real, so `/var/...` is `/private/var/...` (Foundation's
    /// `resolvingSymlinksInPath` would strip that prefix and never match an event).
    static func resolved(_ path: String) -> String {
        guard let real = realpath(path, nil) else { return path }
        defer { free(real) }
        return String(cString: real)
    }
}
