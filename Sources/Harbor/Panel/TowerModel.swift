import Foundation
import HarborCore
import Observation

/// The Tower tab's state: what is on screen, rebuilt from the ledger file and git whenever
/// either changes. Nothing is written to disk and nothing is reused to skip work; a change
/// event recomputes the repo it names.
@MainActor
@Observable
final class TowerModel {
    /// Repos with linked worktrees, by path, as far as each scan has got.
    private(set) var repos: [String: TowerRepoSnapshot] = [:]
    private(set) var repoCount = 0
    /// Repos whose `git worktree list` gave no answer (timed out, could not run) in the latest pass.
    /// They are unknown: shown as "couldn't check", never counted as clear. A snapshot from an
    /// earlier pass, if there is one, stays on screen beside it.
    private(set) var uncheckedRepos: Set<String> = []
    private(set) var isLoading = false
    /// Row open in the detail view.
    var openRow: String?
    /// Retire queue state for the open repo, by repo path.
    private(set) var retire: [String: RetireQueueState] = [:]
    private(set) var timings: [String: TowerScanner.Timings] = [:]

    /// git could not be found, so nothing could be scanned: the tab says that instead of "no repos".
    private(set) var gitMissing = false
    /// git is there but older than the merge forecast needs: shown once in the header, and rows
    /// carry no forecast instead of all landing in Needs you.
    private(set) var forecastNeedsNewerGit = false
    /// The repos whose `.git` directory is being watched (a repo whose `rev-parse` failed is not here).
    var watchedRepos: Set<String> { self.watched }

    private let tail: LedgerTail
    private let locator: ExecutableLocator?
    private var watcher: GitDirWatcher?
    /// The repos the current watcher observes.
    private var watched: Set<String> = []
    private var rootPaths: [String] = []
    private var pending: Set<String> = []
    private var debounce: Task<Void, Never>?
    private var discovery: Task<Void, Never>?
    private var started = false
    private var scanning = false

    /// The user's open pull requests as lowercased `owner/name` to head branch names, read once
    /// per scan pass for every repo at once; nil when there is no answer (signed out, offline, the
    /// search failed), in which case no row is "in review" rather than a guess. The default reads
    /// the answer `MyPullsStore` already has (it searches on every refresh and panel open): Tower
    /// never searches on its own, and holds no copy of the answer between passes.
    private let pullFetch: @MainActor () async -> [String: Set<String>]?
    /// Whose home the global ignore file and `safe.directory` come from; nil is the user's own.
    private let home: String?
    /// The pull answer the last pass was built from; a different one from the store is a reason
    /// to scan again (`pullsChanged`). The pass's own input, not a cache: every pass reads afresh.
    private var pullsUsed: [String: Set<String>]?
    /// The ledger as the last pass saw it, to tell which repos a ledger event names.
    private var ledgerUsed: [String: LedgerWorktree] = [:]
    /// Bumped by `stop()` and `reset()`: a pass still running for the old folders or account
    /// finds its snapshots refused.
    private var generation = 0
    /// How many scan passes have finished, and how many times the pull answer was read.
    private(set) var scanPasses = 0
    private(set) var pullReads = 0

    /// How long one read-only git call may take; tests shorten it.
    private let gitTimeout: TimeInterval

    init(
        tail: LedgerTail = LedgerTail(), locator: ExecutableLocator? = nil,
        home: String? = nil, gitTimeout: TimeInterval = TowerGit.defaultTimeout,
        pullFetch: @escaping @MainActor () async -> [String: Set<String>]? = {
            // The answer Needs you shows: read, never searched for again.
            MyPullsStore.shared.branchesForTower()
        }
    ) {
        self.tail = tail
        self.locator = locator
        self.home = home
        self.gitTimeout = gitTimeout
        self.pullFetch = pullFetch
    }

    /// Worktrees that need you, from repos whose scan has finished. A repo still being worked out
    /// adds nothing: unknown is not counted.
    /// A linked worktree inside a project folder is also found as a "repo" of its own, so the same
    /// worktree can sit in two snapshots: it counts once, by path.
    var needsYouCount: Int {
        Set(self.repos.values.filter { $0.phase == .forecast }.flatMap(\.rows).filter { $0.lane == .needsYou }.map(\.path)).count
    }

    var rows: [TowerRow] { self.repos.values.flatMap(\.rows) }

    func rows(in lane: TowerLane) -> [TowerRow] {
        self.rows.filter { $0.lane == lane }.sorted {
            if $0.repoName != $1.repoName { return $0.repoName.localizedCaseInsensitiveCompare($1.repoName) == .orderedAscending }
            return ($0.lastActivity ?? .distantPast) > ($1.lastActivity ?? .distantPast)
        }
    }

