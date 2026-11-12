import Foundation
import HarborCore

extension AppState {
    /// Opening the menu or panel always refreshes. Only a refresh already running is joined,
    /// so there is never a second one beside it; a finished one never stands in for a new one.
    func refreshIfNeededForMenu() {
        if self.refreshTask != nil || self.menuRefreshTask != nil { return }
        self.menuRefreshTask = Task { [weak self] in
            try? await Task.sleep(for: .milliseconds(250))
            await MainActor.run {
                guard let self else { return }
                self.menuRefreshTask = nil
                self.requestRefresh(cancelInFlight: false)
            }
        }
    }

    func requestRefresh(cancelInFlight: Bool = false) {
        if cancelInFlight {
            self.refreshTask?.cancel()
        }
        guard cancelInFlight || self.refreshTask == nil else { return }
        let token = UUID()
        self.refreshTaskToken = token
        self.refreshTask = Task { [weak self] in
            await self?.refresh()
            await MainActor.run {
                guard let self, self.refreshTaskToken == token else { return }
                self.refreshTask = nil
            }
        }
    }

    func refresh() async {
        // The account this refresh works for. Sign-out and sign-in bump it, and then everything
        // this refresh still has to write is somebody else's data and is dropped.
        let startEpoch = self.scopeEpoch
        var failureEpoch = startEpoch
        let localSettings = self.session.settings.localProjects
        self.session.localProjectsScanInProgress = localSettings.rootPaths.contains { $0.isEmpty == false }
        do {
            if Task.isCancelled { return }
            let now = Date()
            self.updateHeatmapRange(now: now)
            if self.auth.loadTokens() == nil {
                // Signed out: nothing of the last account stays on screen. Sign-out clears at
                // once; this catches tokens that vanished some other way, once, not on every refresh.
                if self.dataOwner != nil { self.clearUserScopedState() }
                // Read after the clear, which bumps the epoch itself: this is the epoch a sign-in
                // during the local scan below would move.
                let signedOutEpoch = self.scopeEpoch
                let matchNames = self.localMatchRepoNamesForLocalProjects(repos: [], includePinned: true)
                let localSnapshot = await self.localRepoManager.snapshot(
                    rootPaths: localSettings.rootPaths,
                    rootBookmarks: localSettings.rootBookmarks,
                    options: LocalRepoManager.SnapshotOptions(
                        autoSyncEnabled: localSettings.autoSyncEnabled,
                        fetchInterval: localSettings.fetchInterval.seconds,
                        preferredPathsByFullName: localSettings.preferredLocalPathsByFullName,
                        matchRepoNames: matchNames,
                        forceRescan: false
                    )
                )
                await self.applySignedOutSnapshot(localSnapshot, epoch: signedOutEpoch)
                return
            }
            // If we have tokens but no user in session, fetch identity once per launch.
            if case .loggedOut = self.session.account {
                if let user = try? await self.github.currentUser() {
                    await MainActor.run { self.session.account = .loggedIn(user) }
                    // The pre-accounts Keychain item gets its own account key now that the login is known.
                    await self.migrateLegacyAccountIfNeeded()
                }
            }
            // A different account than the one whose data is on screen starts from nothing.
            var adopted = false
            if case let .loggedIn(user) = self.session.account { adopted = self.adoptAccountData(for: user.username) }
            // Adopting a different account bumps the epoch itself; this refresh belongs to the new one.
            let epoch = adopted ? self.scopeEpoch : startEpoch
            failureEpoch = epoch
            // A request for the new account must not meet the old account's limits.
            await self.settleAccountReset()
            guard epoch == self.scopeEpoch else { return self.endSupersededScan() }
            // The review search runs on every refresh, not only when the panel opens, so a
            // failed one is retried and never pins the icon on the unchecked ring.
            self.searchReviewRequests()
            self.searchMyPulls()
            // 1. The list: one REST listing (plus orgs, side by side). It names every repo and is
            //    enough to draw the menu, so show it before any count has arrived.
            let listed = try await self.github.listRepositories(limit: nil, pinned: self.session.settings.repoList.pinnedRepositories)
            try Task.checkCancellation()
            guard epoch == self.scopeEpoch else { return self.endSupersededScan() }
            let visible = self.applyVisibilityFilters(to: listed)
            let ordered = self.applyPinnedOrder(to: visible)
            let matchNames = self.localMatchRepoNamesForLocalProjects(repos: ordered, includePinned: true)
            let onScreen = Dictionary(self.session.repositories.map { ($0.fullName, $0) }, uniquingKeysWith: { first, _ in first })
            // Only a bounded set is counted: pinned, the newest pushes, whatever the GraphQL
            // budget pays for. The rest stay "not counted" (the fresh list row, never an old
            // count) and are counted when their detail opens.
            let plan = RepoEnrichmentPlan.make(
                repos: ordered,
                pinned: Set(self.session.settings.repoList.pinnedRepositories),
                opened: Set(self.session.openedRepoNames),
                graphQLRemaining: await self.github.graphQLPointsRemaining(now: now)
            )
            let deferredNames = Set(plan.deferred.map(\.fullName))
            let drawn = ordered.map { fresh in
                deferredNames.contains(fresh.fullName) ? fresh : (onScreen[fresh.fullName]?.updatingListFields(from: fresh) ?? fresh)
            }
            self.session.deferredRepoNames = deferredNames
            await self.updateSession(with: drawn, now: now, epoch: epoch)
            await self.updateMenuDisplayIndex(now: now, epoch: epoch)

            // 2. Everything else at once: local git, the activity feeds, and the counts for every
            //    repo in a few batched GraphQL requests that land one by one.
            let localSnapshotTask = Task {
                await self.localRepoManager.snapshot(
                    rootPaths: localSettings.rootPaths,
                    rootBookmarks: localSettings.rootBookmarks,
                    options: LocalRepoManager.SnapshotOptions(
                        autoSyncEnabled: localSettings.autoSyncEnabled,
                        fetchInterval: localSettings.fetchInterval.seconds,
                        preferredPathsByFullName: localSettings.preferredLocalPathsByFullName,
                        matchRepoNames: matchNames,
                        forceRescan: false
                    )
                )
            }
            let activityUsername: String? = {
                guard case let .loggedIn(user) = self.session.account,
                      user.username.isEmpty == false else { return nil }
                return user.username
            }()
            let scope = self.session.settings.appearance.activityScope
            let globalActivityTask = Task { [weak self] in
                guard let self, let activityUsername else {
                    return GlobalActivityResult(events: [], commits: [], error: nil, commitError: nil)
                }
                return await self.fetchGlobalActivityEvents(username: activityUsername, scope: scope, repos: drawn)
            }
            let token = self.refreshTaskToken
            await self.github.enrich(drawn.filter { !deferredNames.contains($0.fullName) }) { [weak self] batch in
                await self?.merge(batch: batch, token: token, epoch: epoch, now: now)
            }
            try Task.checkCancellation()
            guard epoch == self.scopeEpoch else { return self.endSupersededScan() }
            let localSnapshot = await localSnapshotTask.value
            let globalActivity = await globalActivityTask.value
            await MainActor.run {
                self.session.localRepoIndex = localSnapshot.repoIndex
                self.session.localDiscoveredRepoCount = localSnapshot.discoveredCount
                self.session.localProjectsAccessDenied = localSnapshot.accessDenied
                self.session.localProjectsScanInProgress = false
                guard epoch == self.scopeEpoch else { return }
                self.session.globalActivityEvents = globalActivity.events
                self.session.globalActivityError = globalActivity.error
                self.session.globalCommitEvents = globalActivity.commits
                self.session.globalCommitError = globalActivity.commitError
            }
            await self.updateMenuDisplayIndex(now: now, epoch: epoch)
            let tally = await RequestTally.shared.drain()
            await DiagnosticsLogger.shared.message("refresh done: " + RequestTally.summary(tally))
            let reset = await self.github.rateLimitReset(now: now)
            let message = await self.github.rateLimitMessage(now: now)
            await MainActor.run {
                guard epoch == self.scopeEpoch else { return }
                self.session.rateLimitReset = reset
                self.session.lastError = message
            }
        } catch {
            // A refresh that failed early still counted its requests; start the next from zero.
            let tally = await RequestTally.shared.drain()
            await DiagnosticsLogger.shared.message("refresh failed: " + RequestTally.summary(tally))
            let reportEpoch = failureEpoch
            await MainActor.run {
                self.session.localProjectsScanInProgress = false
                // A superseded refresh ends in URLError.cancelled ("cancelled"); the one that
                // replaced it reports for both, so this one stays silent.
                if reportEpoch == self.scopeEpoch, let message = error.reportableMessage { self.session.lastError = message }
            }
        }
    }

