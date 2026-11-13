import Foundation

/// Builds a repo's worktree list: git for what exists and its state, the ledger and path
/// conventions for who made it. Blocking (spawns git); call it off the main thread.
public struct AgentWorktreeLoader: Sendable {
    public static let maxRows = 8
    /// A join with no matching leave older than this, and no running pid, is a crashed session.
    public static let liveWindow: TimeInterval = LedgerLiveness.window

    private let executableLocator: ExecutableLocator
    private let ledgerURL: URL
    private let home: String
    private let now: Date

    public init(
        executableLocator: ExecutableLocator? = nil,
        ledgerURL: URL = URL(fileURLWithPath: NSHomeDirectory()).appendingPathComponent(".agents/ledger/events.jsonl"),
        home: String = NSHomeDirectory(),
        now: Date = Date()
    ) {
        #if os(macOS)
        self.executableLocator = executableLocator ?? MacOSExecutableLocator()
        #else
        self.executableLocator = executableLocator ?? POSIXExecutableLocator()
        #endif
        self.ledgerURL = ledgerURL
        self.home = home
        self.now = now
    }

    /// nil when git can't list worktrees for `repoURL` (not a repo, no git).
    public func load(repoURL: URL) -> AgentWorktreeSnapshot? {
        guard let git = WorktreeGit(locator: self.executableLocator),
              let raw = git.run(["worktree", "list", "--porcelain"], in: repoURL.path) else { return nil }
        // The first entry is the main checkout, which the repo row already is.
        let linked = GitWorktreePorcelain.parse(raw).dropFirst().filter { !$0.isBare }
        guard !linked.isEmpty else { return AgentWorktreeSnapshot(total: 0, shown: []) }

        let ledger = AgentLedger.replayAll(file: self.ledgerURL)
        let base = self.baseRef(git: git, in: repoURL.path)

        var candidates = linked.map { entry -> Candidate in
            let row = ledger[AgentLedger.normalizedPath(entry.path)]
            let commit = entry.isPrunable ? nil : self.lastCommit(git: git, in: entry.path)
            return Candidate(entry: entry, ledger: row, activity: [row?.lastEvent, commit].compactMap { $0 }.max())
        }
        candidates.sort { lhs, rhs in
            let (lLive, rLive) = (self.isLive(lhs.ledger), self.isLive(rhs.ledger))
            if lLive != rLive { return lLive }
            return (lhs.activity ?? .distantPast) > (rhs.activity ?? .distantPast)
        }

        let shown = candidates.prefix(Self.maxRows).map {
            self.detail($0.entry, ledger: $0.ledger, activity: $0.activity, base: base, git: git)
        }
        return AgentWorktreeSnapshot(total: candidates.count, shown: shown)
    }

    private struct Candidate {
        let entry: GitWorktreeEntry
        let ledger: LedgerWorktree?
        let activity: Date?
    }

    private func isLive(_ row: LedgerWorktree?) -> Bool {
        guard let row else { return false }
        return LedgerLiveness.evidence(for: row, now: self.now) != nil
    }

    private func detail(
        _ entry: GitWorktreeEntry,
        ledger: LedgerWorktree?,
        activity: Date?,
        base: String?,
        git: WorktreeGit
    ) -> AgentWorktree {
        var dirty: Int?
        var ahead: Int?
        var behind: Int?
        if !entry.isPrunable {
            if let status = git.run(["status", "--porcelain=v2", "--branch"], in: entry.path) {
                dirty = status.split(whereSeparator: \.isNewline).count(where: { !$0.hasPrefix("#") })
            }
            let against = base ?? "@{upstream}"
            if let counts = git.run(["rev-list", "--left-right", "--count", "\(against)...HEAD"], in: entry.path) {
                let parts = counts.split(whereSeparator: \.isWhitespace)
                if parts.count == 2, let left = Int(parts[0]), let right = Int(parts[1]) {
                    behind = left
                    ahead = right
                }
            }
        }
        let agent = ledger?.agent ?? AgentWorktrees.agentFromPath(entry.path, home: self.home)
        return AgentWorktree(
            path: URL(fileURLWithPath: entry.path, isDirectory: true),
            branch: entry.branch ?? ledger?.branch,
            agent: agent,
            task: ledger?.task,
            note: ledger?.note,
            isLive: self.isLive(ledger),
            isLocked: entry.isLocked,
            isPrunable: entry.isPrunable,
            dirtyCount: dirty,
            ahead: ahead,
            behind: behind,
            lastActivity: activity
        )
    }

    private func lastCommit(git: WorktreeGit, in path: String) -> Date? {
        guard let out = git.run(["log", "-1", "--format=%ct", "HEAD"], in: path),
              let seconds = TimeInterval(out.trimmingCharacters(in: .whitespacesAndNewlines)) else { return nil }
        return Date(timeIntervalSince1970: seconds)
    }

    /// The branch worktrees are measured against: origin's default, else a local main/master.
    private func baseRef(git: WorktreeGit, in path: String) -> String? {
        if let head = git.run(["symbolic-ref", "-q", "--short", "refs/remotes/origin/HEAD"], in: path)?
            .trimmingCharacters(in: .whitespacesAndNewlines), !head.isEmpty {
            return head
        }
        return ["origin/main", "main", "origin/master", "master"].first {
            git.run(["rev-parse", "--verify", "-q", $0], in: path) != nil
        }
    }
}

/// Runs git without the user's global config or hooks, and without taking optional locks.
private struct WorktreeGit: Sendable {
    let gitURL: URL

    init?(locator: ExecutableLocator) {
        guard let url = locator.locate(executable: "git") else { return nil }
        self.gitURL = url
    }

    /// stdout on exit 0, else nil.
    func run(_ arguments: [String], in directory: String) -> String? {
        let process = Process()
        process.executableURL = self.gitURL
        process.arguments = ["-c", "core.hooksPath=/dev/null", "-c", "core.fsmonitor=false"] + arguments
        process.currentDirectoryURL = URL(fileURLWithPath: directory, isDirectory: true)
        var env = ProcessInfo.processInfo.environment
        env["GIT_CONFIG_GLOBAL"] = "/dev/null"
        env["GIT_CONFIG_NOSYSTEM"] = "1"
        env["GIT_OPTIONAL_LOCKS"] = "0"
        env["GIT_TERMINAL_PROMPT"] = "0"
        process.environment = env
        let out = Pipe()
        process.standardOutput = out
        process.standardError = FileHandle.nullDevice
        process.standardInput = FileHandle.nullDevice
        guard (try? process.run()) != nil else { return nil }
        // Drain before waiting: a big status would otherwise fill the pipe and hang.
        let data = out.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        guard process.terminationStatus == 0 else { return nil }
        return String(data: data, encoding: .utf8)
    }
}
