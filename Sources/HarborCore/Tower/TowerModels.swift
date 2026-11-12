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

    public init(
        isPrunable: Bool = false, live: LiveEvidence? = nil, buildStatus: String? = nil,
        isDelivered: Bool = false, hasOpenPull: Bool = false, ahead: Int? = nil, behind: Int? = nil,
        dirty: Int? = nil, forecast: MergeForecast? = nil, idleDays: Int? = nil
    ) {
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
            && lhs.base == rhs.base
    }
}
