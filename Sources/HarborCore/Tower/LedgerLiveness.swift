import Darwin
import Foundation

/// Answers "is this pid running". Injected so tests need no real process.
public protocol ProcessProbe: Sendable {
    func isAlive(pid: Int) -> Bool
    /// When the process with this pid started, or nil when that can't be read. A pid whose
    /// process started after a session joined is a different process that reused the number.
    func startTime(pid: Int) -> Date?
    /// For each of `worktrees` (normalized paths), the process that works inside it: one whose
    /// current directory is the worktree or below it. A process is listed under the deepest
    /// worktree that holds it. Terminals' shells, `git` and Harbor itself don't count.
    func processes(inside worktrees: [String]) -> [String: ProcessInside]
}

public extension ProcessProbe {
    func startTime(pid _: Int) -> Date? { nil }
    func processes(inside _: [String]) -> [String: ProcessInside] { [:] }
}

/// A running process whose current directory is inside a worktree.
public struct ProcessInside: Equatable, Sendable {
    public let pid: Int
    /// `proc_name`: what Activity Monitor calls it.
    public let name: String
    /// The executable's path, when readable; some agents run under a version number as name.
    public let executable: String?

    public init(pid: Int, name: String, executable: String? = nil) {
        self.pid = pid
        self.name = name
        self.executable = executable
    }

    /// Process names that sit in a directory without being anyone's work there: a shell open in
    /// a terminal, git itself (Tower runs it), and the login/multiplexer plumbing around them.
    static let ignoredNames: Set<String> = [
        "zsh", "bash", "sh", "fish", "dash", "ksh", "tcsh", "csh", "nu", "xonsh", "login", "tmux", "screen",
        "sleep", "cat", "less", "man", "ssh", "sshd", "mdworker", "mds", "Finder", "Harbor", "harborcli"
    ]

    var isIgnored: Bool {
        Self.ignoredNames.contains(self.name) || self.name == "git" || self.name.hasPrefix("git-")
    }

    private static let knownAgents = ["claude", "codex", "cursor", "qwen", "opencode", "ribhu", "gemini", "aider", "copilot"]

    /// The agent the process names, from its name or its executable's path ("claude" for a
    /// binary called `2.1.139` under `.../claude/versions/`); nil when it names none.
    public var agentHint: String? {
        let haystack = ([self.name] + [self.executable].compactMap { $0 }).joined(separator: " ").lowercased()
        return Self.knownAgents.first { haystack.contains($0) }
    }
}

public struct SystemProcessProbe: ProcessProbe {
    public init() {}

    /// `kill(pid, 0)` sends nothing; EPERM means the process exists but belongs to someone else.
    public func isAlive(pid: Int) -> Bool {
        guard pid > 0, pid <= Int(Int32.max) else { return false }
        if kill(pid_t(pid), 0) == 0 { return true }
        return errno == EPERM
    }

    /// `proc_pidinfo(PROC_PIDTBSDINFO)`'s `pbi_start_tvsec`: whole seconds since the epoch.
    public func startTime(pid: Int) -> Date? {
        guard pid > 0, pid <= Int(Int32.max) else { return nil }
        var info = proc_bsdinfo()
        let size = Int32(MemoryLayout<proc_bsdinfo>.size)
        guard proc_pidinfo(pid_t(pid), PROC_PIDTBSDINFO, 0, &info, size) == size else { return nil }
        return Date(timeIntervalSince1970: TimeInterval(info.pbi_start_tvsec))
    }

    /// One pass over the process table with libproc: `proc_listallpids`, then each process's
    /// current directory from `PROC_PIDVNODEPATHINFO`. A process Harbor may not inspect (another
    /// user's) fails the call and is skipped. No `lsof`, nothing kept.
    public func processes(inside worktrees: [String]) -> [String: ProcessInside] {
        guard !worktrees.isEmpty else { return [:] }
        let own = Int(getpid())
        var pids = [pid_t](repeating: 0, count: Int(proc_listallpids(nil, 0)) + 64)
        let listed = Int(proc_listallpids(&pids, Int32(pids.count * MemoryLayout<pid_t>.size)))
        // The kernel reports the physical path (`/private/var/...`), while the caller's paths are
        // Foundation-normalized (`/var/...`): match on the physical form, answer in the caller's.
        // Deepest worktree first, so a process in a nested one is not also credited to its parent.
        let ordered = worktrees.map { (physical: Self.physicalPath($0), key: $0) }.sorted { $0.physical.count > $1.physical.count }
        var found: [String: ProcessInside] = [:]
        for pid in pids.prefix(max(0, listed)) where pid > 0 && Int(pid) != own {
            guard let cwd = Self.currentDirectory(of: pid),
                  let worktree = ordered.first(where: { cwd == $0.physical || cwd.hasPrefix($0.physical + "/") })?.key
            else { continue }
            let process = ProcessInside(pid: Int(pid), name: Self.name(of: pid), executable: Self.executable(of: pid))
            // The same worktree can hold several processes: one that names an agent wins, then the
            // lowest pid, so the pick doesn't flicker between scans.
            func rank(_ item: ProcessInside) -> (Int, Int) { (item.agentHint == nil ? 1 : 0, item.pid) }
            if process.isIgnored || (found[worktree].map { rank($0) <= rank(process) } ?? false) { continue }
            found[worktree] = process
        }
        return found
    }

