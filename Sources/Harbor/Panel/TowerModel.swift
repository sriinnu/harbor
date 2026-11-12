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

    init(tail: LedgerTail = LedgerTail(), locator: ExecutableLocator? = nil) {
        self.tail = tail
        self.locator = locator
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
    }

    private func ledgerChanged() {
        guard self.started else { return }
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
            let found = await Task.detached(priority: .userInitiated) {
                TowerRepos.discover(rootPaths: roots, ledger: ledger)
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
        let found = await Task.detached(priority: .userInitiated) {
            TowerRepos.discover(rootPaths: roots, ledger: ledger)
        }.value
        guard self.started else { return }
        self.repoCount = found.count
        await self.scan(found)
        self.isLoading = false
        await self.rewatchIfNeeded()
    }

    private func scan(_ paths: [String]) async {
        guard let git = TowerGit(locator: self.locator) else {
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
        await withTaskGroup(of: Void.self) { group in
            for path in paths {
                group.addTask { [weak self] in
                    let scanner = TowerScanner(git: git, forecastSupported: supported)
                    let (stream, continuation) = AsyncStream<TowerRepoSnapshot>.makeStream()
                    let work = Task.detached(priority: .userInitiated) {
                        let result = scanner.scan(repo: path, ledger: ledger, timings: { timing in
                            Task { @MainActor in self?.timings[path] = timing }
                        }, emit: { continuation.yield($0) })
                        continuation.finish()
                        return result
                    }
                    for await snapshot in stream { await self?.apply(snapshot) }
                    if await work.value == nil { await self?.drop(path) }
                }
            }
        }
    }

    private func apply(_ snapshot: TowerRepoSnapshot) {
        guard self.started else { return }
        self.repos[snapshot.path] = snapshot
    }

    private func drop(_ path: String) {
        self.repos[path] = nil
    }

    /// One FSEvents stream over the `.git` directories of repos that have worktrees; replaced
    /// whenever that set of repos changes.
    private func rewatchIfNeeded() async {
        guard self.started, Set(self.repos.keys) != self.watched else { return }
        await self.rewatch()
    }

    private func rewatch() async {
        guard let git = TowerGit(locator: self.locator), self.started else { return }
        let paths = Array(self.repos.keys)
        // One `git rev-parse` per repo: not on the main actor.
        let dirs = await Task.detached(priority: .userInitiated) {
            let scanner = TowerScanner(git: git)
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
    static let noRepos = "No repos with linked worktrees."
    static let gitMissing = "git not found. Tower needs git to read your repos."
    static let gitTooOld = "merge check needs git 2.41 or later"
}