    func row(id: String) -> TowerRow? { self.rows.first { $0.id == id } }

    /// Repos that have a collision list, in name order.
    var collisionRepos: [TowerRepoSnapshot] {
        self.repos.values.filter { !$0.collisions.isEmpty }.sorted { $0.name < $1.name }
    }

    // MARK: - lifecycle

    func start(rootPaths: [String]) {
        guard !self.started else { return }
        self.started = true
        self.rootPaths = rootPaths
        self.isLoading = true
        // The ledger watch: an append recomputes the repos whose worktrees it names.
        self.tail.start { [weak self] in
            Task { @MainActor in self?.ledgerChanged() }
        }
        Task { await self.discoverAndScan() }
    }

    func stop() {
        self.started = false
        self.tail.stop()
        self.watcher?.stop()
        self.watcher = nil
        self.watched = []
        self.debounce?.cancel()
        self.debounce = nil
        self.discovery?.cancel()
        self.discovery = nil
        self.pending = []
        // A folder removed from the project list must leave Tower with it: nothing of the old
        // set stays in the lanes or the menu bar badge.
        self.clearState()
    }

    /// The signed-in account changed: everything shown was found for the old one (which pull
    /// requests are "in review" is its answer), so it goes, and the next pass starts from nothing.
    func reset() {
        self.clearState()
        guard self.started else { return }
        self.rediscover()
    }

    private func clearState() {
        self.generation += 1
        self.repos = [:]
        self.uncheckedRepos = []
        self.repoCount = 0
        self.retire = [:]
        self.timings = [:]
        self.pullsUsed = nil
        self.ledgerUsed = [:]
        self.openRow = nil
    }

    /// `MyPullsStore` has a new answer: scan again only if it differs from what the last pass used.
    func pullsChanged() {
        guard self.started else { return }
        Task { @MainActor in
            let answer = await self.pullFetch()
            guard self.started, answer != self.pullsUsed else { return }
            self.schedule(Set(self.repos.keys))
        }
    }

    /// The tab was opened: look again at every repo.
    func refresh() {
        guard self.started else { return }
        self.rediscover()
    }

    /// A ledger line moved a row: rescan the repos whose worktrees changed in the ledger, nothing
    /// else. A change for a worktree no repo on screen holds (a first worktree, a new repo) looks
    /// for repos again.
    private func ledgerChanged() {
        guard self.started else { return }
        let current = self.tail.snapshot()
        let changed = Set(current.keys).union(self.ledgerUsed.keys).filter { current[$0] != self.ledgerUsed[$0] }
        guard !changed.isEmpty else { return }
        var targets = Set<String>()
        var unknown = false
        for path in changed {
            if let repo = self.repos.values.first(where: { $0.rows.contains { $0.path == path } })?.path {
                targets.insert(repo)
            } else if let repo = (current[path]?.repo ?? self.ledgerUsed[path]?.repo), self.repos[repo] != nil {
                targets.insert(repo)
            } else {
                unknown = true
            }
        }
        if unknown { self.rediscover() } else { self.schedule(targets) }
    }

    private func rediscover() {
        // Any ledger line can move a row between lanes, and the first worktree of a repo may
        // have just been created: look for repos again, and recompute every one found plus
        // every one on screen.
        // A burst of ledger lines is one discovery, run 400 ms after the last line; a stale
        // one is cancelled so it can never finish last and overwrite `repoCount`.
        self.discovery?.cancel()
        self.discovery = Task { [weak self] in
            try? await Task.sleep(for: .milliseconds(400))
            guard !Task.isCancelled, let self, self.started else { return }
            let roots = self.rootPaths
            let ledger = self.tail.snapshot()
            let git = TowerGit(locator: self.locator, timeout: self.gitTimeout)
            let found = await Task.detached(priority: .userInitiated) {
                TowerRepos.discover(rootPaths: roots, ledger: ledger, git: git)
            }.value
            guard !Task.isCancelled, self.started else { return }
            self.repoCount = found.count
            self.schedule(Set(found).union(self.repos.keys))
        }
    }

    private func schedule(_ paths: Set<String>) {
        self.pending.formUnion(paths)
        self.debounce?.cancel()
        self.debounce = Task { [weak self] in
            try? await Task.sleep(for: .milliseconds(400))
            guard !Task.isCancelled else { return }
            // Unstructured, so a later event cancelling the debounce never cancels a running scan.
            Task { await self?.drain() }
        }
    }

