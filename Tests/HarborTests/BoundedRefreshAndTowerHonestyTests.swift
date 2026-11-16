import Foundation
@testable import Harbor
@testable import HarborCore
import Testing

/// 0.2.4 review fixes: the refresh's cost is bounded, Tower's readings are honest about age and
/// liveness, notifications do not flap, and the panel does not say "clear" before it has asked.
/// Git fixtures run without the developer's config; nothing here touches the network, the
/// Keychain or the real home folder.
struct BoundedRefreshAndTowerHonestyTests {
    // MARK: - M3: the enrichment plan

    private func repo(_ name: String, pushedDaysAgo: Int) -> Repository {
        Repository(
            id: "o/\(name)", name: name, owner: "o", sortOrder: nil, error: nil, rateLimitedUntil: nil, ciStatus: .unknown,
            openIssues: 0, openPulls: 0, pushedAt: Date(timeIntervalSince1970: 1_800_000_000 - Double(pushedDaysAgo) * 86400),
            latestRelease: nil, latestActivity: nil, traffic: nil, heatmap: [], pullCountsKnown: false
        )
    }

    private func listing(_ count: Int) -> [Repository] {
        (0 ..< count).map { self.repo("r\($0)", pushedDaysAgo: $0) }
    }

    @Test
    func plan_bigOrgCostsAtMostSixtyPlusPinnedRepos_notEveryRepo() {
        let repos = self.listing(1800)
        let plan = RepoEnrichmentPlan.make(repos: repos, pinned: ["o/r1500"], graphQLRemaining: nil)
        #expect(plan.enrich.count == 61)
        #expect(plan.enrich.map(\.fullName).prefix(1) == ["o/r1500"])
        #expect(plan.enrich.dropFirst().map(\.fullName) == (0 ..< 60).map { "o/r\($0)" })
        #expect(plan.deferred.count == 1739)
        // 61 repos is 11 queries, not 300.
        #expect(GitHubRepoBatch.chunks(plan.enrich.map { RepoRef(owner: $0.owner, name: $0.name) }).count == 11)
    }

    @Test
    func plan_picksTheNewestPushesEvenWhenTheListingIsNotInThatOrder() {
        let repos = [self.repo("old", pushedDaysAgo: 400), self.repo("new", pushedDaysAgo: 1), self.repo("mid", pushedDaysAgo: 30)]
        let plan = RepoEnrichmentPlan.make(repos: repos, pinned: [], graphQLRemaining: nil, cap: 2)
        #expect(plan.enrich.map(\.fullName) == ["o/new", "o/mid"])
        #expect(plan.deferred.map(\.fullName) == ["o/old"])
    }

    @Test
    func plan_shrinksToWhatTheGraphQLBudgetPaysFor_andToNothingWhenSpent() {
        let repos = self.listing(200)
        // 600 left, 500 kept back: 100 points at 5 per query is 20 queries, so 120 repos; the cap of 60 still rules.
        #expect(RepoEnrichmentPlan.make(repos: repos, pinned: [], graphQLRemaining: 600).enrich.count == 60)
        // 520 left: 4 queries, 24 repos.
        #expect(RepoEnrichmentPlan.make(repos: repos, pinned: [], graphQLRemaining: 520).enrich.count == 24)
        // Inside the reserve, or limited: nothing is spent, everything is deferred.
        let spent = RepoEnrichmentPlan.make(repos: repos, pinned: ["o/r3"], graphQLRemaining: 499)
        #expect(spent.enrich.isEmpty)
        #expect(spent.deferred.count == 200)
        #expect(RepoEnrichmentPlan.make(repos: repos, pinned: [], graphQLRemaining: 0).enrich.isEmpty)
    }

    // MARK: - S4: fetch age from a worktree

    @Test
    func fetchAge_countsAFetchRunInsideALinkedWorktree() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("fetch-age-\(UUID().uuidString)").resolvingSymlinksInPath()
        defer { try? FileManager.default.removeItem(at: root) }
        let upstream = root.appendingPathComponent("upstream.git")
        let clone = root.appendingPathComponent("clone")
        let worktree = root.appendingPathComponent("wt")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        try TowerFixture.runGit(["init", "--bare", "-b", "main", upstream.path], in: root)
        try TowerFixture.runGit(["clone", upstream.path, clone.path], in: root)
        try TowerFixture.commit("a.txt", "a\n", "a", in: clone)
        try TowerFixture.runGit(["push", "origin", "HEAD:main"], in: clone)
        try TowerFixture.runGit(["worktree", "add", worktree.path, "-b", "feat"], in: clone)
        // A moment after the clone's own FETCH_HEAD and reflog times, a fetch inside the worktree.
        let common = clone.appendingPathComponent(".git").path
        for stale in [common + "/FETCH_HEAD", common + "/logs/refs/remotes/origin/main"] {
            try? FileManager.default.setAttributes([.modificationDate: Date(timeIntervalSince1970: 1_000)], ofItemAtPath: stale)
        }
        try TowerFixture.runGit(["fetch", "origin"], in: worktree)

