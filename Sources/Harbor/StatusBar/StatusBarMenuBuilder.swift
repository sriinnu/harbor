import AppKit
import OSLog
import HarborCore
import SwiftUI

@MainActor
final class StatusBarMenuBuilder {
    private static let menuFixedWidth: CGFloat = 360

    let appState: AppState
    unowned let target: StatusBarMenuManager
    let signposter = OSSignposter(subsystem: "com.sriinnu.harbor", category: "menu")
    var repoSubmenuCache: [String: RepoSubmenuCacheEntry] = [:]
    var systemImageCache: [String: NSImage] = [:]
    let menuItemFactory = MenuItemViewFactory()

    init(appState: AppState, target: StatusBarMenuManager) {
        self.appState = appState
        self.target = target
    }

    func makeMainMenu() -> NSMenu {
        let menu = NSMenu()
        menu.autoenablesItems = false
        menu.delegate = self.target
        menu.appearance = nil
        return menu
    }

    func mainMenuPlan(now: Date = Date()) -> MainMenuPlan {
        let session = self.appState.session
        let settings = session.settings
        let repos = self.orderedViewModels(now: now)
        let signature = MenuBuildSignature(
            account: AccountSignature(session.account),
            settings: MenuSettingsSignature(settings: settings, selection: session.menuRepoSelection),
            hasLoadedRepositories: session.hasLoadedRepositories,
            lastRefresh: session.lastRefreshDate,
            rateLimitReset: session.rateLimitReset,
            lastError: session.lastError,
            contribution: ContributionSignature(
                user: session.contributionUser,
                error: session.contributionError,
                heatmapCount: session.contributionHeatmap.count
            ),
            globalActivity: ActivitySignature(
                events: session.globalActivityEvents,
                error: session.globalActivityError
            ),
            globalCommits: CommitSignature(
                commits: session.globalCommitEvents,
                error: session.globalCommitError
            ),
            heatmapRangeStart: session.heatmapRange.start.timeIntervalSinceReferenceDate,
            heatmapRangeEnd: session.heatmapRange.end.timeIntervalSinceReferenceDate,
            reposDigest: RepoSignature.digest(for: repos),
            timeBucket: Int(now.timeIntervalSinceReferenceDate / 60)
        )
        return MainMenuPlan(repos: repos, signature: signature)
    }

