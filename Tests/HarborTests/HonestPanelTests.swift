import Foundation
@testable import Harbor
import HarborCore
import Testing

/// The panel and the app state when nothing may be skipped, stale or calm by accident.
@MainActor
struct HonestPanelTests {
    // MARK: Fixtures

    private func request(_ number: Int) -> ReviewRequest {
        ReviewRequest(repoFullName: "o/a", number: number, title: "PR \(number)", url: nil, authorLogin: nil, isDraft: false, updatedAt: nil)
    }

    private func model(_ name: String, error: String? = nil, known: Bool = true, ci: CIStatus = .passing) -> RepositoryDisplayModel {
        let repo = Repository(
            id: name, name: name, owner: "o", sortOrder: nil, error: error, rateLimitedUntil: nil, ciStatus: ci,
            openIssues: 0, openPulls: 0, latestRelease: nil, latestActivity: nil, traffic: nil, heatmap: [],
            pullCountsKnown: known
        )
        return RepositoryDisplayModel(repo: repo)
    }

    /// Lets a stand-in network call wait until the test says go.
    private final class Gate: @unchecked Sendable {
        private let lock = NSLock()
        private var waiting: [CheckedContinuation<Void, Never>] = []
        private var open = false

        func wait() async {
            await withCheckedContinuation { continuation in
                let proceed = self.lock.withLock { () -> Bool in
                    if self.open { return true }
                    self.waiting.append(continuation)
                    return false
                }
                if proceed { continuation.resume() }
            }
        }

        func release() {
            let pending = self.lock.withLock { () -> [CheckedContinuation<Void, Never>] in
                self.open = true
                defer { self.waiting = [] }
                return self.waiting
            }
            pending.forEach { $0.resume() }
        }
    }

    private final class Counter: @unchecked Sendable {
        private let lock = NSLock()
        private var value = 0
        @discardableResult func next() -> Int { self.lock.withLock { self.value += 1; return self.value } }
        var count: Int { self.lock.withLock { self.value } }
    }

    private func settle(_ state: AppState) async {
        // The refresh AppState starts at launch (its timer ticks on the next main-actor turn)
        // must finish before a test touches the session: signed out, it clears it.
        for _ in 0 ..< 200 where state.refreshTask == nil { try? await Task.sleep(for: .milliseconds(5)) }
        await state.refreshTask?.value
        await state.menuRefreshTask?.value
    }

    private func appState() async -> AppState {
        let state = AppState(platform: MockPlatformServices())
        await self.settle(state)
        return state
    }

    private func waitUntil(_ condition: () -> Bool) async {
        for _ in 0 ..< 400 where !condition() { try? await Task.sleep(for: .milliseconds(5)) }
    }

    // MARK: #2 review requests are fetched every time

    @Test
    func reviewRequests_everyLoadAsksAgain_noMinimumInterval() async {
        let counter = Counter()
        let store = ReviewRequestsStore(fetch: {
            counter.next()
            return ReviewRequestList(requests: [], total: 0)
        })
        await store.load()?.value
        await store.load()?.value
        #expect(counter.count == 2)
    }

    @Test
    func reviewRequests_aSearchInFlightIsJoined_notDuplicated() async {
        let counter = Counter()
        let gate = Gate()
        let store = ReviewRequestsStore(fetch: {
            counter.next()
            await gate.wait()
            return ReviewRequestList(requests: [self.request(1)], total: 1)
        })
        let first = store.load()
        let second = store.load()
        gate.release()
        await first?.value
        await second?.value
        #expect(counter.count == 1)
        #expect(store.requests == [self.request(1)])
    }

    @Test
    func reviewRequests_keepsTheLastListWhileLoading_andShowsAFailure() async {
        let mode = Counter()
        let gate = Gate()
        let store = ReviewRequestsStore(fetch: {
            if mode.next() == 1 { return ReviewRequestList(requests: [self.request(1)], total: 30) }
            await gate.wait()
            throw URLError(.notConnectedToInternet)
        })
        await store.load()?.value
        #expect(store.requests == [self.request(1)])
        #expect(store.total == 30)
        #expect(store.failure == nil)
        let second = store.load()
        // While the new search runs the old list is still what is on screen.
        #expect(store.requests == [self.request(1)])
        gate.release()
        await second?.value
        #expect(store.failure == "No internet connection.")
        #expect(store.requests == [self.request(1)])
    }

