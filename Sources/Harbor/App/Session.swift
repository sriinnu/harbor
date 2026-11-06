import Foundation
import Observation
import HarborCore

@Observable
final class Session {
    var account: AccountState = .loggedOut
    var repositories: [Repository] = []
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