    /// The end of a signed-out refresh: the local scan has landed, so the account's leftovers go
    /// and the local index is filled in. Only while the epoch is still the one the refresh
    /// started under; a sign-in during the scan owns the session now, and its list stays.
    func applySignedOutSnapshot(_ snapshot: LocalRepoManager.SnapshotResult, epoch: Int) async {
        await MainActor.run {
            self.session.localProjectsScanInProgress = false
            guard epoch == self.scopeEpoch else { return }
            self.session.repositories = []
            self.session.menuSnapshot = nil
            self.session.menuDisplayIndex = [:]
            self.session.hasLoadedRepositories = false
            self.session.lastError = nil
            self.session.localRepoIndex = snapshot.repoIndex
            self.session.localDiscoveredRepoCount = snapshot.discoveredCount
            self.session.localProjectsAccessDenied = snapshot.accessDenied
            self.session.globalActivityEvents = []
            self.session.globalActivityError = nil
            self.session.globalCommitEvents = []
            self.session.globalCommitError = nil
        }
    }

    /// A refresh that stopped early because its account is gone leaves no scan running.
    func endSupersededScan() {
        self.session.localProjectsScanInProgress = false
    }

    func refreshLocalProjects(cancelInFlight: Bool = true, forceRescan: Bool = false) {
        if cancelInFlight {
            self.localProjectsTask?.cancel()
        }

        let settings = self.session.settings.localProjects
        guard settings.rootPaths.contains(where: { $0.isEmpty == false }) else {
            self.session.localRepoIndex = .empty
            self.session.localDiscoveredRepoCount = 0
            self.session.localProjectsAccessDenied = false
            self.session.localProjectsScanInProgress = false
            return
        }

        self.session.localProjectsScanInProgress = true
        self.localProjectsTask = Task { [weak self] in
            guard let self else { return }
            let matchNames = self.localMatchRepoNamesForLocalProjects(
                repos: self.session.repositories.isEmpty
                    ? (self.session.menuSnapshot?.repositories ?? [])
                    : self.session.repositories,
                includePinned: true
            )
            let localSnapshot = await self.localRepoManager.snapshot(
                rootPaths: settings.rootPaths,
                rootBookmarks: settings.rootBookmarks,
                options: LocalRepoManager.SnapshotOptions(
                    autoSyncEnabled: settings.autoSyncEnabled,
                    fetchInterval: settings.fetchInterval.seconds,
                    preferredPathsByFullName: settings.preferredLocalPathsByFullName,
                    matchRepoNames: matchNames,
                    forceRescan: forceRescan
                )
            )
            await MainActor.run {
                self.session.localRepoIndex = localSnapshot.repoIndex
                self.session.localDiscoveredRepoCount = localSnapshot.discoveredCount
                self.session.localProjectsAccessDenied = localSnapshot.accessDenied
                self.session.localProjectsScanInProgress = false
            }
        }
    }

