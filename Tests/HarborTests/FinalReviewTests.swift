import Foundation
@testable import Harbor
import HarborCore
import Testing

/// The final review's findings, one test group each.
@MainActor
struct FinalReviewTests {
    // MARK: Fixtures

    private static let user = UserIdentity(username: "me", host: URL(string: "https://github.com")!)

    private func repo(_ name: String, ci: CIStatus = .passing) -> Repository {
        Repository(
            id: name, name: name, owner: "o", sortOrder: nil, error: nil, rateLimitedUntil: nil, ciStatus: ci,
            openIssues: 0, openPulls: 0, latestRelease: nil, latestActivity: nil, traffic: nil, heatmap: [],
            pullCountsKnown: true
        )
    }

    /// The refresh AppState starts at launch must finish before a test touches the session.
    private func appState() async -> AppState {
        let state = AppState(platform: MockPlatformServices())
        for _ in 0 ..< 200 where state.refreshTask == nil { try? await Task.sleep(for: .milliseconds(5)) }
        await state.refreshTask?.value
        await state.menuRefreshTask?.value
        return state
    }

    private final class Counter: @unchecked Sendable {
        private let lock = NSLock()
        private var value = 0
        @discardableResult func next() -> Int { self.lock.withLock { self.value += 1; return self.value } }
        var count: Int { self.lock.withLock { self.value } }
    }

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

    // MARK: 1. the icon counts every repo, not the listed ones

    @Test
    func icon_aFailingRepoBelowTheDisplayLimitStillNeedsYou() async {
        let state = await self.appState()
        state.session.account = .loggedIn(Self.user)
        state.session.hasLoadedRepositories = true
        let repos = (0 ..< 40).map { self.repo(String(format: "r%02d", $0), ci: $0 == 6 ? .failing : .passing) }
        state.session.repositories = repos
        state.session.settings.repoList.displayLimit = 6
        // Pinned repos sort first, so the first six rows are r00...r05 and the failing r06 is seventh.
        state.session.settings.repoList.pinnedRepositories = (0 ..< 6).map { String(format: "o/r%02d", $0) }
        let manager = StatusBarMenuManager(appState: state)
        let content = manager.panelContent()
        #expect(content.repos.map(\.title) == (0 ..< 6).map { String(format: "o/r%02d", $0) })
        #expect(content.judgedRepos.count == 40)
        #expect(content.needsYou.map(\.title) == ["o/r06"])
        #expect(StatusItemBadge(account: .loggedIn(Self.user), content: content) == .needsYou(1))
    }

    @Test
    func panel_theAllClearCountIsEveryRepoNotTheListedRows() {
        var content = HarborPanelContent()
        content.hasLoadedRepositories = true
        content.reviewRequestsLoaded = true
        content.repos = (0 ..< 6).map { RepositoryDisplayModel(repo: self.repo("r\($0)")) }
        content.judged = (0 ..< 40).map { RepositoryDisplayModel(repo: self.repo("r\($0)")) }
        #expect(content.calm == .clear)
        #expect(content.judgedRepos.count == 40)
        #expect(content.repos.count == 6)
    }

    // MARK: 2. review requests across sign-in

    @Test
    func reviewRequests_aFailureFromBeforeSignInIsGoneAfterIt() async {
        let state = await self.appState()
        let store = ReviewRequestsStore(fetch: { throw URLError(.notConnectedToInternet) })
        state.reviewRequests = store
        await store.load()?.value
        #expect(store.failure == "No internet connection.")
        #expect(store.hasAnswered)
        state.accountSignedIn(Self.user)
        #expect(store.failure == nil)
        #expect(store.hasAnswered == false)
    }

    @Test
    func reviewRequests_noSearchWhileSignedOut_andOneEachTimeSignedIn() async {
        let state = await self.appState()
        let counter = Counter()
        state.reviewRequests = ReviewRequestsStore(fetch: {
            counter.next()
            throw URLError(.notConnectedToInternet)
        })
        #expect(state.searchReviewRequests() == nil)
        StatusBarMenuManager(appState: state).panelWillOpen()
        #expect(counter.count == 0)
        state.session.account = .loggedIn(Self.user)
        // A refresh calls this too: each call asks again, so a failed search is retried.
        await state.searchReviewRequests()?.value
        await state.searchReviewRequests()?.value
        #expect(counter.count == 2)
    }

    // MARK: 3. a signed-out refresh can't blank a new account's list

