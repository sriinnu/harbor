import AppKit
import Foundation
@testable import Harbor
@testable import HarborCore
import Testing

/// 0.2.3 re-review fixes: Tower's honest "couldn't check", the not-counted note, repos opened this
/// session staying counted, and the auto-sync wording. Temp git repos and fake git only; no
/// network, no Keychain.
struct ReReviewFixesTests {
    // MARK: - N2: a repo git can't answer about is unknown, not absent

    /// The real git, except that `git worktree list` hangs (exec'd, so the timeout kills the sleep itself).
    private func hangingGit(in root: URL) throws -> FixedLocator {
        let script = root.appendingPathComponent("hanging-git")
        try Data("""
        #!/bin/sh
        case "$*" in
          *"worktree list"*) exec sleep 30;;
        esac
        exec /usr/bin/git "$@"
        """.utf8).write(to: script)
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: script.path)
        return FixedLocator(url: script)
    }

    @Test
    func scanner_aListingThatTimesOutIsCouldNotRead_notNoWorktrees() throws {
        let fixture = try TowerFixture()
        defer { fixture.remove() }
        let git = try #require(TowerGit(locator: try self.hangingGit(in: fixture.root), timeout: 0.5))
        let scanner = TowerScanner(git: git, home: fixture.root.path, host: "h", now: Date(), probe: NeverAlive())
        guard case .couldNotRead = scanner.scanOutcome(repo: fixture.repo.path, ledger: [:], emit: { _ in }) else {
            Issue.record("a timed-out `git worktree list` must be couldNotRead")
            return
        }
        // A directory that is not a repo is a plain "nothing here".
        let plain = fixture.root.appendingPathComponent("plain")
        try FileManager.default.createDirectory(at: plain, withIntermediateDirectories: true)
        let real = TowerScanner(git: try #require(TowerGit()), home: fixture.root.path, host: "h", now: Date(), probe: NeverAlive())
        guard case .noWorktrees = real.scanOutcome(repo: plain.path, ledger: [:], emit: { _ in }) else {
            Issue.record("a non-repo must be noWorktrees")
            return
        }
    }

    @Test @MainActor
    func model_aRepoWhoseListingTimesOutIsShownAsUnchecked_andTheBadgeIsNotCalm() async throws {
        let fixture = try TowerFixture()
        defer { fixture.remove() }
        let model = TowerModel(
            tail: LedgerTail(url: fixture.root.appendingPathComponent("events.jsonl")), locator: try self.hangingGit(in: fixture.root),
            home: fixture.root.path, gitTimeout: 0.5, pullFetch: { nil }
        )
        model.start(rootPaths: [fixture.root.path])
        defer { model.stop() }
        let deadline = ContinuousClock.now + .seconds(20)
        while model.uncheckedRepos.isEmpty, ContinuousClock.now < deadline { try await Task.sleep(for: .milliseconds(50)) }

        #expect(model.uncheckedRepos == [fixture.repo.path])
        // Not counted as a clear repo: with nothing else waiting the icon is the unchecked ring, never "calm".
        var content = HarborPanelContent()
        content.hasLoadedRepositories = true
        content.reviewRequestsLoaded = true
        content.myPullsLoaded = true
        let account = AccountState.loggedIn(UserIdentity(username: "me", host: URL(string: "https://github.com")!))
        #expect(StatusItemBadge(account: account, content: content, towerNeedsYou: model.needsYouCount, towerUnchecked: model.uncheckedRepos.count) == .unchecked)
        #expect(StatusItemBadge(account: account, content: content, towerNeedsYou: 0, towerUnchecked: 0) == .calm)
        #expect(StatusItemBadge(account: account, content: content, towerNeedsYou: 2, towerUnchecked: 1) == .needsYou(2))
    }

    // MARK: - N3: the cap is stated beside Needs you too

    @Test
    func notCountedNote_showsWheneverReposAreDeferred_andNotTwiceOnTheAllClearLine() {
        var content = HarborPanelContent()
        content.hasLoadedRepositories = true
        content.reviewRequestsLoaded = true
        content.myPullsLoaded = true
        content.deferredRepos = ["o/a", "o/b", "o/c"]
        // All clear: the clear line says it itself.
        #expect(content.needsYou.isEmpty)
        #expect(content.calm == .clear)
        #expect(content.notCountedNote == nil)
        // One review request waiting: Needs you shows, and the note comes with it.
        content.reviewRequests = [ReviewRequest(repoFullName: "o/a", number: 1, title: "PR", url: nil, authorLogin: nil, isDraft: false, updatedAt: nil)]
        #expect(content.needsYou.count == 1)
        #expect(content.notCountedNote == "3 repos not counted yet")
        content.deferredRepos = ["o/a"]
        #expect(content.notCountedNote == "1 repo not counted yet")
        content.deferredRepos = []
        #expect(content.notCountedNote == nil)
    }

    // MARK: - N4: a repo opened this session stays in the counted set

    private func repo(_ name: String, pushedDaysAgo: Int) -> Repository {
        Repository(
            id: "o/\(name)", name: name, owner: "o", sortOrder: nil, error: nil, rateLimitedUntil: nil, ciStatus: .unknown,
            openIssues: 0, openPulls: 0, pushedAt: Date(timeIntervalSince1970: 1_800_000_000 - Double(pushedDaysAgo) * 86400),
            latestRelease: nil, latestActivity: nil, traffic: nil, heatmap: [], pullCountsKnown: false
        )
    }

    @Test
    func plan_aRepoOpenedThisSessionStaysCountedBesideThePinnedAndRecent() {
        let repos = (0 ..< 200).map { self.repo("r\($0)", pushedDaysAgo: $0) }
        let without = RepoEnrichmentPlan.make(repos: repos, pinned: ["o/r3"], graphQLRemaining: nil)
        #expect(without.deferred.contains { $0.fullName == "o/r150" })

        let with = RepoEnrichmentPlan.make(repos: repos, pinned: ["o/r3"], opened: ["o/r150"], graphQLRemaining: nil)
        #expect(with.enrich.map(\.fullName).prefix(2) == ["o/r3", "o/r150"])
        #expect(with.enrich.count == 62) // pinned, opened, then the 60 newest of the rest
        #expect(with.deferred.contains { $0.fullName == "o/r150" } == false)
        // The budget still rules: nothing is spent inside the reserve, opened or not.
        #expect(RepoEnrichmentPlan.make(repos: repos, pinned: [], opened: ["o/r150"], graphQLRemaining: 499).enrich.isEmpty)
    }

    @Test
    func session_remembersAtMostTheLastTwentyOpenedRepos_newestKept() {
        let session = Session()
        for index in 0 ..< 25 { session.noteOpened("o/r\(index)") }
        session.noteOpened("o/r10") // opened again: moves to the end, no duplicate
        #expect(session.openedRepoNames.count == Session.openedCap)
        #expect(session.openedRepoNames.last == "o/r10")
        #expect(session.openedRepoNames.first == "o/r5")
        #expect(session.openedRepoNames.filter { $0 == "o/r10" }.count == 1)
    }

    // MARK: - auto-sync wording

    @Test
    func autoSyncText_followsTheFetchIntervalNotEveryRefresh() {
        #expect(LocalGitSettingsView.autoSyncDetail
            == "Off by default. When on, Harbor pulls with --ff-only in clones with a clean working tree, each time it fetches (see Fetch every).")
    }
}
