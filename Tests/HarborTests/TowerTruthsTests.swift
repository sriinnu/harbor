import Foundation
@testable import Harbor
@testable import HarborCore
import Testing

/// Tower's four truths: In review fills from the user's open pull requests, global ignores are
/// honoured by status, the forecast says how old its base is, and Needs you reaches the icon.
///
/// Only the model tests run on the main actor. The scanner tests run real git, synchronously, for
/// seconds under a loaded machine; on the main actor they held it long enough that every other
/// suite's main-actor wait loop timed out in the full run.
struct TowerTruthsTests {
    @MainActor
    private func wait(timeout: Duration = .seconds(15), _ condition: () -> Bool) async throws {
        let deadline = ContinuousClock.now + timeout
        while !condition() {
            guard ContinuousClock.now < deadline else { throw NSError(domain: "tower", code: 1, userInfo: [NSLocalizedDescriptionKey: "timed out"]) }
            try await Task.sleep(for: .milliseconds(50))
        }
    }

    // MARK: - a. In review

    @Test
    func slug_readsOwnerAndNameFromEveryRemoteShape() {
        #expect(TowerPulls.slug(remoteURL: "git@github.com:Sriinnu/Harbor.git") == "sriinnu/harbor")
        #expect(TowerPulls.slug(remoteURL: "https://github.com/Sriinnu/Harbor") == "sriinnu/harbor")
        #expect(TowerPulls.slug(remoteURL: "https://github.com/Sriinnu/Harbor.git/\n") == "sriinnu/harbor")
        #expect(TowerPulls.slug(remoteURL: "ssh://git@ghe.example.com:22/org/repo.git") == "org/repo")
        #expect(TowerPulls.slug(remoteURL: "/local/path") == nil)
        #expect(TowerPulls.slug(remoteURL: "") == nil)
        #expect(TowerPulls.slugs(configLines: "remote.origin.url git@github.com:A/b.git\nremote.up.url https://github.com/C/d\n") == ["a/b", "c/d"])
        #expect(TowerPulls.branches(forRemotes: ["a/b"], open: ["a/b": ["x", "y"], "c/d": ["z"]]) == ["x", "y"])
        #expect(TowerPulls.branches(forRemotes: ["e/f"], open: ["a/b": ["x"]]) == [])
    }