    @Test
    func reviewRequests_clearDropsEverything_andALateResultLandsNowhere() async {
        let gate = Gate()
        let store = ReviewRequestsStore(fetch: {
            await gate.wait()
            return ReviewRequestList(requests: [self.request(7)], total: 1)
        })
        let task = store.load()
        store.clear()
        gate.release()
        await task?.value
        #expect(store.requests == [])
        #expect(store.total == nil)
        #expect(store.failure == nil)
    }

    // MARK: #6 calm only when it loaded

    @Test
    func calm_isClearOnlyWhenEveryRepoAnsweredAndTheReviewSearchWorked() {
        var content = HarborPanelContent()
        content.reviewRequestsLoaded = true
        content.repos = [self.model("a"), self.model("b", ci: .unknown)]
        #expect(content.calm == .clear)
        #expect(content.uncheckedNotice == nil)
    }

    @Test
    func calm_aFailedBatchIsCouldntCheck_notGreen() {
        var content = HarborPanelContent()
        content.repos = [self.model("a"), self.model("b", error: "rate limited", known: false, ci: .unknown), self.model("c", error: "x", known: false)]
        #expect(content.calm == .unchecked(repos: 2, reviews: false))
        #expect(content.uncheckedNotice == "Couldn't check 2 repos")
        content.repos = [self.model("b", error: "x", known: false)]
        #expect(content.uncheckedNotice == "Couldn't check 1 repo")
    }

    @Test
    func calm_aFailedReviewSearchIsSurfaced() {
        var content = HarborPanelContent()
        content.repos = [self.model("a")]
        content.reviewRequestsFailure = "No internet connection."
        #expect(content.calm == .unchecked(repos: 0, reviews: true))
        #expect(content.uncheckedNotice == "Couldn't check your review requests")
        content.repos = [self.model("b", error: "x", known: false)]
        #expect(content.uncheckedNotice == "Couldn't check 1 repo or your review requests")
    }

    @Test
    func calm_reposStillWaitingForTheirFirstAnswerAreChecking_notClear() {
        var content = HarborPanelContent()
        content.reviewRequestsLoaded = true
        content.repos = [self.model("a"), self.model("b", known: false, ci: .unknown)]
        #expect(content.calm == .checking(repos: 1))
        #expect(content.uncheckedNotice == nil)
    }

    @Test
    func calm_waitsForTheFirstReviewSearchBeforeSayingAllClear() {
        var content = HarborPanelContent()
        content.repos = [self.model("a")]
        #expect(content.calm == .checking(repos: 0))
        #expect(PanelCheckingNote.text(repoCount: 0) == "Checking your review requests…")
        content.reviewRequestsLoaded = true
        #expect(content.calm == .clear)
    }

    @Test
    func calm_aRefreshFailureBannerIsNeverAllClear() {
        var content = HarborPanelContent()
        content.reviewRequestsLoaded = true
        content.repos = [self.model("a")]
        content.error = "Couldn't list repositories"
        #expect(content.calm == .refreshFailed)
        #expect(content.uncheckedNotice == nil)
    }

    @Test
    func allClear_saysWhatWasChecked() {
        #expect(PanelAllClear.summary(repoCount: 1) == "No failing CI or visible alerts in 1 repo")
        #expect(PanelAllClear.summary(repoCount: 12) == "No failing CI or visible alerts in 12 repos")
    }

    @Test
    func reviewStore_knowsItHasAnsweredOnlyAfterASearchLandsAndForgetsOnClear() async {
        let ok = ReviewRequestsStore(fetch: { ReviewRequestList(requests: [], total: 0) })
        #expect(ok.hasAnswered == false)
        await ok.load()?.value
        #expect(ok.hasAnswered)
        ok.clear()
        #expect(ok.hasAnswered == false)
        let failing = ReviewRequestsStore(fetch: { throw URLError(.notConnectedToInternet) })
        await failing.load()?.value
        #expect(failing.hasAnswered)
        #expect(failing.failure != nil)
    }

