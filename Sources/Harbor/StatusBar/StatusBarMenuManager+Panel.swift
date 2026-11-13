import AppKit
import HarborCore

/// What the themed panel needs from the menu manager: the same data the menu is built
/// from, and the same actions its items run.
extension StatusBarMenuManager {
    /// What the system menu does in `menuWillOpen`: load the contribution heatmap (the
    /// panel never did, so "Your activity" stayed empty until the menu had been opened once)
    /// and refresh stale data.
    func panelWillOpen() {
        if self.appState.session.settings.appearance.showContributionHeader,
           case let .loggedIn(user) = self.appState.session.account {
            Task { await self.appState.loadContributionHeatmap(for: user.username) }
        }
        if self.appState.session.settings.appearance.showContributionHeader {
            Task { await self.appState.loadActivity(range: self.appState.session.settings.appearance.activityRange) }
        }
        self.appState.searchReviewRequests()
        self.appState.searchMyPulls()
        self.appState.refreshIfNeededForMenu()
    }

    func panelContent() -> HarborPanelContent {
        let session = self.appState.session
        guard case .loggedIn = session.account else { return HarborPanelContent() }
        return HarborPanelContent(
            login: self.menuBuilder.currentUsername() ?? session.gitlabUser?.username ?? session.azureUser?.displayName ?? "You",
            accounts: self.githubAccountChoices(),
            providers: self.menuBuilder.connectedProviders(session),
            lastRefresh: session.lastRefreshDate,
            isRefreshing: session.isRefreshing,
            rateLimitReset: session.rateLimitReset,
            error: session.lastError,
            repos: self.menuBuilder.orderedViewModels(now: Date()),
            judged: self.menuBuilder.allViewModels(now: Date()),
            pinned: Set(session.settings.repoList.pinnedRepositories),
            activity: self.panelActivity(session),
            hasLoadedRepositories: session.hasLoadedRepositories,
            repoActivity: session.repoActivity,
            activityRange: session.settings.appearance.activityRange,
            reviewRequests: self.appState.reviewRequests.requests,
            reviewRequestsTotal: self.appState.reviewRequests.total,
            reviewRequestsFailure: self.appState.reviewRequests.failure,
            reviewRequestsLoaded: self.appState.reviewRequests.hasAnswered,
            myPulls: self.appState.myPulls.pulls,
            myPullsFailure: self.appState.myPulls.failure,
            myPullsLoaded: self.appState.myPulls.hasAnswered,
            deferredRepos: session.deferredRepoNames
        )
    }

    private func githubAccountChoices() -> [AccountChoice] {
        let index = self.appState.session.settings.githubAccounts
        return index.accounts.map {
            AccountChoice(id: $0.id, login: $0.login, host: $0.host, isActive: $0.id == index.active)
        }
    }

    private func panelActivity(_ session: Session) -> PanelActivity {
        guard session.settings.appearance.showContributionHeader else { return PanelActivity() }
        return PanelActivity(
            range: session.settings.appearance.activityRange,
            githubDays: session.contributionHeatmap,
            githubError: session.contributionError,
            years: session.contributionYears,
            yearsState: session.contributionYearsState,
            others: session.providerActivity
        )
    }

    func panelActions(close: @escaping @MainActor () -> Void) -> HarborPanelActions {
        HarborPanelActions(
            refresh: { [weak self] in
                guard let self else { return }
                Task { await self.appState.refreshAllData() }
            },
            openRepo: { [weak self] repo in
                close()
                self?.openRepoFromMenu(fullName: repo.title)
            },
            openRepoPath: { [weak self] repo, path in
                guard let self, let url = self.webURLBuilder.repoPathURL(fullName: repo.title, path: path) else { return }
                close()
                self.open(url: url)
            },
            openTerminal: { [weak self] url in
                close()
                self?.openLocalTerminal(at: url)
            },
            togglePin: { [weak self] repo, pin in
                guard let self else { return }
                Task { pin ? await self.appState.addPinned(repo.title) : await self.appState.removePinned(repo.title) }
            },
            openActivity: { [weak self] in
                guard let self, let user = self.menuBuilder.currentUsername(),
                      let url = self.webURLBuilder.repoURL(fullName: user) else { return }
                close()
                self.open(url: url)
            },
            selectActivityRange: { [weak self] range in
                guard let self else { return }
                self.appState.session.settings.appearance.activityRange = range
                self.appState.persistSettings()
                Task { await self.appState.loadActivity(range: range) }
            },
            loadRepoActivity: { [weak self] repo in
                guard let self else { return }
                let source = repo.source
                Task {
                    await self.appState.loadRepoActivity(
                        fullName: repo.title, owner: source.owner, name: source.name, known: source.heatmap
                    )
                }
            },
            openSettings: { [weak self] in
                close()
                self?.openPreferences()
            },
            openAbout: { [weak self] in
                close()
                self?.openAbout()
            },
            openGitHub: { [weak self] in
                close()
                self?.open(url: HarborLinks.repository)
            },
            supportHarbor: { [weak self] in
                close()
                self?.open(url: HarborLinks.support)
            },
            signIn: { [weak self] in
                close()
                self?.signIn()
            },
            switchAccount: { [weak self] id in
                close()
                guard let appState = self?.appState else { return }
                Task { await appState.switchGitHubAccount(to: id) }
            },
            addProjectFolder: { [weak self] in
                close()
                guard let self else { return }
                if ProjectFolderPicker.addFolders(appState: self.appState) { self.dismissWelcome() }
            },
            dismissWelcome: { [weak self] in self?.dismissWelcome() },
            loadRateLimit: { [weak self] in
                guard let self else { return nil }
                let diagnostics = await self.appState.diagnostics()
                return diagnostics.restRateLimit ?? diagnostics.graphQLRateLimit
            },
            runLocalGit: { [weak self] command, url in
                guard let self else { return nil }
                return try await self.runLocalGit(command, at: url)
            },
            quit: { NSApp.terminate(nil) }
        )
    }

    /// Ends the first-run welcome for good. Idempotent; the flag is never cleared.
    func dismissWelcome() {
        guard !self.appState.session.settings.firstRunDismissed else { return }
        self.appState.session.settings.firstRunDismissed = true
        self.appState.persistSettings()
    }

    /// Runs one Git command on a clone inside its security-scoped root, then re-reads the
    /// clone's status and refreshes the session's local index so the lists catch up.
    func runLocalGit(_ command: LocalGitCommand, at url: URL) async throws -> LocalRepoStatus? {
        let bookmarks = self.appState.session.settings.localProjects.rootBookmarkList
        try await Task.detached(priority: .userInitiated) {
            var failure: Error?
            SecurityScopedBookmark.withAccess(to: url, rootBookmarks: bookmarks) {
                do { try LocalGitService().perform(command, at: url) } catch { failure = error }
            }
            if let failure { throw failure }
        }.value
        let snapshot = await LocalProjectsService().snapshot(repoRoots: [url], autoSyncEnabled: false)
        self.appState.refreshLocalProjects()
        return snapshot.statuses.first
    }
}