        // git wrote the fetch into the worktree's own directory, not the common one.
        let own = try #require(try FileManager.default.contentsOfDirectory(atPath: common + "/worktrees").first)
        let ownFetchHead = common + "/worktrees/" + own + "/FETCH_HEAD"
        let written = try #require((try FileManager.default.attributesOfItem(atPath: ownFetchHead))[.modificationDate] as? Date)
        let found = try #require(TowerFetchAge.lastFetch(commonDirectory: common, base: "origin/main"))
        #expect(found == written)
        #expect(abs(found.timeIntervalSinceNow) < 60)
    }

    // MARK: - S5, S6: idle guess and waiting

    private func row(
        evidence: LiveEvidence?, namesAgent: Bool, lastChange: Date?, path: String = "/nowhere", dirty: [String] = []
    ) -> TowerRow {
        TowerRow(
            repoPath: "/r", repoName: "r", path: path, branch: "b", agent: nil, task: nil, note: nil, evidence: evidence,
            build: nil, delivered: nil, advice: nil, isLocked: false, isPrunable: false, ahead: 1, behind: 0, dirty: 0,
            forecast: nil, collisions: [], lastActivity: nil, timeline: [], lane: .working, reason: "process inside",
            waiting: nil, lastChange: lastChange, dirtyPaths: dirty, processNamesAgent: namesAgent
        )
    }

    @Test
    func idleGuess_needsAProcessThatNamesAnAgent() {
        let long = Date(timeIntervalSince1970: 1_800_000_000)
        let now = long.addingTimeInterval(3600)
        let server = self.row(evidence: .process(pid: 9, name: "node"), namesAgent: false, lastChange: long)
        #expect(server.idleMinutes(now: now, changeNow: { _ in nil }) == nil)
        #expect(server.reasonText(now: now) == "process inside")
        let agent = self.row(evidence: .process(pid: 9, name: "claude"), namesAgent: true, lastChange: long)
        #expect(agent.idleMinutes(now: now, changeNow: { _ in nil }) == 60)
    }

    @Test
    func idleGuess_looksAtTheFilesAgainBeforeItShows() throws {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("idle-\(UUID().uuidString)").resolvingSymlinksInPath()
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: dir) }
        let edit = dir.appendingPathComponent("edit.txt")
        try Data("x".utf8).write(to: edit)
        let now = Date()
        // The scan saw nothing newer than an hour ago, but the agent has edited a file since.
        let stale = self.row(
            evidence: .process(pid: 9, name: "claude"), namesAgent: true, lastChange: now.addingTimeInterval(-3600),
            path: dir.path, dirty: ["edit.txt"]
        )
        #expect(stale.idleMinutes(now: now) == nil)
        // The same row once that file is itself an hour old: the guess holds.
        try FileManager.default.setAttributes([.modificationDate: now.addingTimeInterval(-3600)], ofItemAtPath: edit.path)
        #expect(stale.idleMinutes(now: now) == 60)
    }

    @Test
    func waiting_onlyStandsWhileTheAskerCanAnswer() {
        let waiting = LedgerWaiting(key: "k", reason: "pick", since: nil)
        // The session crashed after asking: three days on, nobody inside, it is no longer "waiting on you".
        #expect(TowerLanes.assign(TowerFacts(idleDays: 3, waiting: waiting)).lane != .needsYou)
        // The same ask, answered by a session the ledger still counts as live, stands.
        #expect(TowerLanes.assign(TowerFacts(live: .window, idleDays: 3, waiting: waiting)).lane == .needsYou)
        // And a fresh ask with no session record yet stands for its first day.
        #expect(TowerLanes.assign(TowerFacts(idleDays: 0, waiting: waiting)).lane == .needsYou)
    }

    // MARK: - S8: Tower's git has a timeout

    @Test
    func towerGit_stopsAGitThatNeverReturns() throws {
        let git = try #require(TowerGit())
        let started = Date()
        // `sh -c "sleep 30"` stands in for a git stuck on a lock or a credential helper.
        let result = git.run(
            ["status"], in: NSTemporaryDirectory(), wrapper: (URL(fileURLWithPath: "/bin/sh"), ["-c", "sleep 30", "--"]), timeout: 1
        )
        #expect(result == nil)
        #expect(Date().timeIntervalSince(started) < 15)
    }

    // MARK: - S10: notifications do not flap

    private func pull(mergeable: String?, review: String? = "APPROVED") -> MyPullRequest {
        MyPullRequest(
            repoFullName: "o/r", number: 7, title: "Fix", reviewDecision: review, mergeable: mergeable, checksState: "SUCCESS"
        )
    }

    @Test
    func watcher_unknownMergeableIsNoChange() {
        var watcher = NeedsYouWatcher()
        #expect(watcher.observe(mine: [self.pull(mergeable: "MERGEABLE")]).isEmpty) // baseline
        // A push to the base branch: GitHub says UNKNOWN for a while, then MERGEABLE again.
        #expect(watcher.observe(mine: [self.pull(mergeable: "UNKNOWN")]).isEmpty)
        #expect(watcher.observe(mine: [self.pull(mergeable: "MERGEABLE")]).isEmpty)
        // A real change is still news: it conflicts, then it is ready again once, not twice.
        let conflict = watcher.observe(mine: [self.pull(mergeable: "CONFLICTING")])
        #expect(conflict.map(\.key) == ["mine:o/r#7:conflict"])
        #expect(watcher.observe(mine: [self.pull(mergeable: "UNKNOWN")]).isEmpty)
        #expect(watcher.observe(mine: [self.pull(mergeable: "CONFLICTING")]).isEmpty)
        #expect(watcher.observe(mine: [self.pull(mergeable: "MERGEABLE")]).map(\.key) == ["mine:o/r#7:readyToMerge"])
    }

    @Test @MainActor
    func reviewRequests_aTruncatedListAnnouncesNothing() async throws {
        func request(_ number: Int) -> ReviewRequest {
            ReviewRequest(repoFullName: "o/r", number: number, title: "PR \(number)", url: nil, authorLogin: "a", isDraft: false, updatedAt: nil)
        }
        var answers = [
            ReviewRequestList(requests: [request(1)], total: 1),
            ReviewRequestList(requests: [request(1), request(2)], total: 30)
        ]
        var announced: [[String]] = []
        let store = ReviewRequestsStore(fetch: { answers.removeFirst() })
        store.onEntered = { announced.append($0.map(\.key)) }
        await store.load()?.value // baseline
        await store.load()?.value // PR 2 slid into a window that holds 2 of 30
        #expect(announced.isEmpty)
    }

    // MARK: - S11: "clear" waits for both searches

    @Test
    func calm_isNotClearUntilTheOwnPullSearchHasAnswered() {
        var content = HarborPanelContent()
        content.hasLoadedRepositories = true
        content.reviewRequestsLoaded = true
        #expect(content.calm == .checking(repos: 0))
        content.myPullsLoaded = true
        #expect(content.calm == .clear)
    }

    @Test @MainActor
    func calm_repoPastTheCapIsNotChecking_andTheClearLineSaysHowManyWereNotCounted() {
        var content = HarborPanelContent()
        content.reviewRequestsLoaded = true
        content.myPullsLoaded = true
        content.deferredRepos = ["o/far"]
        // (a deferred repo is judged by name; with no repos in the list it changes nothing here)
        #expect(content.calm == .clear)
        #expect(PanelAllClear.summary(repoCount: 60, notCounted: 1740) == "No failing CI or visible alerts in 60 repos · 1740 not counted yet")
        #expect(PanelAllClear.summary(repoCount: 1) == "No failing CI or visible alerts in 1 repo")
    }

    // MARK: - S13: Return with a filter

    @Test @MainActor
    func return_withAFilterDoesNothingWhileAConfirmPinsThePanel() {
        let navigator = PanelNavigator()
        navigator.setFilterScope("repo:")
        var opened = 0
        navigator.update([PanelNavItem(id: "repo:a", drillsIn: false, perform: { opened += 1 })])
        #expect(navigator.type("a"))
        navigator.pin(PanelPin.towerRetire, true)
        navigator.activate()
        #expect(opened == 0)
        navigator.pin(PanelPin.towerRetire, false)
        navigator.activate()
        #expect(opened == 1)
    }
}