    @Test
    func moreReviewRequests_countsWhatGitHubHasBeyondTheRows() {
        var content = HarborPanelContent()
        content.reviewRequests = (1 ... 6).map(self.request)
        content.reviewRequestsTotal = 23
        #expect(content.moreReviewRequests == 23 - HarborPanelContent.maxReviewRows)
        content.reviewRequestsTotal = nil
        #expect(content.moreReviewRequests == 0)
    }

    @Test
    func repoStrip_keepsTheCellsOnScreenWhileLoading() {
        let cell = HeatmapCell(date: Date(timeIntervalSince1970: 0), count: 3)
        var content = HarborPanelContent()
        let repo = self.model("a")
        content.repoActivity[repo.title] = RepoActivitySlice(state: .loading, days: [cell])
        #expect(content.repoStrip(for: repo).activity?.githubDays == [cell])
        content.repoActivity[repo.title] = RepoActivitySlice(state: .loading, days: [])
        #expect(content.repoStrip(for: repo).activity?.isLoadingRepo == true)
    }

    // MARK: #2 app state: nothing is skipped because it was fetched before

    private let cell = HeatmapCell(date: Date(timeIntervalSince1970: 1_000_000), count: 2)

    @Test
    func repoActivity_isFetchedOnEveryDetailOpen() async {
        let state = await self.appState()
        let counter = Counter()
        state.commitActivityLoader = { _, _ in counter.next(); return [self.cell] }
        await state.loadRepoActivity(fullName: "o/r", owner: "o", name: "r", known: [])
        #expect(state.session.repoActivity["o/r"]?.state == .ready)
        await state.loadRepoActivity(fullName: "o/r", owner: "o", name: "r", known: [])
        #expect(counter.count == 2)
    }

    @Test
    func repoActivity_aRepoThatCarriesCellsStillAsksGitHub() async {
        let state = await self.appState()
        let counter = Counter()
        state.commitActivityLoader = { _, _ in counter.next(); return [] }
        await state.loadRepoActivity(fullName: "o/r", owner: "o", name: "r", known: [self.cell])
        #expect(counter.count == 1)
    }

    @Test
    func repoActivity_keepsTheDisplayedCellsWhileTheNewFetchRuns() async {
        let state = await self.appState()
        let gate = Gate()
        let calls = Counter()
        state.commitActivityLoader = { _, _ in
            if calls.next() == 1 { return [self.cell] }
            await gate.wait()
            return []
        }
        await state.loadRepoActivity(fullName: "o/r", owner: "o", name: "r", known: [])
        let second = Task { await state.loadRepoActivity(fullName: "o/r", owner: "o", name: "r", known: []) }
        await self.waitUntil { state.session.repoActivity["o/r"]?.state == .loading }
        #expect(state.session.repoActivity["o/r"] == RepoActivitySlice(state: .loading, days: RepoActivitySlice.pastDays([self.cell])))
        gate.release()
        await second.value
        #expect(state.session.repoActivity["o/r"]?.state == .ready)
    }

    @Test
    func repoActivity_aSecondOpenWhileOneIsInFlightJoinsIt() async {
        let state = await self.appState()
        let gate = Gate()
        let calls = Counter()
        state.commitActivityLoader = { _, _ in calls.next(); await gate.wait(); return [] }
        let first = Task { await state.loadRepoActivity(fullName: "o/r", owner: "o", name: "r", known: []) }
        await self.waitUntil { state.session.repoActivity["o/r"]?.state == .loading }
        await state.loadRepoActivity(fullName: "o/r", owner: "o", name: "r", known: [])
        gate.release()
        await first.value
        #expect(calls.count == 1)
    }

    @Test
    func contributionYears_areFetchedEveryTimeAllTimeIsChosen() async {
        let state = await self.appState()
        state.session.account = .loggedIn(UserIdentity(username: "ada", host: URL(string: "https://github.com")!))
        let counter = Counter()
        state.contributionYearsLoader = { _ in counter.next(); return [] }
        await state.loadContributionYearsIfNeeded(range: .allTime)
        #expect(state.session.contributionYearsState == .ready)
        await state.loadContributionYearsIfNeeded(range: .allTime)
        #expect(counter.count == 2)
    }

