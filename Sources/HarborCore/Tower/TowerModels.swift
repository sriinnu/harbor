import Foundation

public enum TowerLane: Int, CaseIterable, Sendable {
    case needsYou, working, ready, inReview, leftovers

    public var title: String {
        switch self {
        case .needsYou: "Needs you"
        case .working: "Working"
        case .ready: "Ready"
        case .inReview: "In review"
        case .leftovers: "Leftovers"
        }
    }
}

/// Everything lane assignment looks at, so the rules are testable without git or a ledger.
public struct TowerFacts: Equatable, Sendable {
    public var isPrunable = false
    public var live: LiveEvidence?
    public var buildStatus: String?
    public var isDelivered = false
    public var hasOpenPull = false
    public var ahead: Int?
    public var behind: Int?
    public var dirty: Int?
    public var forecast: MergeForecast?
    /// Days since the newest ledger event or commit; nil when unknown.
    public var idleDays: Int?
    /// An unanswered `agent.waiting` event: the one thing that may say the agent waits on the user.
    public var waiting: LedgerWaiting?

    public init(
        isPrunable: Bool = false, live: LiveEvidence? = nil, buildStatus: String? = nil,
        isDelivered: Bool = false, hasOpenPull: Bool = false, ahead: Int? = nil, behind: Int? = nil,
        dirty: Int? = nil, forecast: MergeForecast? = nil, idleDays: Int? = nil, waiting: LedgerWaiting? = nil
    ) {
        self.waiting = waiting
        self.isPrunable = isPrunable
        self.live = live
        self.buildStatus = buildStatus
        self.isDelivered = isDelivered
        self.hasOpenPull = hasOpenPull
        self.ahead = ahead
        self.behind = behind
        self.dirty = dirty
        self.forecast = forecast
        self.idleDays = idleDays
    }
}

public enum TowerLanes {
    /// A worktree nobody is in and nothing has touched for this long is debris, whatever else is true of it.
    public static let staleAfterDays = 14
    /// A conflict with main only needs you while the work is fresh; after this it is a leftover
    /// that happens to conflict.
    public static let conflictQuietDays = 3

    /// First matching rule wins; the reason is the sentence the row shows.
    public static func assign(_ facts: TowerFacts) -> (lane: TowerLane, reason: String) {
        if facts.isPrunable { return (.leftovers, "missing on disk") }
        if facts.buildStatus == "failed", !facts.isDelivered { return (.needsYou, "build failed") }
        // Asked, and not answered: the agent stopped for the user. That only holds while the one
        // who asked can still answer: a session the ledger still counts as live (a running pid, or
        // a join inside the 24 hour window), or an ask made within the last day. A crashed session
        // never sends `worktree.left`, so an older ask with nobody inside is not waiting on you.
        if let waiting = facts.waiting, facts.live != nil || (facts.idleDays ?? 0) < 1 {
            return (.needsYou, "waiting on you" + (waiting.reason.map { ": \($0)" } ?? ""))
        }
        if case let .process(_, name) = facts.live, facts.buildStatus != "building" { return (.working, name.isEmpty ? "process inside" : "process inside: \(name)") }
        if facts.live != nil { return (.working, facts.buildStatus == "building" ? "building" : "agent inside") }
        if let idle = facts.idleDays, idle >= Self.staleAfterDays { return (.leftovers, "idle \(idle)d") }
        if case let .conflicts(files) = facts.forecast, (facts.ahead ?? 0) > 0, !facts.isDelivered {
            let count = max(files.count, 1)
            let sentence = "would conflict with main in \(count) file\(count == 1 ? "" : "s")"
            if let idle = facts.idleDays, idle >= Self.conflictQuietDays { return (.leftovers, "\(sentence), idle \(idle)d") }
            return (.needsYou, sentence)
        }
        if facts.isDelivered { return (.leftovers, "delivered") }
        if facts.hasOpenPull { return (.inReview, "pull request open") }
        if let ahead = facts.ahead, ahead > 0, facts.dirty == 0 {
            // `.unknown` means git could not say, which is not the same as clean: it isn't
            // Ready until someone looks.
            if case .unknown = facts.forecast { return (.needsYou, "\(ahead) ahead, couldn't check merge with main") }
            // No forecast yet (still working it out, or git too old to make one) with main
            // ahead of this branch is not "clean" either, but it needn't pull you in: Ready.
            if facts.forecast == nil, (facts.behind ?? 0) > 0 { return (.ready, "\(ahead) ahead, merge not checked yet") }
            return (.ready, "\(ahead) ahead, clean")
        }
        if let dirty = facts.dirty, dirty > 0 { return (.leftovers, "\(dirty) uncommitted") }
        if facts.ahead == 0 { return (.leftovers, "nothing ahead of main") }
        return (.leftovers, "idle")
    }
}

public struct TowerRow: Identifiable, Equatable, Sendable {
    public var id: String { self.path }
    public let repoPath: String
    public let repoName: String
    public let path: String
    public let branch: String?
    public let agent: String?
    public let task: String?
    public let note: String?
    public let evidence: LiveEvidence?
    public let build: LedgerBuild?
    public let delivered: LedgerDelivery?
    public let advice: LedgerAdvice?
    public let isLocked: Bool
    public let isPrunable: Bool
    public let ahead: Int?
    public let behind: Int?
    public let dirty: Int?
    public let forecast: MergeForecast?
    /// Files this worktree shares with another live worktree of the same repo.
    public let collisions: [String]
    public let lastActivity: Date?
    public let timeline: [LedgerTimelineEntry]
    public let lane: TowerLane
    public let reason: String
    /// The unanswered `agent.waiting` event, if any.
    public var waiting: LedgerWaiting?
    /// When something in the worktree last changed (files, index, HEAD); read only for rows with
    /// a process inside and no ledger, to guess "idle".
    public var lastChange: Date?
    /// The uncommitted paths seen at scan time (for a row with a process inside only), so the
    /// idle guess can look at them again when it is shown instead of trusting `lastChange`.
    public var dirtyPaths: [String] = []
    /// The process inside names an agent (claude, codex, ...). The idle guess needs it: a language
    /// server or dev server sitting in a worktree is not an agent that may be waiting.
    public var processNamesAgent = false

