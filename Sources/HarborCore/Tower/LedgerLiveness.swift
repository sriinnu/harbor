import Darwin
import Foundation

/// Answers "is this pid running". Injected so tests need no real process.
public protocol ProcessProbe: Sendable {
    func isAlive(pid: Int) -> Bool
    /// When the process with this pid started, or nil when that can't be read. A pid whose
    /// process started after a session joined is a different process that reused the number.
    func startTime(pid: Int) -> Date?
}

public extension ProcessProbe {
    func startTime(pid _: Int) -> Date? { nil }
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
}

/// Why a worktree counts as having a live session.
public enum LiveEvidence: Equatable, Sendable {
    /// The pid on a joining event is running on this host.
    case pid(Int)
    /// No running pid to check (none recorded, another host, or the emitter has exited), and the
    /// join is younger than the window.
    case window
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