    @Test
    func providerActivity_isNotSkippedWhenReady_andRetriesAfterAFailureAtOnce() async {
        let state = await self.appState()
        let calls = Counter()
        state.providerActivityLoader = { provider, _, _ in
            if calls.next() == 3 { throw URLError(.notConnectedToInternet) }
            return ProviderActivityResult(provider: provider, days: [])
        }
        await state.loadProviderActivity(.gitlab, days: 30)
        await state.loadProviderActivity(.gitlab, days: 30)
        #expect(calls.count == 2)
        await state.loadProviderActivity(.gitlab, days: 30)
        #expect(state.session.providerActivity[.gitlab]?.state == .failed("unreachable"))
        // No 90-second quiet period: the next open asks again.
        await state.loadProviderActivity(.gitlab, days: 30)
        #expect(calls.count == 4)
        #expect(state.session.providerActivity[.gitlab]?.state == .ready)
    }

    @Test
    func menuOpen_refreshesEvenWithAFreshSnapshot() async {
        let state = await self.appState()
        state.session.menuSnapshot = MenuSnapshot(repositories: [], capturedAt: Date())
        state.refreshIfNeededForMenu()
        #expect(state.menuRefreshTask != nil)
        // A second open while that one is pending joins it.
        let pending = state.menuRefreshTask
        state.refreshIfNeededForMenu()
        #expect(state.menuRefreshTask == pending)
        await state.menuRefreshTask?.value
    }

    // MARK: #2 sign-out and account switch clear everything of the last account

    private func fill(_ state: AppState) {
        let session = state.session
        session.repositories = [Repository(
            id: "1", name: "r", owner: "o", sortOrder: nil, error: nil, rateLimitedUntil: nil, ciStatus: .passing,
            openIssues: 0, openPulls: 0, latestRelease: nil, latestActivity: nil, traffic: nil, heatmap: []
        )]
        session.hasLoadedRepositories = true
        session.repoActivity["o/r"] = RepoActivitySlice(state: .ready, days: [self.cell])
        session.contributionYears = [ContributionYear(year: 2025, total: 9, commits: 9, pullRequests: 0, issues: 0, reviews: 0)]
        session.contributionYearsState = .ready
        session.providerActivity[.gitlab] = ProviderActivitySlice(state: .ready, days: [], coveredDays: 30)
        session.contributionHeatmap = [self.cell]
        session.contributionUser = "alice"
        session.globalActivityEvents = [ActivityEvent(title: "t", actor: "alice", date: Date(), url: URL(string: "https://x.test")!)]
    }

    @Test
    func accountSwitch_clearsEveryUserScopedThing() async {
        let state = await self.appState()
        #expect(state.adoptAccountData(for: "alice") == false)
        self.fill(state)
        #expect(state.adoptAccountData(for: "ALICE") == false)
        #expect(state.session.repoActivity.count == 1)
        let epoch = state.scopeEpoch
        #expect(state.adoptAccountData(for: "bob") == true)
        let session = state.session
        #expect(session.repositories == [])
        #expect(session.hasLoadedRepositories == false)
        #expect(session.repoActivity == [:])
        #expect(session.contributionYears == [])
        #expect(session.contributionYearsState == .idle)
        #expect(session.providerActivity == [:])
        #expect(session.contributionHeatmap == [])
        #expect(session.contributionUser == nil)
        #expect(session.globalActivityEvents == [])
        #expect(state.scopeEpoch == epoch + 1)
        #expect(state.dataOwner == "bob")
    }

    @Test
    func signOut_clearsTheSameState() async {
        let state = await self.appState()
        self.fill(state)
        state.clearUserScopedState()
        #expect(state.session.repoActivity == [:])
        #expect(state.session.contributionYears == [])
        #expect(state.session.providerActivity == [:])
        #expect(state.dataOwner == nil)
    }

    private var alice: UserIdentity { UserIdentity(username: "alice", host: URL(string: "https://github.com")!) }

    /// The action both sign-out buttons run, not `clearUserScopedState` called by the test.
    @Test
    func signOut_theRealActionClearsAtOnceAndBumpsTheEpoch() async {
        let state = await self.appState()
        state.session.account = .loggedIn(self.alice)
        state.dataOwner = "alice"
        self.fill(state)
        state.session.menuSnapshot = MenuSnapshot(repositories: state.session.repositories, capturedAt: Date())
        let epoch = state.scopeEpoch
        await state.signOut()
        #expect(state.session.account == .loggedOut)
        #expect(state.session.repositories == [])
        #expect(state.session.menuSnapshot == nil)
        #expect(state.session.repoActivity == [:])
        #expect(state.session.contributionYears == [])
        #expect(state.session.providerActivity == [:])
        #expect(state.session.globalActivityEvents == [])
        #expect(state.dataOwner == nil)
        #expect(state.scopeEpoch == epoch + 1)
    }