    @Test
    func signedOutRefresh_aSignInDuringTheScanKeepsTheNewAccountsList() async {
        let state = await self.appState()
        let snapshot = LocalRepoManager.SnapshotResult(discoveredCount: 0, repoIndex: .empty, accessDenied: false)
        state.session.localProjectsScanInProgress = true
        state.session.repositories = [self.repo("keep")]
        state.session.hasLoadedRepositories = true
        let epoch = state.scopeEpoch
        state.accountSignedIn(Self.user) // sign-in completes while the scan runs
        await state.applySignedOutSnapshot(snapshot, epoch: epoch)
        #expect(state.session.repositories.map(\.name) == ["keep"])
        #expect(state.session.hasLoadedRepositories)
        // The stale refresh still ends its scan (finding 7).
        #expect(state.session.localProjectsScanInProgress == false)
        // The current epoch wipes, as before.
        await state.applySignedOutSnapshot(snapshot, epoch: state.scopeEpoch)
        #expect(state.session.repositories.isEmpty)
        #expect(state.session.hasLoadedRepositories == false)
    }

    @Test
    func aSupersededRefreshEndsItsScan() async {
        let state = await self.appState()
        state.session.localProjectsScanInProgress = true
        state.endSupersededScan()
        #expect(state.session.localProjectsScanInProgress == false)
    }

    // MARK: 6. the account reset is ordered

    @Test
    func accountReset_signOutWaitsForItBeforeReturning() async {
        let state = await self.appState()
        let finished = Counter()
        state.accountReset = {
            try? await Task.sleep(for: .milliseconds(150))
            finished.next()
        }
        await state.signOut()
        #expect(finished.count == 1)
    }

    @Test
    func accountReset_twoQuickChangesRunInOrder() async {
        let state = await self.appState()
        let order = OrderBox()
        let counter = Counter()
        state.accountReset = {
            let mine = counter.next()
            if mine == 1 { try? await Task.sleep(for: .milliseconds(120)) }
            order.append(mine)
        }
        state.clearUserScopedState()
        state.clearUserScopedState()
        await state.settleAccountReset()
        #expect(order.values == [1, 2])
    }

    private final class OrderBox: @unchecked Sendable {
        private let lock = NSLock()
        private var items: [Int] = []
        func append(_ value: Int) { self.lock.withLock { self.items.append(value) } }
        var values: [Int] { self.lock.withLock { self.items } }
    }

    // MARK: 7. the heatmap fetch drops a late answer

    @Test
    func heatmap_aResponseThatLandsAfterSignOutIsDropped() async {
        let state = await self.appState()
        state.session.account = .loggedIn(Self.user)
        state.session.hasLoadedRepositories = true
        state.session.settings.appearance.showContributionHeader = true
        let gate = Gate()
        state.contributionHeatmapLoader = { _ in
            await gate.wait()
            return [HeatmapCell(date: Date(timeIntervalSince1970: 0), count: 3)]
        }
        let load = Task { await state.loadContributionHeatmap(for: "me") }
        try? await Task.sleep(for: .milliseconds(50))
        await state.signOut()
        gate.release()
        await load.value
        #expect(state.session.contributionHeatmap == [])
        #expect(state.session.contributionUser == nil)
    }

    // MARK: 7. panel actions respect the pins

    @Test
    func panelActions_closeThroughThePinsLikeAnOutsideClick() {
        let controller = HarborPanelController()
        let navigator = PanelNavigator()
        controller.navigator = navigator
        navigator.pin(PanelPin.towerExecuting, true)
        controller.closeFromAction()
        #expect(controller.navigator === navigator)
        navigator.pin(PanelPin.towerExecuting, false)
        controller.closeFromAction()
        #expect(controller.navigator == nil)
    }

    // MARK: 7. a running cleanup holds the detail

    @Test
    func cleanup_whileDeletingTheDetailStaysAndEscapeIsSwallowed() {
        let navigator = PanelNavigator()
        #expect(navigator.blocksLeavingDetail == false)
        #expect(navigator.blocksEscape == false)
        // Scanning or confirming pins the panel but may still be left.
        navigator.pin(PanelPin.runCleanup, true)
        #expect(navigator.blocksLeavingDetail == false)
        navigator.pin(PanelPin.runCleanupDeleting, true)
        #expect(navigator.blocksLeavingDetail)
        #expect(navigator.blocksEscape)
        navigator.pin(PanelPin.runCleanupDeleting, false)
        #expect(navigator.blocksLeavingDetail == false)
    }
}