    private static func physicalPath(_ path: String) -> String {
        guard let resolved = realpath(path, nil) else { return path }
        defer { free(resolved) }
        return String(cString: resolved)
    }

    private static func currentDirectory(of pid: pid_t) -> String? {
        var info = proc_vnodepathinfo()
        let size = Int32(MemoryLayout<proc_vnodepathinfo>.size)
        guard proc_pidinfo(pid, PROC_PIDVNODEPATHINFO, 0, &info, size) == size else { return nil }
        let path = withUnsafePointer(to: &info.pvi_cdir.vip_path) {
            $0.withMemoryRebound(to: CChar.self, capacity: Int(MAXPATHLEN)) { String(cString: $0) }
        }
        return path.isEmpty ? nil : path
    }

    private static func name(of pid: pid_t) -> String {
        var buffer = [CChar](repeating: 0, count: 256)
        guard proc_name(pid, &buffer, UInt32(buffer.count)) > 0 else { return "" }
        return String(bytes: buffer.prefix { $0 != 0 }.map { UInt8(bitPattern: $0) }, encoding: .utf8) ?? ""
    }

    private static func executable(of pid: pid_t) -> String? {
        var buffer = [CChar](repeating: 0, count: Int(MAXPATHLEN) * 4)
        guard proc_pidpath(pid, &buffer, UInt32(buffer.count)) > 0 else { return nil }
        return String(bytes: buffer.prefix { $0 != 0 }.map { UInt8(bitPattern: $0) }, encoding: .utf8) ?? ""
    }
}

/// Why a worktree counts as having a live session.
public enum LiveEvidence: Equatable, Sendable {
    /// The pid on a joining event is running on this host.
    case pid(Int)
    /// No running pid to check (none recorded, another host, or the emitter has exited), and the
    /// join is younger than the window.
    case window
    /// No ledger row: a process (not a shell, not git) is running with its current directory in
    /// the worktree. Weaker than a ledger join: it says something is there, not that it is an agent.
    case process(pid: Int, name: String)
}

public enum LedgerLiveness {
    /// A join with no leave older than this, and no running pid, is a crashed session.
    public static let window: TimeInterval = 24 * 3600
    /// A running pid proves a session only this long after the join, whatever its start time says:
    /// a join this old whose pid still answers is a reused number, not an agent.
    public static let pidAgeBound: TimeInterval = 7 * 24 * 3600
    /// The join's timestamp can be truncated to whole seconds, as can the process start time.
    static let startTimeSlack: TimeInterval = 5

    public static var currentHost: String {
        var buffer = [CChar](repeating: 0, count: 256)
        guard gethostname(&buffer, buffer.count) == 0 else { return "" }
        return String(bytes: buffer.prefix { $0 != 0 }.map { UInt8(bitPattern: $0) }, encoding: .utf8) ?? ""
    }

    /// The strongest evidence that someone is working in the worktree now, or nil.
    ///
    /// A pid that is running on this host proves it, unless it started after the join (a reused
    /// pid) or the join is older than `pidAgeBound`. Everything else falls back to the 24 hour
    /// window: the ledger's `pid` is the process that emitted the event (the short-lived
    /// `wtr.py`/`ledger.py`, `os.getpid()`), not the agent, so a dead pid is not proof of a
    /// crash and must not clear a recent join.
    public static func evidence(
        for row: LedgerWorktree,
        host: String = currentHost,
        now: Date = Date(),
        probe: some ProcessProbe = SystemProcessProbe(),
        window: TimeInterval = window,
        pidAgeBound: TimeInterval = pidAgeBound
    ) -> LiveEvidence? {
        var windowed = false
        for key in row.live.sorted() {
            let session = row.sessions[key]
            if let pid = session?.pid, let sessionHost = session?.host, sessionHost == host,
               Self.pidProvesSession(pid: pid, since: session?.since, now: now, probe: probe, ageBound: pidAgeBound) {
                return .pid(pid)
            }
            if let since = session?.since ?? row.lastEvent, now.timeIntervalSince(since) < window {
                windowed = true
            }
        }
        return windowed ? .window : nil
    }

    private static func pidProvesSession(pid: Int, since: Date?, now: Date, probe: some ProcessProbe, ageBound: TimeInterval) -> Bool {
        guard probe.isAlive(pid: pid) else { return false }
        // A join with no timestamp can't be aged, so it is treated as old: the pid alone is not proof.
        guard let since else { return false }
        if now.timeIntervalSince(since) >= ageBound { return false }
        if let started = probe.startTime(pid: pid), started.timeIntervalSince(since) > startTimeSlack { return false }
        return true
    }
}
