import Foundation

/// Works out one repo's worktrees in phases, cheapest first, calling `emit` after each so the
/// view can paint what is known. Only `git --no-optional-locks` runs; no repo is written.
public struct TowerScanner: Sendable {
    public struct Timings: Equatable, Sendable {
        public var listed: TimeInterval = 0
        public var counted: TimeInterval = 0
        public var detailed: TimeInterval = 0
        public var forecast: TimeInterval = 0
    }

    let git: TowerGit
    let home: String
    let host: String
    let now: Date
    let probe: any ProcessProbe
    /// False when git is too old for the merge forecast: no forecast is made, so rows stay `nil`.
    let forecastSupported: Bool

    public init(
        git: TowerGit, home: String = NSHomeDirectory(), host: String = LedgerLiveness.currentHost,
        now: Date = Date(), probe: any ProcessProbe = SystemProcessProbe(), forecastSupported: Bool = true
    ) {
        self.forecastSupported = forecastSupported
        self.git = git
        self.home = home
        self.host = host
        self.now = now
        self.probe = probe
    }

    /// What building rows needs besides the worktrees themselves.
    struct RowContext {
        let repo: String
        let name: String
        let pulls: Set<String>
        let home: String
        let host: String
        let now: Date
        let probe: any ProcessProbe
    }

    private func context(repo: String, name: String, pulls: Set<String>) -> RowContext {
        RowContext(repo: repo, name: name, pulls: pulls, home: self.home, host: self.host, now: self.now, probe: self.probe)
    }

    /// Per-worktree facts gathered so far.
    struct Partial: Sendable {
        let entry: GitWorktreeEntry
        let ledger: LedgerWorktree?
        var ahead: Int?
        var behind: Int?
        var committed: Date?
        var dirty: Int?
        var dirtyPaths: [String] = []
        var forecast: MergeForecast?
    }

    /// The repo's absolute object directory, for the forecast's alternate store.
    public func objectsDirectory(repo: String) -> String? {
        guard let common = self.git.output(["rev-parse", "--path-format=absolute", "--git-common-dir"], in: repo)?
            .trimmingCharacters(in: .whitespacesAndNewlines), !common.isEmpty else { return nil }
        return common + "/objects"
    }

