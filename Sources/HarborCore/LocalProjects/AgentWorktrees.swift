import Foundation

// Worktrees that belong to one repo, with who made them. Git says what exists; the shared
// agent ledger (~/.agents/ledger/events.jsonl, append-only, read-only here) says who is in
// each one and why; path conventions fill in when the ledger has no row. Nothing is cached.

// MARK: - git worktree list --porcelain

public struct GitWorktreeEntry: Equatable, Sendable {
    public let path: String
    public let head: String?
    /// Short branch name (`refs/heads/` stripped); nil when detached.
    public let branch: String?
    public let isDetached: Bool
    public let isBare: Bool
    public let isLocked: Bool
    public let isPrunable: Bool
}

public enum GitWorktreePorcelain {
    /// Blocks are separated by blank lines; the first block is the main worktree.
    public static func parse(_ raw: String) -> [GitWorktreeEntry] {
        var entries: [GitWorktreeEntry] = []
        var path: String?
        var head: String?
        var branch: String?
        var detached = false
        var bare = false
        var locked = false
        var prunable = false

        func flush() {
            if let path {
                entries.append(GitWorktreeEntry(
                    path: path, head: head, branch: branch, isDetached: detached,
                    isBare: bare, isLocked: locked, isPrunable: prunable
                ))
            }
            path = nil; head = nil; branch = nil
            detached = false; bare = false; locked = false; prunable = false
        }

        for line in raw.split(omittingEmptySubsequences: false, whereSeparator: \.isNewline) {
            if line.isEmpty { flush(); continue }
            if line.hasPrefix("worktree ") {
                flush()
                path = String(line.dropFirst("worktree ".count))
            } else if line.hasPrefix("HEAD ") {
                head = String(line.dropFirst("HEAD ".count))
            } else if line.hasPrefix("branch ") {
                let ref = String(line.dropFirst("branch ".count))
                branch = ref.hasPrefix("refs/heads/") ? String(ref.dropFirst("refs/heads/".count)) : ref
            } else if line == "detached" {
                detached = true
            } else if line == "bare" {
                bare = true
            } else if line == "locked" || line.hasPrefix("locked ") {
                locked = true
            } else if line == "prunable" || line.hasPrefix("prunable ") {
                prunable = true
            }
        }
        flush()
        return entries
    }
}

// MARK: - Agent attribution

public enum AgentWorktrees {
    /// Canonical agent name from a ledger `agent` field ("claude-code" is "claude").
    public static func normalizedAgent(_ raw: String?) -> String? {
        guard let value = raw?.trimmingCharacters(in: .whitespaces).lowercased(), !value.isEmpty,
              value != "unknown", !value.contains("/") else { return nil }
        for known in ["claude", "codex", "ribhu", "cursor", "qwen", "opencode"] where value.hasPrefix(known) {
            return known
        }
        return value
    }

    /// Fallback when the ledger has no row: which agent's directory the path sits in.
    public static func agentFromPath(_ path: String, home: String) -> String? {
        // git reports /private/var/... where the caller may say /var/..., so compare both
        // sides in one canonical form.
        let path = AgentLedger.normalizedPath(path)
        let home = AgentLedger.normalizedPath(home)
        let prefix = home.hasSuffix("/") ? home : home + "/"
        if path.hasPrefix(prefix + ".codex/worktrees/") { return "codex" }
        if path.hasPrefix(prefix + ".ribhu/worktrees/") { return "ribhu" }
        if path.hasPrefix(prefix + ".cursor/worktrees/") { return "cursor" }
        if path.contains("/.claude/worktrees/") { return "claude" }
        if path.contains("/.qwen/worktrees/") { return "qwen" }
        if path.hasPrefix(prefix + ".local/share/opencode/worktree/") { return "opencode" }
        // VS Code puts a repo's worktrees in `<parent>/<repo>.worktrees/<name>`. `~/.worktrees`
        // (nothing before the dot) is a plain shared folder: it says nothing about who made them.
        let folders = path.split(separator: "/").dropLast()
        if folders.contains(where: { $0.hasSuffix(".worktrees") && $0.count > ".worktrees".count }) { return "vscode" }
        return nil
    }
}

// MARK: - Ledger

