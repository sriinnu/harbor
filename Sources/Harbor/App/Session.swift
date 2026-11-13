import Foundation
import Observation
import HarborCore

@Observable
final class Session {
    var account: AccountState = .loggedOut
    /// A second GitHub account is signing in beside the one on screen: the code to show, and
    /// whether the sign-in is running. The account itself is untouched until it succeeds.
    var addAccountPrompt: DeviceAuthorization?
    var isAddingAccount = false
    var repositories: [Repository] = []
    /// Listed repositories this refresh did not count (past the recent cap or the GraphQL budget).
    /// Their counts load when their detail opens; the panel says how many there are.
    var deferredRepoNames: Set<String> = []
    /// Repos whose detail was opened lately (newest last, at most `Self.openedCap`). The next
    /// refreshes keep counting them, so a count loaded from a detail is not wiped by the next
    /// refresh. In memory, cleared with the account.
    var openedRepoNames: [String] = []
    static let openedCap = 20

    func noteOpened(_ fullName: String) {
        self.openedRepoNames.removeAll { $0 == fullName }
        self.openedRepoNames.append(fullName)
        if self.openedRepoNames.count > Self.openedCap { self.openedRepoNames.removeFirst(self.openedRepoNames.count - Self.openedCap) }
    }
    var menuSnapshot: MenuSnapshot?
    var menuDisplayIndex: [String: RepositoryDisplayModel] = [:]
    var hasLoadedRepositories = false
    var settings = UserSettings()
    var settingsSelectedTab: SettingsTab = .general
    var rateLimitReset: Date?
    var lastError: String?
    var contributionHeatmap: [HeatmapCell] = []
    var contributionUser: String?
    var contributionError: String?
    /// Per-year GitHub totals for the "All time" range. In memory only; filled the first
    /// time that range is chosen.
    var contributionYears: [ContributionYear] = []
    var contributionYearsState: ActivityLoadState = .idle
    /// GitLab and Azure DevOps activity for the panel's strip, in memory only.
    var providerActivity: [ProviderType: ProviderActivitySlice] = [:]
    /// Each repo's commit activity for its detail pane, keyed by full name. In memory only;
    /// filled the first time that repo's detail opens.
    var repoActivity: [String: RepoActivitySlice] = [:]
    var globalActivityEvents: [ActivityEvent] = []
    var globalActivityError: String?
    var globalCommitEvents: [RepoCommitSummary] = []
    var globalCommitError: String?
    var heatmapRange: HeatmapRange = HeatmapFilter.range(span: .twelveMonths, now: Date(), alignToWeek: true)
    var menuRepoSelection: MenuRepoSelection = .all
    var recentIssueScope: RecentIssueScope = .all
    var recentIssueLabelSelection: Set<String> = []
    var recentPullRequestScope: RecentPullRequestScope = .all
    var recentPullRequestEngagement: RecentPullRequestEngagement = .all
    var localRepoIndex: LocalRepoIndex = .empty
    var localDiscoveredRepoCount = 0
    var localProjectsScanInProgress = false
    var localProjectsAccessDenied = false

    // Multi-provider support
    var isAzureConnecting = false
    var isAzureConnected = false
    var azureUser: AzureDevOpsUser?
    var azureOrganization: String = ""

    var isGitLabConnecting = false
    var isGitLabConnected = false
    var gitlabUser: GitLabUser?
    var gitlabInstanceURL: String = "https://gitlab.com"

    // Refresh state
    var isRefreshing = false
    var lastRefreshDate: Date?

    // Computed property for GitHub connection
    var isGitHubConnected: Bool {
        if case .loggedIn = account { return true }
        return false
    }

    var githubUser: UserIdentity? {
        if case .loggedIn(let user) = account { return user }
        return nil
    }
}

enum AccountState: Equatable {
    case loggedOut
    /// Sign-in in progress. Carries the device code once GitHub has issued one,
    /// so the menu and Settings can show the user what to type.
    case loggingIn(DeviceAuthorization?)
    case loggedIn(UserIdentity)

    var isLoggingIn: Bool {
        if case .loggingIn = self { return true }
        return false
    }

    var deviceCodePrompt: DeviceAuthorization? {
        if case let .loggingIn(prompt) = self { return prompt }
        return nil
    }
}