    func updateHeatmapRange(now: Date = Date()) {
        self.session.heatmapRange = HeatmapFilter.range(
            span: self.session.settings.heatmap.span,
            now: now,
            alignToWeek: true
        )
    }

    /// Folds one landed batch of counts into what the menu shows, in place, so rows fill in
    /// as results arrive instead of all at the end. A superseded refresh's batches are dropped.
    @MainActor
    private func merge(batch: [Repository], token: UUID, epoch: Int, now: Date) {
        guard self.refreshTaskToken == token, self.scopeEpoch == epoch else { return }
        let lookup = Dictionary(batch.map { ($0.fullName, $0) }, uniquingKeysWith: { first, _ in first })
        let merged = self.session.repositories.map { current in lookup[current.fullName].map { current.mergingBatch($0) } ?? current }
        self.session.repositories = merged
        self.session.menuSnapshot = MenuSnapshot(repositories: merged, capturedAt: now)
        let localIndex = self.session.localRepoIndex
        let models = merged.map { RepositoryDisplayModel(repo: $0, localStatus: localIndex.status(for: $0), now: now) }
        self.session.menuDisplayIndex = Dictionary(models.map { ($0.title, $0) }, uniquingKeysWith: { first, _ in first })
    }

    private func updateSession(with repos: [Repository], now: Date, epoch: Int) async {
        await MainActor.run {
            guard self.scopeEpoch == epoch else { return }
            self.session.repositories = repos
            self.session.menuSnapshot = MenuSnapshot(repositories: repos, capturedAt: now)
            self.session.hasLoadedRepositories = true
            self.session.lastRefreshDate = now
            self.session.rateLimitReset = nil
            self.session.lastError = nil
        }
    }

    private func updateMenuDisplayIndex(now: Date, epoch: Int) async {
        guard self.scopeEpoch == epoch else { return }
        let repos = self.session.repositories
        let localIndex = self.session.localRepoIndex
        let models = repos.map { repo in
            RepositoryDisplayModel(repo: repo, localStatus: localIndex.status(for: repo), now: now)
        }
        let index = Dictionary(uniqueKeysWithValues: models.map { ($0.title, $0) })
        await MainActor.run {
            guard self.scopeEpoch == epoch else { return }
            self.session.menuDisplayIndex = index
        }
    }
}