/// One agent session inside a worktree, as the joining event recorded it.
public struct LedgerSession: Equatable, Sendable {
    /// Pid of the process that emitted the event (the ledger CLI), and the host it ran on.
    public var pid: Int?
    public var host: String?
    public var since: Date?
}

public struct LedgerBuild: Equatable, Sendable {
    /// `building`, `ok` or `failed`.
    public var status: String
    public var version: String?
    public var date: Date?
}

public struct LedgerDelivery: Equatable, Sendable {
    public var sha: String?
    public var base: String?
    public var date: Date?
}

public struct LedgerAdvice: Equatable, Sendable {
    public var decision: String?
    public var abandoned: Double?
}

/// An agent that stopped to ask the user something (`agent.waiting`). Only an event can say this.
public struct LedgerWaiting: Equatable, Sendable {
    /// `agent:session` of the emitter: a later event with the same key clears it.
    public var key: String
    public var reason: String?
    public var since: Date?
}

/// One line of a worktree's history, for the detail timeline.
public struct LedgerTimelineEntry: Equatable, Sendable {
    public var date: Date?
    public var event: String
    public var agent: String?
    public var text: String
}

/// What the ledger knows about one worktree path.
public struct LedgerWorktree: Equatable, Sendable {
    public var path: String
    public var repo: String?
    public var agent: String?
    public var task: String?
    public var branch: String?
    /// Latest `worktree.noted` note, else the birth `purpose`.
    public var note: String?
    /// `agent:session` keys that joined and have not left.
    public var live: Set<String> = []
    /// The joining event's pid, host and time for each key in `live`.
    public var sessions: [String: LedgerSession] = [:]
    /// The latest `build.recorded`.
    public var build: LedgerBuild?
    /// The latest `task.delivered`.
    public var delivered: LedgerDelivery?
    /// The reason of the latest `worktree.flagged`.
    public var flagged: String?
    /// The latest `audit.advice`.
    public var advice: LedgerAdvice?
    /// An `agent.waiting` event no later event from the same session has cleared.
    public var waiting: LedgerWaiting?
    /// Newest event for this path.
    public var lastEvent: Date?
    /// Every event since the path was born, oldest first, the newest `maxTimeline` kept.
    public var timeline: [LedgerTimelineEntry] = []

    public static let maxTimeline = 200
}

/// Folds ledger lines into per-worktree state, one line at a time, so a file can be replayed
/// in chunks and then extended from a byte offset. Malformed lines are skipped,
/// `task.retired` drops the path, the latest `worktree.noted` wins. Keyed by standardized path.
public struct LedgerReplayer: Sendable {
    public private(set) var state: [String: LedgerWorktree] = [:]

    public init() {}