    /// Who made it: the ledger, else the path's convention, else the process inside, else "unknown".
    public var agentLabel: String { self.agent ?? "unknown" }

    /// Minutes with nothing changing in a worktree an agent process sits in, once past `TowerIdle.threshold`.
    /// nil when the ledger speaks for the row (an event says waiting, or the ledger says who is in),
    /// when the process inside names no agent, when nothing is inside, or when no change time could
    /// be read. `lastChange` is only the scan's reading and scans follow `.git` events, so before
    /// the guess shows, the files are looked at again (`changeNow`); the newer time wins.
    public func idleMinutes(
        now: Date = Date(),
        changeNow: (TowerRow) -> Date? = { TowerIdle.lastChange(worktree: $0.path, dirtyPaths: $0.dirtyPaths) }
    ) -> Int? {
        guard self.waiting == nil, case .process = self.evidence, self.processNamesAgent, var last = self.lastChange else { return nil }
        // Cheap first: a scan-time change that is already recent needs no second look.
        guard now.timeIntervalSince(last) >= TowerIdle.threshold else { return nil }
        if let fresh = changeNow(self), fresh > last { last = fresh }
        let idle = now.timeIntervalSince(last)
        return idle >= TowerIdle.threshold ? Int(idle / 60) : nil
    }

    /// The row's sentence: the lane reason, with the idle guess added while it holds.
    public func reasonText(now: Date = Date()) -> String {
        guard let minutes = self.idleMinutes(now: now) else { return self.reason }
        return "\(self.reason), idle \(minutes)m — maybe waiting"
    }
}

/// One repo's worktrees. `phase` says how much has been worked out so far, so the view can
/// paint the cheap parts first.
public struct TowerRepoSnapshot: Equatable, Sendable, Identifiable {
    public enum Phase: Int, Sendable { case listed, counted, detailed, forecast }

    public var id: String { self.path }
    public let path: String
    public let name: String
    public let base: String?
    public let rows: [TowerRow]
    public let collisions: [FileCollision]
    public let phase: Phase
    /// When the repo last fetched, as far as the files git leaves say; nil when unknown or when
    /// the base is a local branch. The forecast is against the base as of that moment.
    public let fetchedAt: Date?

    public init(
        path: String, name: String, base: String?, rows: [TowerRow], collisions: [FileCollision],
        phase: Phase, fetchedAt: Date? = nil
    ) {
        self.path = path
        self.name = name
        self.base = base
        self.rows = rows
        self.collisions = collisions
        self.phase = phase
        self.fetchedAt = fetchedAt
    }

    /// "last fetch 3d ago": how stale the forecast's base is. It is the repo's last fetch of any
    /// remote, from any of its worktrees, so it does not claim to be about `origin/main` alone.
    /// nil for a local base.
    public func fetchText(now: Date = Date()) -> String? {
        guard let base, base.contains("/") else { return nil }
        guard let fetchedAt else { return "last fetch unknown" }
        let seconds = max(0, Int(now.timeIntervalSince(fetchedAt)))
        switch seconds {
        case ..<60: return "last fetch just now"
        case ..<3600: return "last fetch \(seconds / 60)m ago"
        case ..<86400: return "last fetch \(seconds / 3600)h ago"
        default: return "last fetch \(seconds / 86400)d ago"
        }
    }

    /// Worktrees that need the user, counted only from a finished scan: a repo still being worked
    /// out is unknown, and unknown is not counted.
    public var needsYouCount: Int {
        self.phase == .forecast ? self.rows.filter { $0.lane == .needsYou }.count : 0
    }

    public struct MainMoved: Equatable, Sendable {
        public let behind: Int
        public let wouldConflict: Int
        public let notChecked: Int
    }

    /// Worktrees behind main, how many of those would conflict, and how many have no answer
    /// (no forecast, or git could not say). nil until forecast.
    public var mainMoved: MainMoved? {
        guard self.phase == .forecast else { return nil }
        let behind = self.rows.filter { !$0.isPrunable && $0.lane != .leftovers && ($0.behind ?? 0) > 0 }
        guard !behind.isEmpty else { return nil }
        let unchecked = behind.filter { row in
            guard let forecast = row.forecast else { return true }
            return forecast == .unknown
        }.count
        return MainMoved(
            behind: behind.count, wouldConflict: behind.filter { ($0.forecast?.conflictCount ?? 0) > 0 }.count,
            notChecked: unchecked
        )
    }

    /// A worktree without an answer is "not checked", never counted as "0 would conflict".
    public var mainMovedText: String? {
        guard let moved = self.mainMoved else { return nil }
        let head = "main moved: \(moved.behind) behind"
        if moved.notChecked == 0 { return head + ", \(moved.wouldConflict) would conflict" }
        if moved.notChecked == moved.behind { return head + ", not checked" }
        return head + ", \(moved.wouldConflict) would conflict, \(moved.notChecked) not checked"
    }

    public static func == (lhs: Self, rhs: Self) -> Bool {
        lhs.path == rhs.path && lhs.phase == rhs.phase && lhs.rows == rhs.rows && lhs.collisions == rhs.collisions
            && lhs.base == rhs.base && lhs.fetchedAt == rhs.fetchedAt
    }
}