    /// One scan at a time; events that arrive meanwhile are folded into the next pass.
    private func drain() async {
        guard !self.scanning else { return }
        self.scanning = true
        defer { self.scanning = false }
        while self.started, !self.pending.isEmpty {
            let batch = self.pending
            self.pending = []
            await self.scan(Array(batch))
            await self.rewatchIfNeeded()
        }
    }

    // MARK: - scanning

    private func discoverAndScan() async {
        let roots = self.rootPaths
        let ledger = self.tail.snapshot()
        let git = TowerGit(locator: self.locator, timeout: self.gitTimeout)
        let found = await Task.detached(priority: .userInitiated) {
            TowerRepos.discover(rootPaths: roots, ledger: ledger, git: git)
        }.value
        guard self.started else { return }
        self.repoCount = found.count
        await self.scan(found)
        self.isLoading = false
        await self.rewatchIfNeeded()
    }

    private func scan(_ paths: [String]) async {
        guard let git = TowerGit(locator: self.locator, timeout: self.gitTimeout) else {
            self.gitMissing = true
            return
        }
        self.gitMissing = false
        // Once per pass: is this git new enough for the merge forecast?
        let supported = await Task.detached(priority: .userInitiated) {
            git.versionString().map { TowerGitParse.supportsForecast(versionText: $0) } ?? true
        }.value
        self.forecastNeedsNewerGit = !supported
        let ledger = self.tail.snapshot()
        let generation = self.generation
        self.ledgerUsed = ledger
        // The open pull requests as the store has them right now: read, not searched for.
        self.pullReads += 1
        let answer = await self.pullFetch()
        self.pullsUsed = answer
        let pulls = answer ?? [:]
        // The user's config read once for the whole pass, off the main actor.
        let base = self.makeScanner(git: git, forecastSupported: supported)
        let scanner = await Task.detached(priority: .userInitiated) { base.prepared() }.value
        await withTaskGroup(of: Void.self) { group in
            for path in paths {
                group.addTask { [weak self] in
                    let (stream, continuation) = AsyncStream<TowerRepoSnapshot>.makeStream()
                    let work = Task.detached(priority: .userInitiated) {
                        let branches = TowerPulls.branches(forRemotes: scanner.remoteSlugs(repo: path), open: pulls)
                        let result = scanner.scanOutcome(repo: path, ledger: ledger, openPullBranches: branches, timings: { timing in
                            Task { @MainActor in if self?.generation == generation { self?.timings[path] = timing } }
                        }, emit: { continuation.yield($0) })
                        continuation.finish()
                        return result
                    }
                    for await snapshot in stream { await self?.apply(snapshot, generation: generation) }
                    switch await work.value {
                    case .scanned: break
                    case .noWorktrees: await self?.drop(path, generation: generation)
                    case .couldNotRead: await self?.markUnchecked(path, generation: generation)
                    }
                }
            }
        }
        self.scanPasses += 1
    }

    private func makeScanner(git: TowerGit, forecastSupported: Bool) -> TowerScanner {
        guard let home = self.home else { return TowerScanner(git: git, forecastSupported: forecastSupported) }
        return TowerScanner(git: git, home: home, forecastSupported: forecastSupported, xdgConfigHome: nil)
    }

    private func apply(_ snapshot: TowerRepoSnapshot, generation: Int) {
        guard self.started, generation == self.generation else { return }
        self.repos[snapshot.path] = snapshot
        self.uncheckedRepos.remove(snapshot.path)
    }

    private func drop(_ path: String, generation: Int) {
        guard generation == self.generation else { return }
        self.repos[path] = nil
        self.uncheckedRepos.remove(path)
    }

    private func markUnchecked(_ path: String, generation: Int) {
        guard started, generation == self.generation else { return }
        self.uncheckedRepos.insert(path)
    }

    /// One FSEvents stream over the `.git` directories of repos that have worktrees; replaced
    /// whenever that set of repos changes.
    private func rewatchIfNeeded() async {
        guard self.started, Set(self.repos.keys) != self.watched else { return }
        await self.rewatch()
    }

    private func rewatch() async {
        guard let git = TowerGit(locator: self.locator, timeout: self.gitTimeout), self.started else { return }
        let paths = Array(self.repos.keys)
        // One `git rev-parse` per repo: not on the main actor.
        let base = self.makeScanner(git: git, forecastSupported: true)
        let dirs = await Task.detached(priority: .userInitiated) {
            let scanner = TowerScanner(git: base.readingGit())
            var dirs: [String: String] = [:]
            for path in paths {
                if let dir = scanner.commonDirectory(repo: path) { dirs[path] = dir }
            }
            return dirs
        }.value
        guard self.started else { return }
        self.watcher?.stop()
        // Only repos whose `rev-parse` worked count as watched, so a failed one is retried on the
        // next rewatch instead of staying unwatched until the repo set changes.
        self.watched = Set(dirs.keys)
        self.watcher = GitDirWatcher(gitDirs: dirs) { [weak self] changed in
            Task { @MainActor in self?.schedule(changed) }
        }
    }