    func populateMainMenu(_ menu: NSMenu, repos: [RepositoryDisplayModel]) {
        let signpost = self.signposter.beginInterval("populateMainMenu")
        defer { self.signposter.endInterval("populateMainMenu", signpost) }
        menu.removeAllItems()
        let session = self.appState.session
        let settings = session.settings

        let hasContributionHeatmap = session.contributionHeatmap.isEmpty == false
        let shouldShowContributionHeader = settings.appearance.showContributionHeader
            && (hasContributionHeatmap || session.contributionError == nil)
        let username = self.currentUsername()
        let displayName = self.currentDisplayName()

        if case .loggedIn = session.account {
            let header = MenuAccountHeader(
                login: username ?? session.gitlabUser?.username ?? session.azureUser?.displayName ?? "You",
                providers: self.connectedProviders(session),
                lastRefresh: session.lastRefreshDate,
                isRefreshing: session.isRefreshing,
                onRefresh: { [weak self] in
                    guard let self else { return }
                    Task { await self.appState.refreshAllData() }
                }
            )
            menu.addItem(self.viewItem(for: header, enabled: true))
            menu.addItem(.separator())
        } else {
            let multiProviderStatus = MultiProviderStatusView(session: session, appState: self.appState)
                .padding(.horizontal, MenuStyle.headerHorizontalPadding)
                .padding(.top, MenuStyle.headerTopPadding)
                .padding(.bottom, MenuStyle.headerBottomPadding)
            menu.addItem(self.viewItem(for: multiProviderStatus, enabled: true, highlightable: true))
            menu.addItem(.separator())
        }

        if case .loggedIn = session.account, settings.appearance.showHarborView, !repos.isEmpty {
            menu.addItem(self.viewItem(for: HarborViewCard(boats: repos.map { HarborBoat(repo: $0) }), enabled: false))
            menu.addItem(.separator())
        }

        switch session.account {
        case .loggedOut:
            let loggedOut = MenuLoggedOutView()
                .padding(.horizontal, MenuStyle.sectionHorizontalPadding)
                .padding(.vertical, MenuStyle.sectionVerticalPadding)
            menu.addItem(self.viewItem(for: loggedOut, enabled: false))
            menu.addItem(.separator())

            // A failed sign-in lands here; show why instead of dropping it.
            if let error = session.lastError {
                let banner = ErrorBanner(message: error)
                    .padding(.horizontal, MenuStyle.bannerHorizontalPadding)
                    .padding(.vertical, MenuStyle.bannerVerticalPadding)
                menu.addItem(self.viewItem(for: banner, enabled: false))
                menu.addItem(.separator())
            }

            // Provider selection menu
            let providerMenu = NSMenu()

            let githubItem = NSMenuItem(title: "GitHub", action: #selector(self.target.signInToGitHub), keyEquivalent: "")
            githubItem.image = NSImage(systemSymbolName: "chevron.left.forwardslash.chevron.right", accessibilityDescription: "GitHub")
            githubItem.target = self.target
            providerMenu.addItem(githubItem)

            let azureItem = NSMenuItem(title: "Azure DevOps", action: #selector(self.target.signInToAzure), keyEquivalent: "")
            azureItem.image = NSImage(systemSymbolName: "terminal", accessibilityDescription: "Azure DevOps")
            azureItem.target = self.target
            providerMenu.addItem(azureItem)

            let gitlabItem = NSMenuItem(title: "GitLab", action: #selector(self.target.signInToGitLab), keyEquivalent: "")
            gitlabItem.image = NSImage(systemSymbolName: "chevron.left.forwardslash.chevron.right", accessibilityDescription: "GitLab")
            gitlabItem.target = self.target
            providerMenu.addItem(gitlabItem)

            let signInItem = NSMenuItem(title: "Sign In", action: nil, keyEquivalent: "")
            signInItem.submenu = providerMenu
            menu.addItem(signInItem)
            menu.addItem(.separator())
            menu.addItem(self.actionItem(title: "Preferences…", action: #selector(self.target.openPreferences), keyEquivalent: ","))
            menu.addItem(self.actionItem(title: "About Harbor", action: #selector(self.target.openAbout)))
            self.addBuildLabel(to: menu)
            menu.addItem(self.actionItem(title: "Quit Harbor", action: #selector(self.target.quitApp), keyEquivalent: "q"))
            return
        case let .loggingIn(prompt):
            let loggedOut = MenuLoggedOutView()
                .padding(.horizontal, MenuStyle.sectionHorizontalPadding)
                .padding(.vertical, MenuStyle.sectionVerticalPadding)
            menu.addItem(self.viewItem(for: loggedOut, enabled: false))
            menu.addItem(.separator())
            if let prompt {
                let codeItem = NSMenuItem(title: "Enter code \(prompt.userCode) on GitHub", action: nil, keyEquivalent: "")
                codeItem.isEnabled = false
                menu.addItem(codeItem)
                menu.addItem(self.actionItem(title: "Copy Code", action: #selector(self.target.copyDeviceCode)))
                menu.addItem(self.actionItem(title: "Open GitHub", action: #selector(self.target.openDeviceVerification)))
            } else {
                let signInItem = NSMenuItem(title: "Signing in…", action: nil, keyEquivalent: "")
                signInItem.isEnabled = false
                menu.addItem(signInItem)
            }
            menu.addItem(self.actionItem(title: "Cancel Sign-In", action: #selector(self.target.cancelSignIn)))
            menu.addItem(.separator())
            menu.addItem(self.actionItem(title: "Preferences…", action: #selector(self.target.openPreferences), keyEquivalent: ","))
            menu.addItem(self.actionItem(title: "About Harbor", action: #selector(self.target.openAbout)))
            self.addBuildLabel(to: menu)
            menu.addItem(self.actionItem(title: "Quit Harbor", action: #selector(self.target.quitApp), keyEquivalent: "q"))
            return
        case .loggedIn:
            break
        }

        if let reset = session.rateLimitReset {
            let banner = RateLimitBanner(reset: reset)
                .padding(.horizontal, MenuStyle.bannerHorizontalPadding)
                .padding(.vertical, MenuStyle.bannerVerticalPadding)
            menu.addItem(self.viewItem(for: banner, enabled: false))
            menu.addItem(.separator())
        } else if let error = session.lastError {
            let banner = ErrorBanner(message: error)
                .padding(.horizontal, MenuStyle.bannerHorizontalPadding)
                .padding(.vertical, MenuStyle.bannerVerticalPadding)
            menu.addItem(self.viewItem(for: banner, enabled: false))
            menu.addItem(.separator())
        }

        let waiting = repos.filter { $0.ciStatus == .failing || ($0.source.security?.openAlertCount ?? 0) > 0 }
        if !waiting.isEmpty {
            menu.addItem(self.viewItem(for: MenuSectionHeader(title: "Needs you · \(waiting.count)"), enabled: false))
            for repo in waiting.prefix(5) {
                menu.addItem(self.needsYouItem(for: repo, isPinned: settings.repoList.pinnedRepositories.contains(repo.title)))
            }
            menu.addItem(.separator())
        }

        let showFilters = session.hasLoadedRepositories
        if showFilters {
            let filters = MenuRepoFiltersView(session: session)
                .padding(.horizontal, 0)
                .padding(.vertical, 0)
            menu.addItem(self.viewItem(for: filters, enabled: true))
            menu.addItem(.separator())
        }

        if repos.isEmpty {
            let (title, subtitle) = self.emptyStateMessage(for: session)
            let emptyState = MenuEmptyStateView(title: title, subtitle: subtitle)
                .padding(.horizontal, MenuStyle.sectionHorizontalPadding)
                .padding(.vertical, MenuStyle.sectionVerticalPadding)
            menu.addItem(self.viewItem(for: emptyState, enabled: false))
        } else {
            var usedRepoKeys: Set<String> = []
            for repo in repos {
                let isPinned = settings.repoList.pinnedRepositories.contains(repo.title)
                let item = self.repoMenuItem(for: repo, isPinned: isPinned)
                item.representedObject = repo.title
                menu.addItem(item)
                usedRepoKeys.insert(repo.title)
            }
            self.repoSubmenuCache = self.repoSubmenuCache.filter { usedRepoKeys.contains($0.key) }
        }

        if shouldShowContributionHeader, let username, let displayName {
            menu.addItem(.separator())
            let strip = ActivityStripRow(cells: session.contributionHeatmap)
            let submenu = self.contributionSubmenu(username: username, displayName: displayName)
            menu.addItem(self.viewItem(for: strip, enabled: true, highlightable: true, submenu: submenu))
        }

        menu.addItem(self.paddedSeparator())
        menu.addItem(self.actionItem(title: "Preferences…", action: #selector(self.target.openPreferences), keyEquivalent: ","))
        menu.addItem(self.actionItem(title: "About Harbor", action: #selector(self.target.openAbout)))
        if SparkleController.shared.updateStatus.isUpdateReady {
            menu.addItem(self.actionItem(title: "Restart to update", action: #selector(self.target.checkForUpdates)))
        }
        self.addBuildLabel(to: menu)
        menu.addItem(self.actionItem(title: "Quit Harbor", action: #selector(self.target.quitApp), keyEquivalent: "q"))
    }

    /// Dev builds (Scripts/dev-launch.sh) show their build label, so it's obvious which build is running.
    private func addBuildLabel(to menu: NSMenu) {
        guard let label = Bundle.main.object(forInfoDictionaryKey: "HarborBuildLabel") as? String else { return }
        let item = NSMenuItem(title: "Dev build \(label)", action: nil, keyEquivalent: "")
        item.isEnabled = false
        menu.addItem(item)
    }

    func refreshMenuViewHeights(in menu: NSMenu) {
        let signpost = self.signposter.beginInterval("refreshMenuViewHeights")
        defer { self.signposter.endInterval("refreshMenuViewHeights", signpost) }
        self.refreshMenuViewHeights(in: menu, width: self.menuWidth(for: menu))
    }

    func refreshMenuViewHeights(in menu: NSMenu, width: CGFloat) {
        let signpost = self.signposter.beginInterval("refreshMenuViewHeightsWidth")
        defer { self.signposter.endInterval("refreshMenuViewHeightsWidth", signpost) }
        for item in menu.items {
            guard let view = item.view,
                  let measuring = view as? MenuItemMeasuring else { continue }
            let height = measuring.measuredHeight(width: width)
            if abs(view.frame.size.height - height) > 0.5 || view.frame.size.width != width {
                view.frame = NSRect(origin: .zero, size: NSSize(width: width, height: height))
            }
        }
    }

    func clearHighlights(in menu: NSMenu) {
        for item in menu.items {
            (item.view as? MenuItemHighlighting)?.setHighlighted(false)
        }
    }

    func menuWidth(for menu: NSMenu) -> CGFloat {
        let signpost = self.signposter.beginInterval("menuWidth")
        defer { self.signposter.endInterval("menuWidth", signpost) }
        if let view = menu.items.compactMap(\.view).first {
            if let contentWidth = view.window?.contentView?.bounds.width, contentWidth > 0 {
                return max(contentWidth, Self.menuFixedWidth)
            }
            if let windowWidth = view.window?.frame.width, windowWidth > 0 {
                return max(windowWidth, Self.menuFixedWidth)
            }
        }
        let menuWidth = menu.size.width
        if menuWidth > 0 { return max(menuWidth, Self.menuFixedWidth) }
        return Self.menuFixedWidth
    }

    func orderedViewModels(now: Date) -> [RepositoryDisplayModel] {
        let session = self.appState.session
        let selection = session.menuRepoSelection
        let settings = session.settings
        let scope: RepositoryScope = selection.isPinnedScope ? .pinned : .all
        let query = RepositoryQuery(
            scope: scope,
            onlyWith: selection.onlyWith,
            includeForks: settings.repoList.showForks,
            includeArchived: settings.repoList.showArchived,
            sortKey: settings.repoList.menuSortKey,
            limit: settings.repoList.displayLimit,
            pinned: settings.repoList.pinnedRepositories,
            hidden: Set(settings.repoList.hiddenRepositories),
            pinPriority: true
        )
        let baseRepos = session.repositories.isEmpty
            ? (session.menuSnapshot?.repositories ?? [])
            : session.repositories
        return self.displayModels(RepositoryPipeline.apply(baseRepos, query: query), now: now)
    }

    /// Every repo of the account, with no scope, limit or hide: what Needs you and the menu bar
    /// icon are judged on. The display limit only decides which rows are drawn.
    func allViewModels(now: Date) -> [RepositoryDisplayModel] {
        let session = self.appState.session
        let settings = session.settings
        let query = RepositoryQuery(
            scope: .all,
            includeForks: true,
            includeArchived: true,
            sortKey: settings.repoList.menuSortKey,
            pinned: settings.repoList.pinnedRepositories,
            pinPriority: true
        )
        let baseRepos = session.repositories.isEmpty
            ? (session.menuSnapshot?.repositories ?? [])
            : session.repositories
        return self.displayModels(RepositoryPipeline.apply(baseRepos, query: query), now: now)
    }

    private func displayModels(_ repos: [Repository], now: Date) -> [RepositoryDisplayModel] {
        let session = self.appState.session
        let displayIndex = session.menuDisplayIndex
        return repos.map { repo in
            displayIndex[repo.fullName]
                ?? RepositoryDisplayModel(
                    repo: repo,
                    localStatus: session.localRepoIndex.status(for: repo),
                    now: now
                )
        }
    }

    private func emptyStateMessage(for session: Session) -> (String, String) {
        let hasPinned = !session.settings.repoList.pinnedRepositories.isEmpty
        let isPinnedScope = session.menuRepoSelection.isPinnedScope
        let hasFilter = session.menuRepoSelection.onlyWith.isActive
        if isPinnedScope, !hasPinned {
            return ("No pinned repositories", "Pin a repository to see activity here.")
        }
        if isPinnedScope || hasFilter {
            return ("No repositories match this filter", "Try All or a different filter.")
        }
        return ("No repositories yet", "Pin a repository to see activity here.")
    }

    func currentUsername() -> String? {
        if case let .loggedIn(user) = self.appState.session.account { return user.username }
        return nil
    }

    private func currentDisplayName() -> String? {
        guard case let .loggedIn(user) = self.appState.session.account else { return nil }
        let host = user.host.host ?? "github.com"
        return "\(user.username)@\(host)"
    }

    var isLightAppearance: Bool {
        NSApp.effectiveAppearance.bestMatch(from: [.aqua, .darkAqua]) == .aqua
    }
}