    public mutating func ingest(_ line: String) {
        guard let obj = AgentLedger.parseLine(line), let event = obj["event"] as? String,
              let rawPath = obj["worktree"] as? String, !rawPath.isEmpty else { return }
        let key = AgentLedger.normalizedPath(rawPath)
        let rawAgent = obj["agent"] as? String ?? ""
        let session = (obj["session"] as? String) ?? ""
        let data = obj["data"] as? [String: Any] ?? [:]
        let date = (obj["ts"] as? String).flatMap(AgentLedger.parseDate)
        let agent = AgentWorktrees.normalizedAgent(rawAgent)
        let repo = AgentLedger.nonEmpty(obj["repo"] as? String)

        // Any later event from the session that asked is the agent carrying on: it no longer waits.
        let sessionKey = "\(rawAgent):\(session)"
        if event != "agent.waiting", var waiting = self.state[key], waiting.waiting?.key == sessionKey {
            waiting.waiting = nil
            self.state[key] = waiting
        }

        var text: String
        switch event {
        case "task.retired":
            self.state[key] = nil
            return
        case "worktree.born":
            var row = LedgerWorktree(path: key)
            row.repo = repo
            row.agent = agent
            row.task = obj["task"] as? String
            row.branch = obj["branch"] as? String
            row.note = AgentLedger.nonEmpty(data["purpose"] as? String) ?? AgentLedger.nonEmpty(data["name"] as? String)
            self.state[key] = row
            text = "born" + (row.task.map { " for \($0)" } ?? "")
        case "worktree.joined":
            var row = self.state[key] ?? LedgerWorktree(path: key)
            row.repo = row.repo ?? repo
            row.agent = row.agent ?? agent
            row.live.insert(sessionKey)
            row.sessions[sessionKey] = LedgerSession(
                pid: Self.int(obj["pid"]), host: AgentLedger.nonEmpty(obj["host"] as? String), since: date
            )
            self.state[key] = row
            text = "joined"
        case "worktree.left":
            guard var row = self.state[key] else { return }
            let leaving = data["key"] as? String ?? sessionKey
            row.live.remove(leaving)
            row.sessions[leaving] = nil
            // Left, so nobody is waiting here: the session that asked, or the last one out.
            if row.waiting?.key == leaving || row.live.isEmpty { row.waiting = nil }
            self.state[key] = row
            text = "left"
        case "agent.waiting":
            var row = self.state[key] ?? LedgerWorktree(path: key)
            row.repo = row.repo ?? repo
            row.agent = row.agent ?? agent
            let reason = AgentLedger.nonEmpty(data["reason"] as? String)
            row.waiting = LedgerWaiting(key: sessionKey, reason: reason, since: date)
            self.state[key] = row
            text = "waiting" + (reason.map { ": \($0)" } ?? "")
        case "agent.resumed":
            // Cleared above; the event only needs a line in the timeline.
            guard self.state[key] != nil else { return }
            text = "resumed"
        case "worktree.noted":
            var row = self.state[key] ?? LedgerWorktree(path: key)
            row.repo = row.repo ?? repo
            if let note = AgentLedger.nonEmpty(data["note"] as? String) ?? AgentLedger.nonEmpty(data["name"] as? String) {
                row.note = note
            }
            self.state[key] = row
            text = "noted" + (row.note.map { ": \($0)" } ?? "")
        case "build.recorded":
            // A build never creates a row.
            guard var row = self.state[key] else { return }
            let status = AgentLedger.nonEmpty(data["status"] as? String)
            if let status {
                row.build = LedgerBuild(status: status, version: AgentLedger.nonEmpty(data["version"] as? String), date: date)
            }
            self.state[key] = row
            text = "build " + (status ?? "recorded")
        case "task.delivered":
            var row = self.state[key] ?? LedgerWorktree(path: key)
            row.repo = row.repo ?? repo
            row.agent = row.agent ?? agent
            row.task = row.task ?? (obj["task"] as? String)
            let sha = AgentLedger.nonEmpty(data["sha"] as? String)
            row.delivered = LedgerDelivery(sha: sha, base: AgentLedger.nonEmpty(data["base"] as? String), date: date)
            self.state[key] = row
            text = "delivered" + (sha.map { " " + String($0.prefix(7)) } ?? "")
        case "worktree.flagged":
            guard var row = self.state[key] else { return }
            row.flagged = AgentLedger.nonEmpty(data["reason"] as? String) ?? "flagged"
            self.state[key] = row
            text = "flagged: \(row.flagged ?? "")"
        case "audit.advice":
            guard var row = self.state[key] else { return }
            let abandoned = (data["abandoned"] as? [String: Any])?["normalized"] as? Double
            row.advice = LedgerAdvice(decision: AgentLedger.nonEmpty(data["decision"] as? String), abandoned: abandoned)
            self.state[key] = row
            text = "advice: " + (row.advice?.decision ?? "none")
        default:
            return
        }
        guard var row = self.state[key] else { return }
        if let date { row.lastEvent = max(row.lastEvent ?? date, date) }
        row.timeline.append(LedgerTimelineEntry(date: date, event: event, agent: agent, text: text))
        if row.timeline.count > LedgerWorktree.maxTimeline {
            row.timeline.removeFirst(row.timeline.count - LedgerWorktree.maxTimeline)
        }
        self.state[key] = row
    }

    private static func int(_ value: Any?) -> Int? {
        if let number = value as? Int { return number }
        return (value as? String).flatMap(Int.init)
    }
}

public enum AgentLedger {
    /// Replays ledger lines in file order.
    public static func replay(lines: some Sequence<String>) -> [String: LedgerWorktree] {
        var replayer = LedgerReplayer()
        for line in lines { replayer.ingest(line) }
        return replayer.state
    }