    /// The repo's `.git` directory as an absolute path (what the watcher observes).
    public func commonDirectory(repo: String) -> String? {
        self.git.output(["rev-parse", "--path-format=absolute", "--git-common-dir"], in: repo)?
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// Ahead/behind and tip time for the given local branches. One `for-each-ref` with
    /// `%(ahead-behind:)` where git has it; where git refuses that format (before 2.41) the same
    /// numbers come from one `rev-list --left-right --count` per branch, and the tip times from a
    /// plain `for-each-ref`.
    func branchTips(base: String, repo: String, branches: [String]) -> [String: BranchTip] {
        if let raw = self.git.output(TowerGitParse.branchArguments(base: base), in: repo) {
            return TowerGitParse.branchTips(raw)
        }
        let dates = self.git.output(TowerGitParse.branchDatesArguments, in: repo).map(TowerGitParse.branchDates) ?? [:]
        var result: [String: BranchTip] = [:]
        for branch in Set(branches) {
            guard let counts = self.git.output(["rev-list", "--left-right", "--count", "\(base)...refs/heads/\(branch)"], in: repo)
                .flatMap(TowerGitParse.leftRight) else { continue }
            result[branch] = BranchTip(counts: counts, committed: dates[branch])
        }
        return result
    }

    /// nil when `repo` isn't a git repo or has no linked worktrees.
    @discardableResult
    public func scan(
        repo: String,
        ledger: [String: LedgerWorktree],
        openPullBranches: Set<String> = [],
        timings: ((Timings) -> Void)? = nil,
        emit: (TowerRepoSnapshot) -> Void
    ) -> TowerRepoSnapshot? {
        var clock = Timings()
        var mark = Date()
        func lap(_ keyPath: WritableKeyPath<Timings, TimeInterval>) {
            clock[keyPath: keyPath] = Date().timeIntervalSince(mark)
            mark = Date()
            timings?(clock)
        }

        guard let raw = self.git.output(["worktree", "list", "--porcelain"], in: repo) else { return nil }
        let linked = GitWorktreePorcelain.parse(raw).dropFirst().filter { !$0.isBare }
        guard !linked.isEmpty else { return nil }
        let name = URL(fileURLWithPath: repo).lastPathComponent
        let base = self.baseRef(in: repo)
        let ctx = self.context(repo: repo, name: name, pulls: openPullBranches)
        var partials = linked.map { Partial(entry: $0, ledger: ledger[AgentLedger.normalizedPath($0.path)]) }

        var snapshot = self.snapshot(ctx, base, partials, .listed, collisions: [])
        emit(snapshot)
        lap(\.listed)

        if let base {
            let tips = self.branchTips(base: base, repo: repo, branches: partials.compactMap(\.entry.branch))
            for index in partials.indices {
                let entry = partials[index].entry
                if let branch = entry.branch, let tip = tips[branch] {
                    partials[index].ahead = tip.counts.ahead
                    partials[index].behind = tip.counts.behind
                    partials[index].committed = tip.committed
                } else if !entry.isPrunable, entry.branch == nil,
                          let counts = self.git.output(["rev-list", "--left-right", "--count", "\(base)...HEAD"], in: entry.path)
                          .flatMap(TowerGitParse.leftRight) {
                    // Detached HEAD: no branch ref to ask about.
                    partials[index].ahead = counts.ahead
                    partials[index].behind = counts.behind
                }
            }
        }
        snapshot = self.snapshot(ctx, base, partials, .counted, collisions: [])
        emit(snapshot)
        lap(\.counted)

        let entries = partials.map(\.entry)
        let reading = partials.map { self.isWorthReading($0) }
        let statuses = Self.concurrentMap(Array(entries.indices)) { index -> (Int, [String])? in
            let entry = entries[index]
            guard reading[index],
                  let out = self.git.output(["status", "--porcelain=v2", "--untracked-files=normal"], in: entry.path)
            else { return nil }
            return (index, TowerGitParse.statusPaths(out))
        }
        for (index, paths) in statuses {
            partials[index].dirty = paths.count
            partials[index].dirtyPaths = paths
        }
        snapshot = self.snapshot(ctx, base, partials, .detailed, collisions: [])
        emit(snapshot)
        lap(\.detailed)

        // Forecast only where a conflict is possible: a branch both ahead of and behind main.
        if let base, let objects = self.objectsDirectory(repo: repo) {
            let targets = !self.forecastSupported ? [] : partials.indices.filter {
                let item = partials[$0]
                return reading[$0] && item.ledger?.delivered == nil
                    && (item.ahead ?? 0) > 0 && (item.behind ?? 0) > 0 && item.entry.head != nil
            }
            let heads = partials.map { $0.entry.head ?? "HEAD" }
            let forecasts = Self.concurrentMap(targets) { index -> (Int, MergeForecast) in
                let head = heads[index]
                return (index, ConflictForecast.run(
                    git: self.git, repo: repo, objectsDirectory: objects, base: base, head: head
                ))
            }
            for (index, forecast) in forecasts { partials[index].forecast = forecast }
            for index in partials.indices where (partials[index].behind ?? 0) == 0 && !partials[index].entry.isPrunable {
                // Not behind main: nothing to conflict with.
                if partials[index].ahead != nil { partials[index].forecast = .clean }
            }
        }
        let collisions = self.collisions(ctx, base: base, partials: partials)
        snapshot = self.snapshot(ctx, base, partials, .forecast, collisions: collisions)
        emit(snapshot)
        lap(\.forecast)
        return snapshot
    }

    // MARK: - rows

    private func snapshot(
        _ ctx: RowContext, _ base: String?, _ partials: [Partial], _ phase: TowerRepoSnapshot.Phase,
        collisions: [FileCollision]
    ) -> TowerRepoSnapshot {
        let rows = Self.makeRows(partials, collisions: collisions, context: ctx)
        return TowerRepoSnapshot(path: ctx.repo, name: ctx.name, base: base, rows: rows, collisions: collisions, phase: phase)
    }

    static func makeRows(_ partials: [Partial], collisions: [FileCollision], context ctx: RowContext) -> [TowerRow] {
        let rows = partials.map { item -> TowerRow in
            let entry = item.entry
            let ledger = item.ledger
            let evidence = ledger.flatMap { LedgerLiveness.evidence(for: $0, host: ctx.host, now: ctx.now, probe: ctx.probe) }
            let branch = entry.branch ?? ledger?.branch.flatMap { $0 == "(detached)" ? nil : $0 }
            let facts = TowerFacts(
                isPrunable: entry.isPrunable, live: evidence, buildStatus: ledger?.build?.status,
                isDelivered: ledger?.delivered != nil, hasOpenPull: branch.map(ctx.pulls.contains) ?? false,
                ahead: item.ahead, behind: item.behind, dirty: item.dirty, forecast: item.forecast,
                idleDays: Self.idleDays(ledger: ledger, committed: item.committed, now: ctx.now)
            )
            let (lane, reason) = TowerLanes.assign(facts)
            let mine = Set(collisions.filter { $0.worktrees.contains(AgentLedger.normalizedPath(entry.path)) }.map(\.file))
            return TowerRow(
                repoPath: ctx.repo, repoName: ctx.name, path: AgentLedger.normalizedPath(entry.path), branch: branch,
                agent: ledger?.agent ?? AgentWorktrees.agentFromPath(entry.path, home: ctx.home),
                task: ledger?.task, note: ledger?.note, evidence: evidence, build: ledger?.build,
                delivered: ledger?.delivered, advice: ledger?.advice, isLocked: entry.isLocked,
                isPrunable: entry.isPrunable, ahead: item.ahead, behind: item.behind, dirty: item.dirty,
                forecast: item.forecast, collisions: mine.sorted(),
                lastActivity: [ledger?.lastEvent, item.committed].compactMap { $0 }.max(),
                timeline: ledger?.timeline ?? [], lane: lane, reason: reason
            )
        }
        return rows.sorted {
            if $0.lane != $1.lane { return $0.lane.rawValue < $1.lane.rawValue }
            return ($0.lastActivity ?? .distantPast) > ($1.lastActivity ?? .distantPast)
        }
    }

    /// Whole days since the newest of the ledger's last event and the branch tip's commit.
    static func idleDays(ledger: LedgerWorktree?, committed: Date?, now: Date) -> Int? {
        guard let last = [ledger?.lastEvent, committed].compactMap({ $0 }).max() else { return nil }
        return max(0, Int(now.timeIntervalSince(last) / 86400))
    }

    /// Debris needs no status or forecast: nobody is inside and nothing has moved for weeks.
    private func isWorthReading(_ item: Partial) -> Bool {
        if item.entry.isPrunable { return false }
        if let ledger = item.ledger,
           LedgerLiveness.evidence(for: ledger, host: self.host, now: self.now, probe: self.probe) != nil { return true }
        guard let idle = Self.idleDays(ledger: item.ledger, committed: item.committed, now: self.now) else { return true }
        return idle < TowerLanes.staleAfterDays
    }

    // MARK: - collisions

    private func collisions(_ ctx: RowContext, base: String?, partials: [Partial]) -> [FileCollision] {
        let rows = Self.makeRows(partials, collisions: [], context: ctx)
        let live = Set(rows.filter { $0.lane != .leftovers && !$0.isPrunable }.map(\.path))
        let candidates = partials.filter { live.contains(AgentLedger.normalizedPath($0.entry.path)) }
        let changed = Self.concurrentMap(candidates) { item -> (String, Set<String>) in
            var files = Set(item.dirtyPaths)
            if let base, let out = self.git.output(["diff", "--name-only", "\(base)...HEAD"], in: item.entry.path) {
                files.formUnion(out.split(whereSeparator: \.isNewline).map(String.init))
            }
            return (AgentLedger.normalizedPath(item.entry.path), files)
        }
        return CollisionMap.collisions(changes: Dictionary(changed, uniquingKeysWith: { $0.union($1) }))
    }

    /// The branch worktrees are measured against: origin's default, else a local main/master.
    func baseRef(in repo: String) -> String? {
        if let head = self.git.output(["symbolic-ref", "-q", "--short", "refs/remotes/origin/HEAD"], in: repo)?
            .trimmingCharacters(in: .whitespacesAndNewlines), !head.isEmpty {
            return head
        }
        return ["origin/main", "main", "origin/master", "master"].first {
            self.git.output(["rev-parse", "--verify", "-q", $0], in: repo) != nil
        }
    }

    /// Runs `body` over `items` on every core, keeping the results that exist.
    static func concurrentMap<Item: Sendable, Output: Sendable>(
        _ items: [Item], _ body: @Sendable (Item) -> Output?
    ) -> [Output] {
        let lock = NSLock()
        nonisolated(unsafe) var results: [Output] = []
        DispatchQueue.concurrentPerform(iterations: items.count) { index in
            guard let value = body(items[index]) else { return }
            lock.lock()
            results.append(value)
            lock.unlock()
        }
        return results
    }
}