    @Test
    func signOut_dropsALoadStartedBeforeIt() async {
        let state = await self.appState()
        let gate = Gate()
        state.commitActivityLoader = { _, _ in await gate.wait(); return [self.cell] }
        let load = Task { await state.loadRepoActivity(fullName: "o/r", owner: "o", name: "r", known: []) }
        await self.waitUntil { state.session.repoActivity["o/r"]?.state == .loading }
        await state.signOut()
        gate.release()
        await load.value
        #expect(state.session.repoActivity["o/r"] == nil)
    }

    @Test
    func signIn_bumpsTheEpochSoAnOlderRefreshCannotMergeIn() async {
        let state = await self.appState()
        let epoch = state.scopeEpoch
        state.accountSignedIn(self.alice)
        #expect(state.scopeEpoch == epoch + 1)
        #expect(state.session.account == .loggedIn(self.alice))
    }

    @Test
    func accountChange_runsTheRegisteredResets() async {
        let state = await self.appState()
        let counter = Counter()
        state.accountScopeResets.append { counter.next() }
        await state.signOut()
        #expect(counter.count == 1)
        state.dataOwner = "alice"
        #expect(state.adoptAccountData(for: "bob"))
        #expect(counter.count == 2)
    }

    @Test
    func recentLists_areForgottenOnAccountChange() {
        let cache = RecentListCache<Int>()
        cache.store([1, 2], for: "o/r")
        #expect(cache.lastShown(for: "o/r") == [1, 2])
        cache.clear()
        #expect(cache.lastShown(for: "o/r") == nil)
    }

    @Test
    func aSignedOutRefreshDoesNotBumpTheEpochEveryTime() async {
        let state = await self.appState()
        let epoch = state.scopeEpoch
        await state.refresh()
        await state.refresh()
        #expect(state.scopeEpoch == epoch)
        // But tokens that vanished under data still on screen clear it, once.
        state.dataOwner = "alice"
        await state.refresh()
        #expect(state.scopeEpoch == epoch + 1)
        await state.refresh()
        #expect(state.scopeEpoch == epoch + 1)
    }

    @Test
    func healthAlertsFromAnOlderAccountAreDropped() async {
        let state = await self.appState()
        self.fill(state)
        let old = state.scopeEpoch
        state.accountSignedIn(self.alice)
        state.session.repositories = [Repository(
            id: "1", name: "r", owner: "o", sortOrder: nil, error: nil, rateLimitedUntil: nil, ciStatus: .passing,
            openIssues: 0, openPulls: 0, latestRelease: nil, latestActivity: nil, traffic: nil, heatmap: []
        )]
        state.applyHealthAlerts(fullName: "o/r", alerts: RepoSecurity(dependabot: DependabotTally(critical: 1, high: 0, medium: 0, low: 0), secretLeaks: 2, codeScanning: 3), epoch: old)
        #expect(state.session.repositories.first?.security == nil)
        state.applyHealthAlerts(fullName: "o/r", alerts: RepoSecurity(dependabot: DependabotTally(critical: 1, high: 0, medium: 0, low: 0), secretLeaks: 2, codeScanning: 3), epoch: state.scopeEpoch)
        #expect(state.session.repositories.first?.security == RepoSecurity(dependabot: DependabotTally(critical: 1, high: 0, medium: 0, low: 0), secretLeaks: 2, codeScanning: 3))
    }

    @Test
    func aLoadStartedForTheOldAccountDropsItsResult() async {
        let state = await self.appState()
        let gate = Gate()
        state.commitActivityLoader = { _, _ in await gate.wait(); return [self.cell] }
        let load = Task { await state.loadRepoActivity(fullName: "o/r", owner: "o", name: "r", known: []) }
        await self.waitUntil { state.session.repoActivity["o/r"]?.state == .loading }
        state.clearUserScopedState()
        gate.release()
        await load.value
        #expect(state.session.repoActivity["o/r"] == nil)
    }
}