    /// Streams the file from `offset` through `replayer` in chunks, never holding more than a
    /// chunk and one partial line. Returns the offset just past the last complete line; a
    /// trailing line with no newline yet is left for the next call. nil when unreadable.
    public static func replay(
        file url: URL,
        from offset: UInt64 = 0,
        into replayer: inout LedgerReplayer,
        chunkSize: Int = 256 * 1024
    ) -> UInt64? {
        guard let handle = try? FileHandle(forReadingFrom: url) else { return nil }
        defer { try? handle.close() }
        guard (try? handle.seek(toOffset: offset)) != nil else { return nil }
        var consumed = offset
        var pending = Data()
        while let chunk = try? handle.read(upToCount: chunkSize), !chunk.isEmpty {
            pending.append(chunk)
            guard let lastNewline = pending.lastIndex(of: 0x0A) else { continue }
            let complete = pending[pending.startIndex ... lastNewline]
            for raw in complete.split(separator: 0x0A, omittingEmptySubsequences: true) {
                if let line = String(data: raw, encoding: .utf8) { replayer.ingest(line) }
            }
            consumed += UInt64(complete.count)
            pending = Data(pending[(lastNewline + 1)...])
        }
        return consumed
    }

    /// The whole file replayed from the start.
    public static func replayAll(file url: URL) -> [String: LedgerWorktree] {
        var replayer = LedgerReplayer()
        _ = self.replay(file: url, into: &replayer)
        return replayer.state
    }

    /// The last `maxBytes` of the file as complete lines (a cut first line is dropped).
    public static func tailLines(of url: URL, maxBytes: Int = 4 * 1024 * 1024) -> [String] {
        guard let handle = try? FileHandle(forReadingFrom: url) else { return [] }
        defer { try? handle.close() }
        guard let size = try? handle.seekToEnd() else { return [] }
        let start = size > UInt64(maxBytes) ? size - UInt64(maxBytes) : 0
        // Read one byte early so a cut that lands exactly on a line start keeps that line.
        guard (try? handle.seek(toOffset: start > 0 ? start - 1 : 0)) != nil,
              let data = try? handle.readToEnd(),
              let text = String(data: data, encoding: .utf8) else { return [] }
        var lines = text.split(separator: "\n", omittingEmptySubsequences: true).map(String.init)
        if start > 0, data.first != 0x0A, !lines.isEmpty { lines.removeFirst() }
        return lines
    }

    public static func normalizedPath(_ path: String) -> String {
        URL(fileURLWithPath: path).resolvingSymlinksInPath().standardizedFileURL.path
    }

    static func parseLine(_ line: String) -> [String: Any]? {
        guard let data = line.data(using: .utf8),
              let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { return nil }
        return obj
    }

    static func nonEmpty(_ value: String?) -> String? {
        guard let value = value?.trimmingCharacters(in: .whitespacesAndNewlines), !value.isEmpty else { return nil }
        return value
    }

    private static let plainDate = Date.ISO8601FormatStyle(timeZoneSeparator: .colon)
    private static let fractionalDate = Date.ISO8601FormatStyle(timeZoneSeparator: .colon, includingFractionalSeconds: true)

    static func parseDate(_ value: String) -> Date? {
        if let date = try? Date(value, strategy: Self.plainDate) { return date }
        if let date = try? Date(value, strategy: Self.fractionalDate) { return date }
        // "Z" and offsets without a colon.
        let loose = ISO8601DateFormatter()
        return loose.date(from: value)
    }
}

// MARK: - Result

public struct AgentWorktree: Equatable, Sendable, Identifiable {
    public var id: String { self.path.path }
    public let path: URL
    public let branch: String?
    /// nil when neither the ledger nor the path says; the UI calls that "you".
    public let agent: String?
    public let task: String?
    public let note: String?
    public let isLive: Bool
    public let isLocked: Bool
    public let isPrunable: Bool
    /// Changed files; nil when status could not be read.
    public let dirtyCount: Int?
    public let ahead: Int?
    public let behind: Int?
    public let lastActivity: Date?
}

public struct AgentWorktreeSnapshot: Equatable, Sendable {
    /// Every linked worktree git reports; `shown` is the newest few, which carry git detail.
    public let total: Int
    public let shown: [AgentWorktree]
    public var hiddenCount: Int { max(0, self.total - self.shown.count) }
}