    // MARK: - retire queue

    func runAudit(repo: String) {
        self.retire[repo] = RetireQueueState(phase: .auditing)
        Task {
            let out = await Task.detached {
                RetireCommand.run(RetireCommand.auditArguments(repo: repo), mergeStderr: false)
            }.value
            guard let out, out.status == 0, !out.timedOut else {
                self.retire[repo] = RetireQueueState(phase: .failed(out?.text.trimmedTail ?? "python3 not found"))
                return
            }
            self.retire[repo] = RetireQueueState(phase: .listed(RetireAudit.candidates(json: out.text)))
        }
    }

    func dryRun(repo: String, candidate: RetireCandidate) {
        guard case let .listed(list) = self.retire[repo]?.phase else { return }
        self.retire[repo] = RetireQueueState(phase: .running(list, candidate, execute: false))
        Task {
            let out = await Task.detached {
                RetireCommand.run(RetireCommand.arguments(repo: repo, path: candidate.path))
            }.value
            self.retire[repo] = RetireQueueState(phase: .confirming(list, candidate, out?.text ?? "python3 not found", ok: out?.status == 0 && out?.timedOut != true))
        }
    }

    func execute(repo: String) {
        guard case let .confirming(list, candidate, _, ok) = self.retire[repo]?.phase, ok else { return }
        self.retire[repo] = RetireQueueState(phase: .running(list, candidate, execute: true))
        Task {
            let out = await Task.detached {
                RetireCommand.run(RetireCommand.arguments(repo: repo, path: candidate.path, execute: true), timeout: RetireCommand.executeTimeout)
            }.value
            self.retire[repo] = RetireQueueState(phase: .finished(out?.text ?? "python3 not found", ok: out?.status == 0 && out?.timedOut != true))
            self.schedule([repo])
        }
    }

    func cancelRetire(repo: String) {
        switch self.retire[repo]?.phase {
        case let .confirming(list, _, _, _): self.retire[repo] = RetireQueueState(phase: .listed(list))
        case .finished, .failed: self.retire[repo] = nil
        default: break
        }
    }

    /// True while `--execute` is running: Escape must not close the panel, or its result is never shown.
    var retireExecuting: Bool {
        self.retire.values.contains {
            if case .running(_, _, execute: true) = $0.phase { return true }
            return false
        }
    }

    /// True while a retire step is waiting on the user or running: the panel must stay open.
    var retirePending: Bool {
        self.retire.values.contains {
            switch $0.phase {
            case .confirming, .running, .auditing: true
            default: false
            }
        }
    }
}

struct RetireQueueState {
    enum Phase {
        case auditing
        case listed([RetireCandidate])
        case running([RetireCandidate], RetireCandidate, execute: Bool)
        /// The dry run's output, shown verbatim; `ok` is its exit status 0.
        case confirming([RetireCandidate], RetireCandidate, String, ok: Bool)
        case finished(String, ok: Bool)
        case failed(String)
    }

    var phase: Phase
}

private extension String {
    var trimmedTail: String {
        let text = self.trimmingCharacters(in: .whitespacesAndNewlines)
        return text.count > 400 ? "…" + text.suffix(400) : text
    }
}

/// Words the Tower tab shows when it has no repos to list.
enum TowerCopy {
    static let emptyTitle = "No agent worktrees yet"
    static let emptyParagraphs = [
        "Tower lists the git worktrees your coding agents work in (Codex, Claude Code, Cursor, Qwen, OpenCode, ribhu and others), sorted by what needs you: a build that failed, a branch that would conflict with main, an agent waiting for your answer.",
        "Harbor finds them by running git worktree list in every repo under your project folders (Settings, Local Git). It guesses the agent from the folder the worktree sits in, and sees who is inside by looking for a running process in that folder. It never starts or stops anything.",
        "An optional ledger at ~/.agents/ledger/events.jsonl adds names, tasks and an agent.waiting event, so \u{201C}waiting on you\u{201D} is exact instead of a guess."
    ]
    static let gitMissing = "git not found. Tower needs git to read your repos."
    static let gitTooOld = "merge check needs git 2.41 or later"
}