    @Test
    func openPullsWire_groupsHeadBranchesByRepoAndDropsEmptyNodes() throws {
        let json = #"""
        {"data":{"search":{"nodes":[
          {"headRefName":"feat/x","repository":{"nameWithOwner":"Sriinnu/Harbor"}},
          {"headRefName":"fix/y","repository":{"nameWithOwner":"Sriinnu/Harbor"}},
          {},
          null,
          {"headRefName":"z","repository":{"nameWithOwner":"o/other"}}
        ]}}}
        """#
        let wire = try JSONDecoder().decode(OpenPullBranchesWire.self, from: Data(json.utf8))
        #expect(wire.branches() == ["sriinnu/harbor": ["feat/x", "fix/y"], "o/other": ["z"]])
    }

    @Test @MainActor
    func model_aWorktreeWhoseBranchHasAnOpenPullLandsInReview() async throws {
        let fixture = try TowerFixture()
        defer { fixture.remove() }
        try fixture.git(["remote", "add", "origin", "git@github.com:Octo/App.git"])
        let model = TowerModel(
            tail: LedgerTail(url: fixture.root.appendingPathComponent("events.jsonl")), home: fixture.root.path,
            pullFetch: { ["octo/app": ["feat-clean"], "octo/other": ["feat-a"]] }
        )
        model.start(rootPaths: [fixture.root.path])
        defer { model.stop() }
        try await self.wait { model.repos[fixture.repo.path]?.phase == .forecast }
        let rows = try #require(model.repos[fixture.repo.path]).rows
        let byBranch = Dictionary(uniqueKeysWithValues: rows.map { ($0.branch ?? "", "\($0.lane.title): \($0.reason)") })
        #expect(byBranch["feat-clean"] == "In review: pull request open")
        // feat-a is named by a pull request in a repo this one has no remote for: not in review.
        #expect(byBranch["feat-a"] == "Needs you: would conflict with main in 1 file")
    }

    // MARK: - b. global ignores

    private func plantGlobalIgnore(_ fixture: TowerFixture, config: Bool) throws {
        if config {
            try Data("[core]\n\texcludesFile = ~/global-ignore\n".utf8).write(to: fixture.root.appendingPathComponent(".gitconfig"))
            try Data(".DS_Store\n".utf8).write(to: fixture.root.appendingPathComponent("global-ignore"))
        } else {
            let dir = fixture.root.appendingPathComponent(".config/git")
            try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
            try Data(".DS_Store\n".utf8).write(to: dir.appendingPathComponent("ignore"))
        }
        for dir in [fixture.worktreeA, fixture.worktreeB, fixture.worktreeClean] {
            try Data("junk".utf8).write(to: dir.appendingPathComponent(".DS_Store"))
        }
    }

    private func scan(_ fixture: TowerFixture) throws -> TowerRepoSnapshot {
        let git = try #require(TowerGit())
        let scanner = TowerScanner(git: git, home: fixture.root.path, host: "h", now: Date(), probe: NeverAlive(), xdgConfigHome: nil)
        return try #require(scanner.scan(repo: fixture.repo.path, ledger: [:]) { _ in })
    }

    @Test(arguments: [true, false])
    func status_honoursTheGlobalExcludesFileAndTheXdgDefault(configured: Bool) throws {
        let fixture = try TowerFixture()
        defer { fixture.remove() }
        try self.plantGlobalIgnore(fixture, config: configured)
        let final = try self.scan(fixture)
        let byBranch = Dictionary(uniqueKeysWithValues: final.rows.map { ($0.branch ?? "", $0) })
        let clean = try #require(byBranch["feat-clean"])
        #expect(clean.dirty == 0)
        #expect("\(clean.lane.title): \(clean.reason)" == "Ready: 1 ahead, clean")
        let paths = [fixture.worktreeA, fixture.worktreeB].map { AgentLedger.normalizedPath($0.path) }.sorted()
        #expect(final.collisions == [FileCollision(file: "a.txt", worktrees: paths)])
        // The merge forecast is untouched by any of this.
        #expect(byBranch["feat-a"]?.forecast == .conflicts(["a.txt"]))
    }

    @Test
    func status_withoutAnyGlobalIgnoreStillCountsUntrackedFiles() throws {
        let fixture = try TowerFixture()
        defer { fixture.remove() }
        for dir in [fixture.worktreeA, fixture.worktreeB, fixture.worktreeClean] {
            try Data("junk".utf8).write(to: dir.appendingPathComponent(".DS_Store"))
        }
        let final = try self.scan(fixture)
        let clean = try #require(final.rows.first { $0.branch == "feat-clean" })
        #expect(clean.dirty == 1)
        #expect(final.collisions.map(\.file) == [".DS_Store", "a.txt"])
    }

    @Test
    func excludes_resolveTildeAndPickTheGitconfigOverTheXdgFile() throws {
        let fixture = try TowerFixture()
        defer { fixture.remove() }
        let git = try #require(TowerGit())
        #expect(TowerExcludes.path(git: git, home: fixture.root.path) == nil)
        try self.plantGlobalIgnore(fixture, config: false)
        #expect(TowerExcludes.path(git: git, home: fixture.root.path) == fixture.root.path + "/.config/git/ignore")
        try self.plantGlobalIgnore(fixture, config: true)
        #expect(TowerExcludes.path(git: git, home: fixture.root.path) == fixture.root.path + "/global-ignore")
        #expect(TowerExcludes.statusArguments(excludesFile: nil) == ["status", "--porcelain=v2", "--untracked-files=normal"])
        #expect(TowerExcludes.statusArguments(excludesFile: "/x") == ["-c", "core.excludesFile=/x", "status", "--porcelain=v2", "--untracked-files=normal"])
    }

    // MARK: - c. how old origin/main is

    @Test
    func fetchAge_isTheNewestOfFetchHeadAndTheBaseReflog() throws {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("fetch-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: dir) }
        try FileManager.default.createDirectory(at: dir.appendingPathComponent("logs/refs/remotes/origin"), withIntermediateDirectories: true)
        #expect(TowerFetchAge.lastFetch(commonDirectory: dir.path, base: "origin/main") == nil)
        let reflog = dir.appendingPathComponent("logs/refs/remotes/origin/main")
        try Data("x".utf8).write(to: reflog)
        try FileManager.default.setAttributes([.modificationDate: Date(timeIntervalSince1970: 1_000)], ofItemAtPath: reflog.path)
        #expect(TowerFetchAge.lastFetch(commonDirectory: dir.path, base: "origin/main") == Date(timeIntervalSince1970: 1_000))
        let head = dir.appendingPathComponent("FETCH_HEAD")
        try Data("x".utf8).write(to: head)
        try FileManager.default.setAttributes([.modificationDate: Date(timeIntervalSince1970: 5_000)], ofItemAtPath: head.path)
        #expect(TowerFetchAge.lastFetch(commonDirectory: dir.path, base: "origin/main") == Date(timeIntervalSince1970: 5_000))
        // A local base has no fetch to be old.
        #expect(TowerFetchAge.lastFetch(commonDirectory: dir.path, base: "main") == nil)
    }

    @Test
    func scanner_carriesTheFetchTimeAndTheHeaderWordsIt() throws {
        let fixture = try TowerFixture()
        defer { fixture.remove() }
        try fixture.git(["update-ref", "refs/remotes/origin/main", "main"])
        try fixture.git(["symbolic-ref", "refs/remotes/origin/HEAD", "refs/remotes/origin/main"])
        let fetched = Date(timeIntervalSince1970: 1_762_800_000)
        let head = fixture.repo.appendingPathComponent(".git/FETCH_HEAD")
        try? FileManager.default.removeItem(at: fixture.repo.appendingPathComponent(".git/logs/refs/remotes/origin/main"))
        try Data("x".utf8).write(to: head)
        try FileManager.default.setAttributes([.modificationDate: fetched], ofItemAtPath: head.path)
        let final = try self.scan(fixture)
        #expect(final.base == "origin/main")
        #expect(final.fetchedAt == fetched)
        #expect(final.fetchText(now: fetched.addingTimeInterval(3 * 86400 + 5)) == "last fetch 3d ago")
        #expect(final.fetchText(now: fetched.addingTimeInterval(7200)) == "last fetch 2h ago")
        #expect(final.fetchText(now: fetched.addingTimeInterval(120)) == "last fetch 2m ago")
        #expect(final.fetchText(now: fetched.addingTimeInterval(10)) == "last fetch just now")
    }

    @Test
    func fetchText_isSilentForALocalBaseAndHonestWhenTheTimeIsUnknown() {
        let local = TowerRepoSnapshot(path: "/r", name: "r", base: "main", rows: [], collisions: [], phase: .forecast)
        #expect(local.fetchText() == nil)
        let unknown = TowerRepoSnapshot(path: "/r", name: "r", base: "origin/main", rows: [], collisions: [], phase: .forecast)
        #expect(unknown.fetchText() == "last fetch unknown")
    }

    // MARK: - d. the icon

    private func row(_ name: String, lane: TowerLane) -> TowerRow {
        TowerRow(
            repoPath: "/r", repoName: "r", path: "/r/\(name)", branch: name, agent: nil, task: nil, note: nil, evidence: nil,
            build: nil, delivered: nil, advice: nil, isLocked: false, isPrunable: false, ahead: 1, behind: 0, dirty: 0,
            forecast: nil, collisions: [], lastActivity: nil, timeline: [], lane: lane, reason: ""
        )
    }

    @Test
    func needsYouCount_countsOnlyFinishedScans() {
        let rows = [self.row("a", lane: .needsYou), self.row("b", lane: .needsYou), self.row("c", lane: .ready)]
        for phase in [TowerRepoSnapshot.Phase.listed, .counted, .detailed] {
            #expect(TowerRepoSnapshot(path: "/r", name: "r", base: nil, rows: rows, collisions: [], phase: phase).needsYouCount == 0)
        }
        #expect(TowerRepoSnapshot(path: "/r", name: "r", base: nil, rows: rows, collisions: [], phase: .forecast).needsYouCount == 2)
    }

    @Test
    func badge_addsTowersNeedsYouToThePanelsAndNothingWhenUnknown() {
        var content = HarborPanelContent()
        content.hasLoadedRepositories = true
        content.reviewRequestsLoaded = true
        content.myPullsLoaded = true
        let account = AccountState.loggedIn(UserIdentity(username: "me", host: URL(string: "https://github.com")!))
        #expect(StatusItemBadge(account: account, content: content, towerNeedsYou: 3) == .needsYou(3))
        #expect(StatusItemBadge(account: account, content: content, towerNeedsYou: 0) == .calm)
        #expect(StatusItemBadge(account: account, content: content) == .calm)
        #expect(StatusItemBadge(account: .loggedOut, content: content, towerNeedsYou: 3) == .signedOut)
    }

    @Test @MainActor
    func model_countsWorktreesNeedingYouOnceTheScanFinishes() async throws {
        let fixture = try TowerFixture()
        defer { fixture.remove() }
        let model = TowerModel(tail: LedgerTail(url: fixture.root.appendingPathComponent("events.jsonl")), home: fixture.root.path, pullFetch: { nil })
        #expect(model.needsYouCount == 0)
        model.start(rootPaths: [fixture.root.path])
        defer { model.stop() }
        try await self.wait { model.repos[fixture.repo.path]?.phase == .forecast }
        // feat-a and feat-b conflict with main; feat-clean is ready.
        #expect(model.needsYouCount == 2)
    }

    /// The bug this guards: a rescan replaced the finished snapshot with its first, unforecast
    /// one, so the badge lost this repo's count (and its conflict rows left Needs you) until the
    /// new pass finished. Any git event in the repo starts such a pass.
    @Test @MainActor
    func model_keepsTheFinishedCountWhileARescanRuns() async throws {
        let fixture = try TowerFixture()
        defer { fixture.remove() }
        let model = TowerModel(tail: LedgerTail(url: fixture.root.appendingPathComponent("events.jsonl")), home: fixture.root.path, pullFetch: { nil })
        model.start(rootPaths: [fixture.root.path])
        defer { model.stop() }
        try await self.wait { model.repos[fixture.repo.path]?.phase == .forecast }
        let firstPass = model.timings[fixture.repo.path]

        model.refresh()
        var seen = Set<Int>()
        let deadline = ContinuousClock.now + .seconds(15)
        // Timings land after every phase; the pass is over once a new one has its forecast lap.
        func rescanDone() -> Bool {
            guard let now = model.timings[fixture.repo.path] else { return false }
            return now != firstPass && now.forecast > 0
        }
        while !rescanDone(), ContinuousClock.now < deadline {
            seen.insert(model.needsYouCount)
            try await Task.sleep(for: .milliseconds(1))
        }

        #expect(rescanDone())
        #expect(seen == [2])
        #expect(model.needsYouCount == 2)
    }
}
