import Foundation
import Observation
import HarborCore

// MARK: - AppState container

@MainActor
@Observable
final class AppState {
    // Platform services
    let platform: PlatformServices

    var session = Session()
    let auth: OAuthCoordinator
    let github = GitHubClient()
    let refreshScheduler = RefreshScheduler()
    let settingsStore: SettingsStore
    let localRepoManager = LocalRepoManager()
    let menuRefreshInterval: TimeInterval = 30
    var refreshTask: Task<Void, Never>?
    var localProjectsTask: Task<Void, Never>?
    private var tokenRefreshTask: Task<Void, Never>?
    var menuRefreshTask: Task<Void, Never>?
    var refreshTaskToken = UUID()
    /// The one in-flight GitHub sign-in, so it can be cancelled or replaced.
    var loginTask: Task<String?, Never>?
    /// The one in-flight contribution heatmap load; callers that arrive meanwhile join it.
    var contributionTask: Task<Void, Never>?
    /// Repos whose detail is loading right now, so opening one twice asks GitHub once.
    var detailLoads: Set<String> = []
    private let tokenRefreshInterval: TimeInterval = 300
    /// Bumped whenever the signed-in account goes away or changes. A load that started under
    /// an older value drops its result instead of writing the previous account's data in.
    var scopeEpoch = 0
    /// Who the data on screen belongs to; a different login clears it all.
    var dataOwner: String?
    /// Run on every account change (sign-out, sign-in, a different login): owners of per-account
    /// state outside `Session`, such as the menu's recent lists, register a reset here.
    var accountScopeResets: [@MainActor () -> Void] = []
    /// The in-flight reset of the GitHub client's per-account limits. A request for the new
    /// account must not reach the client before it ran: `settleAccountReset()` awaits it.
    var accountResetTask: Task<Void, Never>?
    /// What the reset runs; tests replace it to watch the ordering.
    var accountReset: @Sendable () async -> Void = {}
    /// The review-request search the panel and the menu bar icon read.
    var reviewRequests = ReviewRequestsStore.shared
    /// The user's own open pull requests, searched once for Needs you and the Tower alike.
    var myPulls = MyPullsStore.shared
    /// What entered Needs you since the last notification, across both searches of one refresh.
    var needsYouPending: [NeedsYouWatcher.Item] = []
    /// Needs-you searches (review requests, own pull requests) started and not yet finished. The
    /// batch is posted when the last one finishes, so a refresh posts one notification, not two.
    var needsYouSearchesRunning = 0
    /// Posts a notification body; tests replace it. The setting is checked before it is called.
    var postNeedsYouNotification: @MainActor (String) -> Void = { body in
        Task { await LocalSyncNotifier.shared.notify(body: body) }
    }
    /// The network reads behind the lazily loaded activity, so tests can stand in for GitHub.
    var commitActivityLoader: (_ owner: String, _ name: String) async throws -> [HeatmapCell] = { _, _ in [] }
    var contributionHeatmapLoader: (_ login: String) async throws -> [HeatmapCell] = { _ in [] }
    var contributionYearsLoader: (_ login: String) async throws -> [ContributionYear] = { _ in [] }
    var providerActivityLoader: ((_ provider: ProviderType, _ since: Date, _ now: Date) async throws -> ProviderActivityResult)?

    // Default GitHub App values for convenience login from the main window.
    let defaultClientID = HarborAuthDefaults.clientID
    let defaultLoopbackPort = HarborAuthDefaults.loopbackPort
    let defaultGitHubHost = HarborAuthDefaults.githubHost
    let defaultAPIHost = HarborAuthDefaults.apiHost

    // Azure DevOps authentication
    let azureAuth = AzureDevOpsAuth.shared

    // GitLab authentication and client
    let gitlabAuth = GitLabAuth.shared
    var gitlabClient: GitLabClient?

    init(platform: PlatformServices = ApplePlatformServices(), settingsStore: SettingsStore = SettingsStore()) {
        self.platform = platform
        self.settingsStore = settingsStore
        self.auth = OAuthCoordinator(platform: platform)

        self.session.settings = self.settingsStore.load()
        self.reconcileAccountIndex()
        _ = self.auth.loadTokens()
        let github = self.github
        self.accountReset = { await github.resetAccountScope() }
        self.commitActivityLoader = { owner, name in try await github.repoCommitActivity(owner: owner, name: name) }
        self.contributionHeatmapLoader = { login in try await github.userContributionHeatmap(login: login) }
        self.contributionYearsLoader = { login in try await github.userContributionYears(login: login) }
        Task { [weak self] in
            await github.setTokenProvider { @Sendable [weak self] () async throws -> OAuthTokens? in
                try? await self?.auth.refreshIfNeeded()
            }
        }
        self.tokenRefreshTask = Task { [weak self] in
            guard let self else { return }
            while !Task.isCancelled {
                if self.auth.loadTokens() != nil {
                    _ = try? await self.auth.refreshIfNeeded()
                }
                try? await Task.sleep(for: .seconds(self.tokenRefreshInterval))
            }
        }
        self.refreshScheduler.configure(interval: self.session.settings.refreshInterval.seconds) { [weak self] in
            self?.requestRefresh()
        }
        Task { await DiagnosticsLogger.shared.setEnabled(self.session.settings.diagnosticsEnabled) }
        RepoHealthService.client = self.github
        RepoHealthService.onAlerts = { [weak self] fullName, alerts, epoch in
            self?.applyHealthAlerts(fullName: fullName, alerts: alerts, epoch: epoch)
        }
        RepoHealthService.epoch = { [weak self] in self?.scopeEpoch ?? 0 }
    }

    struct GlobalActivityResult {
        let events: [ActivityEvent]
        let commits: [RepoCommitSummary]
        let error: String?
        let commitError: String?
    }

    func diagnostics() async -> DiagnosticsSummary {
        await self.github.diagnostics()
    }

    func persistSettings() {
        self.settingsStore.save(self.session.settings)
    }

    func restartRefreshTimer() {
        self.refreshScheduler.configure(
            interval: self.session.settings.refreshInterval.seconds,
            fireImmediately: false
        ) { [weak self] in
            self?.requestRefresh()
        }
    }

    func refreshAllData() async {
        guard !self.session.isRefreshing else { return }
        self.session.isRefreshing = true
        defer { self.session.isRefreshing = false }

        self.requestRefresh(cancelInFlight: true)
    }
}
