import Foundation
import Security

/// Azure DevOps client using REST API with PAT-based authentication.
/// Coordinates multiple services for repositories, pull requests, work items, pipelines, and more.
public actor AzureDevOpsClient {
    // MARK: - Configuration

    /// The API host URL (defaults to https://dev.azure.com)
    public private(set) var apiHost: URL = URL(string: "https://dev.azure.com")!

    /// The organization name (required for API calls)
    public private(set) var organization: String?

    /// The default project name (optional, can be overridden per call)
    public private(set) var defaultProject: String?

    private let tokenStore: AzureDevOpsPATStore
    private var tokenProvider: (@Sendable () async throws -> String)?
    private let diag = DiagnosticsLogger.shared
    private let requestRunner = AzureDevOpsRequestRunner()
    private var restAPI: AzureDevOpsRESTWorker?
    private var prefetchedRepos: [AzureRepository] = []
    private var prefetchedReposExpiry: Date?
    private var inflightRepoDetails: [String: Task<AzureRepository, Error>] = [:]

    public init(tokenStore: AzureDevOpsPATStore = .shared) {
        self.tokenStore = tokenStore
    }

    private func ensureRestAPI() {
        guard restAPI == nil else { return }
        // Capture current values for use in closures
        let currentApiHost = self.apiHost
        let currentOrg = self.organization ?? ""
        let currentProject = self.defaultProject
        self.restAPI = AzureDevOpsRESTWorker(
            apiHost: { currentApiHost },
            organization: { currentOrg },
            defaultProject: { currentProject },
            tokenProvider: { [weak self] in
                guard let self else { throw URLError(.userAuthenticationRequired) }
                return try await self.validAccessToken()
            },
            requestRunner: self.requestRunner,
            diag: self.diag
        )
    }

    // MARK: - Configuration Methods

    /// Sets the Azure DevOps API host URL.
    /// - Parameter host: The base URL for Azure DevOps (SaaS or on-premises)
    public func setAPIHost(_ host: URL) throws {
        guard host.scheme?.lowercased() == "https" else {
            throw AzureDevOpsAPIError.invalidHost
        }
        guard host.host != nil else {
            throw AzureDevOpsAPIError.invalidHost
        }
        self.apiHost = host
        Task {
            await self.diag.message("API host set to \(host.absoluteString)")
        }
    }

    /// Sets the organization name for API calls.
    /// - Parameter organization: The Azure DevOps organization name
    public func setOrganization(_ organization: String) throws {
        guard !organization.isEmpty else {
            throw AzureDevOpsAPIError.invalidOrganization
        }
        self.organization = organization
        Task {
            await self.diag.message("Organization set to \(organization)")
        }
    }

    /// Sets the default project name for API calls.
    /// - Parameter project: The Azure DevOps project name
    public func setDefaultProject(_ project: String) throws {
        guard !project.isEmpty else {
            throw AzureDevOpsAPIError.invalidProject
        }
        self.defaultProject = project
        Task {
            await self.diag.message("Default project set to \(project)")
        }
    }

    /// Sets the token provider for PAT-based authentication.
    /// - Parameter provider: An async closure that returns the PAT or throws an error
    public func setTokenProvider(_ provider: @Sendable @escaping () async throws -> String?) {
        self.tokenProvider = {
            if let pat = try await provider() {
                return pat
            }
            throw URLError(.userAuthenticationRequired)
        }
        Task {
            await self.diag.message("Token provider configured")
        }
    }

    /// Sets the PAT directly (for simple use cases).
    /// - Parameter pat: The Personal Access Token
    public func setPAT(_ pat: String) throws {
        guard !pat.isEmpty else {
            throw AzureDevOpsAPIError.invalidPAT
        }
        try self.tokenStore.save(token: pat, forOrganization: self.organization ?? "default")
        Task {
            await self.diag.message("PAT configured")
        }
    }

    // MARK: - Rate Limit & Diagnostics

    /// Returns the date when the rate limit will reset, if applicable.
    /// - Parameter now: The current date for comparison
    /// - Returns: The reset date or nil if not rate limited
    public func rateLimitReset(now: Date = Date()) async -> Date? {
        await self.requestRunner.rateLimitReset(now: now)
    }

    /// Returns a human-readable message about the current rate limit status.
    /// - Parameter now: The current date for comparison
    /// - Returns: A message describing the rate limit status
    public func rateLimitMessage(now: Date = Date()) async -> String? {
        await self.requestRunner.rateLimitMessage(now: now)
    }

    /// Returns a diagnostics summary for the client.
    /// - Returns: Current diagnostics state including rate limits, cache, and backoff status
    public func diagnostics() async -> AzureDevOpsDiagnosticsSummary {
        let runnerDiagnostics = await self.requestRunner.diagnosticsSnapshot()
        return AzureDevOpsDiagnosticsSummary(
            apiHost: self.apiHost,
            organization: self.organization,
            defaultProject: self.defaultProject,
            rateLimitReset: runnerDiagnostics.rateLimitReset,
            lastRateLimitError: runnerDiagnostics.lastRateLimitError,
            etagEntries: runnerDiagnostics.etagEntries,
            backoffEntries: runnerDiagnostics.backoffEntries,
            rateLimit: runnerDiagnostics.rateLimit
        )
    }

    // MARK: - Repository Methods

    /// Returns repositories for the authenticated user, sorted by activity.
    /// - Parameters:
    ///   - limit: Maximum number of repositories to return
    ///   - project: Optional project name to filter by
    /// - Returns: Array of repositories
    public func defaultRepositories(limit: Int, for project: String?) async throws -> [AzureRepository] {
        guard let org = self.organization else {
            throw AzureDevOpsAPIError.invalidOrganization
        }
        ensureRestAPI()
        let repos = try await self.restAPI!.repositories(organization: org, project: project, limit: max(limit, 10))
        return try await self.expandRepoItems(Array(repos.prefix(limit)))
    }

    /// Returns repositories sorted by recent activity (pushes, PRs, etc.).
    /// - Parameters:
    ///   - limit: Maximum number of repositories to return (nil for all)
    ///   - project: Optional project name to filter by
    /// - Returns: Array of repositories with activity information
    public func activityRepositories(limit: Int?, for project: String?) async throws -> [AzureRepository] {
        guard let org = self.organization else {
            throw AzureDevOpsAPIError.invalidOrganization
        }
        ensureRestAPI()
        let items = try await self.restAPI!.repositories(organization: org, project: project, limit: limit)
        let activityResults = await self.fetchActivityResults(for: items, organization: org)
        return items.compactMap { item in
            let key = "\(item.project?.name ?? "")/\(item.name)"
            let result = activityResults[key]
            return self.activityRepository(from: item, activityResult: result)
        }
    }

    /// Returns full details for a specific repository.
    /// - Parameters:
    ///   - project: The project name
    ///   - repository: The repository name
    /// - Returns: Full repository details including stats
    public func fullRepository(project: String, repository: String) async throws -> AzureRepository {
        let key = "\(project.lowercased())/\(repository.lowercased())"
        if let task = self.inflightRepoDetails[key] {
            return try await task.value
        }
        let task = Task { [weak self] () throws -> AzureRepository in
            guard let self else { throw CancellationError() }
            return try await self.fullRepositoryInternal(project: project, repository: repository)
        }
        self.inflightRepoDetails[key] = task
        defer { self.inflightRepoDetails[key] = nil }
        return try await task.value
    }

    /// Searches for repositories matching a query.
    /// - Parameters:
    ///   - query: The search query
    ///   - project: Optional project to search within
    /// - Returns: Array of matching repositories
    public func searchRepositories(matching query: String, in project: String?) async throws -> [AzureRepository] {
        guard let org = self.organization else {
            throw AzureDevOpsAPIError.invalidOrganization
        }
        ensureRestAPI()
        let items = try await self.restAPI!.searchRepositories(organization: org, project: project, query: query)
        return items.map { AzureRepository.from(apiRepo: $0, organization: org) }
    }

    /// Prefetch repositories for fast autocomplete.
    /// - Parameter max: Maximum number to prefetch
    /// - Returns: Prefetched repositories
    public func prefetchedRepositories(max: Int = RepoCacheConstants.maxRepositoriesToPrefetch) async throws -> [AzureRepository] {
        let now = Date()
        if let expires = self.prefetchedReposExpiry, expires > now, !self.prefetchedRepos.isEmpty {
            return Array(self.prefetchedRepos.prefix(max))
        }

        guard let org = self.organization else {
            throw AzureDevOpsAPIError.invalidOrganization
        }
        ensureRestAPI()
        let items = try await self.restAPI!.repositories(organization: org, project: self.defaultProject, limit: max)
        let repos = items.map { AzureRepository.from(apiRepo: $0, organization: org) }
        self.prefetchedRepos = repos
        self.prefetchedReposExpiry = now.addingTimeInterval(RepoCacheConstants.cacheTTL)
        return repos
    }

    // MARK: - Pull Request Methods

    /// Returns recent pull requests for a repository.
    /// - Parameters:
    ///   - project: The project name
    ///   - repository: The repository name
    ///   - limit: Maximum number of PRs to return
    /// - Returns: Array of pull request summaries
    public func recentPullRequests(
        project: String,
        repository: String,
        limit: Int = 20
    ) async throws -> [AzurePullRequestSummary] {
        ensureRestAPI()
        let summaries = try await self.restAPI!.pullRequests(
            organization: self.organization ?? "",
            project: project,
            repository: repository,
            limit: limit
        )
        return summaries
    }

    /// Returns full pull request details.
    /// - Parameters:
    ///   - project: The project name
    ///   - repository: The repository name
    ///   - pullRequestId: The PR ID
    /// - Returns: Full pull request details
    public func pullRequestDetails(
        project: String,
        repository: String,
        pullRequestId: Int
    ) async throws -> AzurePullRequest {
        ensureRestAPI()
        return try await self.restAPI!.pullRequestDetails(
            organization: self.organization ?? "",
            project: project,
            repository: repository,
            pullRequestId: pullRequestId
        )
    }

    // MARK: - Work Item Methods

    /// Returns recent work items (issues, bugs, tasks) for a project.
    /// - Parameters:
    ///   - project: The project name
    ///   - limit: Maximum number of work items to return
    /// - Returns: Array of work item summaries
    public func recentIssues(project: String, limit: Int = 20) async throws -> [RepoIssueSummary] {
        ensureRestAPI()
        return try await self.restAPI!.workItems(
            organization: self.organization ?? "",
            project: project,
            limit: limit
        )
    }

    // MARK: - Pipeline Methods

    /// Returns recent pipeline runs for a project or repository.
    /// - Parameters:
    ///   - project: The project name
    ///   - repository: Optional repository name to filter by
    ///   - limit: Maximum number of runs to return
    /// - Returns: Array of pipeline run summaries
    public func recentPipelineRuns(
        project: String,
        repository: String? = nil,
        limit: Int = 20
    ) async throws -> [RepoWorkflowRunSummary] {
        ensureRestAPI()
        return try await self.restAPI!.pipelineRuns(
            organization: self.organization ?? "",
            project: project,
            repository: repository,
            limit: limit
        )
    }

    // MARK: - Commit Methods

    /// Returns recent commits for a repository.
    /// - Parameters:
    ///   - project: The project name
    ///   - repository: The repository name
    ///   - limit: Maximum number of commits to return
    /// - Returns: Array of commit summaries
    public func recentCommits(
        project: String,
        repository: String,
        limit: Int = 20
    ) async throws -> [RepoCommitSummary] {
        ensureRestAPI()
        return try await self.restAPI!.commits(
            organization: self.organization ?? "",
            project: project,
            repository: repository,
            limit: limit
        )
    }

    /// Returns commit details.
    /// - Parameters:
    ///   - project: The project name
    ///   - repository: The repository name
    ///   - commitId: The commit SHA
    /// - Returns: Commit details
    public func commitDetails(
        project: String,
        repository: String,
        commitId: String
    ) async throws -> AzureCommit {
        ensureRestAPI()
        return try await self.restAPI!.commitDetails(
            organization: self.organization ?? "",
            project: project,
            repository: repository,
            commitId: commitId
        )
    }

    // MARK: - Branch Methods

    /// Returns recent branches for a repository.
    /// - Parameters:
    ///   - project: The project name
    ///   - repository: The repository name
    ///   - limit: Maximum number of branches to return
    /// - Returns: Array of branch summaries
    public func recentBranches(
        project: String,
        repository: String,
        limit: Int = 20
    ) async throws -> [RepoBranchSummary] {
        ensureRestAPI()
        return try await self.restAPI!.branches(
            organization: self.organization ?? "",
            project: project,
            repository: repository,
            limit: limit
        )
    }

    // MARK: - Project Methods

    /// Returns projects in the organization.
    /// - Parameter limit: Maximum number of projects to return
    /// - Returns: Array of project information
    public func projectList(limit: Int = 50) async throws -> [AzureDevOpsProject] {
        guard let org = self.organization else {
            throw AzureDevOpsAPIError.invalidOrganization
        }
        ensureRestAPI()
        return try await self.restAPI!.projects(organization: org, limit: limit)
    }

    // MARK: - User Methods

    /// Returns the current user's profile.
    /// - Returns: User profile information
    public func currentUser() async throws -> UserIdentity {
        guard let org = self.organization else {
            throw AzureDevOpsAPIError.invalidOrganization
        }
        ensureRestAPI()
        let profile = try await self.restAPI!.profile(organization: org)
        var components = URLComponents()
        components.scheme = self.apiHost.scheme ?? "https"
        let rawHost = self.apiHost.host ?? "dev.azure.com"
        components.host = rawHost == "dev.azure.com" ? "\(org).dev.azure.com" : rawHost
        let hostURL = components.url ?? URL(string: "https://dev.azure.com/\(org)")!
        let username = profile.displayName ?? profile.emailAddress ?? "Azure DevOps User"
        return UserIdentity(username: username, host: hostURL)
    }

    // MARK: - Simplified API Methods

    /// Fetches all repositories for the organization.
    /// - Returns: Array of Azure DevOps repositories
    public func fetchRepositories() async throws -> [AzureDevOpsRepository] {
        guard let org = self.organization else {
            throw AzureDevOpsAPIError.invalidOrganization
        }
        ensureRestAPI()
        let repos = try await self.restAPI!.fetchRepositoriesRaw(organization: org)
        return repos
    }

    /// Fetches work items for the project, optionally filtered by assignee.
    /// - Parameter assignedTo: Optional filter for work items assigned to a specific user
    /// - Returns: Array of Azure DevOps work items
    public func fetchWorkItems(assignedTo: String? = nil) async throws -> [AzureDevOpsWorkItem] {
        guard let org = self.organization else {
            throw AzureDevOpsAPIError.invalidOrganization
        }
        guard let project = self.defaultProject else {
            throw AzureDevOpsAPIError.invalidProject
        }
        ensureRestAPI()
        let workItems = try await self.restAPI!.fetchWorkItemsRaw(
            organization: org,
            project: project,
            assignedTo: assignedTo
        )
        return workItems
    }

    /// Fetches pull requests across all accessible repositories.
    /// - Returns: Array of Azure DevOps pull requests
    public func fetchPullRequests() async throws -> [AzureDevOpsPullRequest] {
        guard let org = self.organization else {
            throw AzureDevOpsAPIError.invalidOrganization
        }
        ensureRestAPI()
        let prs = try await self.restAPI!.fetchPullRequestsRaw(organization: org)
        return prs
    }

    /// Fetches pipelines for the organization or project.
    /// - Returns: Array of Azure DevOps pipelines
    public func fetchPipelines() async throws -> [AzureDevOpsPipeline] {
        guard let org = self.organization else {
            throw AzureDevOpsAPIError.invalidOrganization
        }
        ensureRestAPI()
        let pipelines = try await self.restAPI!.fetchPipelinesRaw(organization: org)
        return pipelines
    }

    /// Fetches the current user's profile.
    /// - Returns: The current Azure DevOps user
    public func fetchCurrentUser() async throws -> AzureDevOpsUser {
        guard let org = self.organization else {
            throw AzureDevOpsAPIError.invalidOrganization
        }
        return try await self.restAPI!.fetchCurrentUserRaw(organization: org)
    }

    // MARK: - Cache Management

    /// Clears all cached data.
    public func clearCache() async {
        await self.requestRunner.clear()
        self.prefetchedRepos = []
        self.prefetchedReposExpiry = nil
    }

    // MARK: - Internal Helpers

    private func expandRepoItems(_ items: [AzureDevOpsRepository]) async throws -> [AzureRepository] {
        guard self.organization != nil else {
            throw AzureDevOpsAPIError.invalidOrganization
        }
        return try await withThrowingTaskGroup(of: AzureRepository.self) { group in
            for repo in items {
                let projectName = repo.project?.name ?? self.defaultProject ?? ""
                group.addTask {
                    try await self.fullRepository(project: projectName, repository: repo.name)
                }
            }
            var out: [AzureRepository] = []
            for try await repo in group {
                out.append(repo)
            }
            return out
        }
    }

    private struct ActivityFetchResult {
        let pulls: Result<Int, Error>
        let commits: Result<[RepoCommitSummary], Error>
    }

    private func fetchActivityResults(
        for items: [AzureDevOpsRepository],
        organization: String
    ) async -> [String: ActivityFetchResult] {
        await withTaskGroup(of: (String, ActivityFetchResult).self) { group in
            for item in items {
                let projectName = item.project?.name ?? ""
                let repoName = item.name
                let key = "\(projectName)/\(repoName)"
                group.addTask { [self] in
                    async let pullsResult: Result<Int, Error> = self.capture {
                        try await self.restAPI!.pullRequestCount(
                            organization: organization,
                            project: projectName,
                            repository: repoName
                        )
                    }
                    async let commitsResult: Result<[RepoCommitSummary], Error> = self.capture {
                        try await self.restAPI!.commits(
                            organization: organization,
                            project: projectName,
                            repository: repoName,
                            limit: 10
                        )
                    }
                    let result = await ActivityFetchResult(
                        pulls: pullsResult,
                        commits: commitsResult
                    )
                    return (key, result)
                }
            }
            var out: [String: ActivityFetchResult] = [:]
            for await (key, result) in group {
                out[key] = result
            }
            return out
        }
    }

    private func fullRepositoryInternal(project: String, repository: String) async throws -> AzureRepository {
        guard let org = self.organization else {
            throw AzureDevOpsAPIError.invalidOrganization
        }
        ensureRestAPI()
        let repo = try await self.restAPI!.repositoryDetails(
            organization: org,
            project: project,
            repository: repository
        )
        return AzureRepository.from(apiRepo: repo, organization: org)
    }

    private func activityRepository(
        from item: AzureDevOpsRepository,
        activityResult: ActivityFetchResult?
    ) -> AzureRepository? {
        guard let org = self.organization else { return nil }
        var accumulator = AzureDevOpsErrorAccumulator()

        let pullCount = self.value(from: activityResult?.pulls, into: &accumulator) ?? 0
        let commits = self.value(from: activityResult?.commits, into: &accumulator) ?? []
        let latestActivity = commits.first

        return AzureRepository.from(
            apiRepo: item,
            organization: org,
            stats: nil,
            openPulls: pullCount,
            latestActivity: latestActivity,
            error: accumulator.message,
            rateLimitedUntil: accumulator.rateLimit
        )
    }

    private func validAccessToken() async throws -> String {
        if let provider = tokenProvider {
            return try await provider()
        }
        if let org = self.organization, let pat = try? tokenStore.token(forOrganization: org) { return pat }
        throw URLError(.userAuthenticationRequired)
    }

    private func capture<T>(_ work: @escaping () async throws -> T) async -> Result<T, Error> {
        do { return try await .success(work()) } catch { return .failure(error) }
    }

    private func value<T>(from result: Result<T, Error>?, into accumulator: inout AzureDevOpsErrorAccumulator) -> T? {
        guard let result else { return nil }
        switch result {
        case let .success(value): return value
        case let .failure(error):
            accumulator.absorb(error)
            return nil
        }
    }
}
