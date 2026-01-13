import Foundation
import Security

/// Azure DevOps client using REST API with PAT-based authentication.
/// Coordinates multiple services for repositories, pull requests, work items, pipelines, and more.
public actor AzureDevOpsClient {
    // MARK: - Configuration

    /// The API host URL (defaults to https://dev.azure.com)
    public nonisolated(unsafe) var apiHost: URL = URL(string: "https://dev.azure.com")!

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
        guard let org = self.organization else {
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

        let projectName = item.project?.name ?? ""
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

// MARK: - Azure DevOps REST API Internal

/// Internal REST API implementation for Azure DevOps
private actor AzureDevOpsRESTWorker {
    private let apiHost: () -> URL
    private let organization: () -> String?
    private let defaultProject: () -> String?
    private let tokenProvider: () async throws -> String
    private let requestRunner: AzureDevOpsRequestRunner
    private let diag: DiagnosticsLogger

    init(
        apiHost: @escaping () -> URL,
        organization: @escaping () -> String?,
        defaultProject: @escaping () -> String?,
        tokenProvider: @escaping () async throws -> String,
        requestRunner: AzureDevOpsRequestRunner,
        diag: DiagnosticsLogger
    ) {
        self.apiHost = apiHost
        self.organization = organization
        self.defaultProject = defaultProject
        self.tokenProvider = tokenProvider
        self.requestRunner = requestRunner
        self.diag = diag
    }

    // MARK: - Repository API

    func repositories(organization: String, project: String?, limit: Int?) async throws -> [AzureDevOpsRepository] {
        let host = self.apiHost()
        var components = URLComponents(url: host.appendingPathComponent(organization), resolvingAgainstBaseURL: true)!
        if let proj = project {
            components.path += "/\(proj)"
        }
        components.path += "/_apis/git/repositories"
        components.queryItems = [
            URLQueryItem(name: "api-version", value: "7.0"),
            URLQueryItem(name: "$top", value: limit.map(String.init))
        ].compactMap { $0 }

        guard let url = components.url else { throw URLError(.badURL) }
        let pat = try await self.tokenProvider()
        let (data, _) = try await self.requestRunner.get(url: url, pat: pat)
        return try AzureDevOpsRecentDecoders.decodeRepositories(from: data)
    }

    func repositoryDetails(
        organization: String,
        project: String,
        repository: String
    ) async throws -> AzureDevOpsRepository {
        let host = self.apiHost()
        let url = host
            .appendingPathComponent(organization)
            .appendingPathComponent(project)
            .appendingPathComponent("_apis/git/repositories/\(repository)")

        var components = URLComponents(url: url, resolvingAgainstBaseURL: true)!
        components.queryItems = [URLQueryItem(name: "api-version", value: "7.0")]

        guard let finalURL = components.url else { throw URLError(.badURL) }
        let pat = try await self.tokenProvider()
        let (data, _) = try await self.requestRunner.get(url: finalURL, pat: pat)
        return try AzureDevOpsDecoding.decode(AzureDevOpsRepository.self, from: data)
    }

    func pullRequestCount(
        organization: String,
        project: String,
        repository: String
    ) async throws -> Int {
        let host = self.apiHost()
        let url = host
            .appendingPathComponent(organization)
            .appendingPathComponent(project)
            .appendingPathComponent("_apis/git/repositories/\(repository)/pullRequests")

        var components = URLComponents(url: url, resolvingAgainstBaseURL: true)!
        components.queryItems = [
            URLQueryItem(name: "api-version", value: "7.0"),
            URLQueryItem(name: "$top", value: "1"),
            URLQueryItem(name: "searchCriteria.status", value: "active")
        ]

        guard let finalURL = components.url else { throw URLError(.badURL) }
        let pat = try await self.tokenProvider()
        let (data, _) = try await self.requestRunner.get(url: finalURL, pat: pat)
        let response = try AzureDevOpsDecoding.decode(AzureDevOpsListResponse<AzureDevOpsPullRequest>.self, from: data)
        return response.count ?? response.value.count
    }

    func searchRepositories(
        organization: String,
        project: String?,
        query: String
    ) async throws -> [AzureDevOpsRepository] {
        let repos = try await self.repositories(organization: organization, project: project, limit: 100)
        let lowerQuery = query.lowercased()
        return repos.filter { repo in
            repo.name.lowercased().contains(lowerQuery) ||
            (repo.project?.name.lowercased().contains(lowerQuery) ?? false)
        }
    }

    // MARK: - Pull Request API

    func pullRequests(
        organization: String,
        project: String,
        repository: String,
        limit: Int
    ) async throws -> [AzurePullRequestSummary] {
        let host = self.apiHost()
        let url = host
            .appendingPathComponent(organization)
            .appendingPathComponent(project)
            .appendingPathComponent("_apis/git/repositories/\(repository)/pullRequests")

        var components = URLComponents(url: url, resolvingAgainstBaseURL: true)!
        components.queryItems = [
            URLQueryItem(name: "api-version", value: "7.0"),
            URLQueryItem(name: "$top", value: String(limit)),
            URLQueryItem(name: "searchCriteria.status", value: "all")
        ]

        guard let finalURL = components.url else { throw URLError(.badURL) }
        let pat = try await self.tokenProvider()
        let (data, _) = try await self.requestRunner.get(url: finalURL, pat: pat)
        let summaries = try AzureDevOpsRecentDecoders.decodeRecentPullRequests(from: data)
        return summaries.map { AzurePullRequestSummary(from: $0) }
    }

    func pullRequestDetails(
        organization: String,
        project: String,
        repository: String,
        pullRequestId: Int
    ) async throws -> AzurePullRequest {
        let host = self.apiHost()
        let url = host
            .appendingPathComponent(organization)
            .appendingPathComponent(project)
            .appendingPathComponent("_apis/git/repositories/\(repository)/pullRequests/\(pullRequestId)")

        var components = URLComponents(url: url, resolvingAgainstBaseURL: true)!
        components.queryItems = [URLQueryItem(name: "api-version", value: "7.0")]

        guard let finalURL = components.url else { throw URLError(.badURL) }
        let pat = try await self.tokenProvider()
        let (data, _) = try await self.requestRunner.get(url: finalURL, pat: pat)

        let apiPR = try AzureDevOpsDecoding.decode(AzureDevOpsPullRequest.self, from: data)
        return AzurePullRequest.from(api: apiPR, organization: organization, project: project, repository: repository)
    }

    // MARK: - Work Item API

    func workItems(organization: String, project: String, limit: Int) async throws -> [RepoIssueSummary] {
        let host = self.apiHost()
        let url = host
            .appendingPathComponent(organization)
            .appendingPathComponent(project)
            .appendingPathComponent("_apis/wit/wiql")

        var components = URLComponents(url: url, resolvingAgainstBaseURL: true)!
        let query = """
        SELECT [System.Id], [System.Title], [System.State], [System.ChangedDate], [System.CreatedBy]
        FROM WorkItems
        WHERE [System.WorkItemType] IN ('Bug', 'Issue', 'Task', 'User Story')
        ORDER BY [System.ChangedDate] DESC
        """
        components.queryItems = [
            URLQueryItem(name: "api-version", value: "7.0"),
            URLQueryItem(name: "$top", value: String(limit)),
            URLQueryItem(name: "query", value: query)
        ]

        guard let finalURL = components.url else { throw URLError(.badURL) }
        let pat = try await self.tokenProvider()

        let (wiData, _) = try await self.requestRunner.get(url: finalURL, pat: pat)
        let wiResponse = try AzureDevOpsDecoding.decode(AzureDevOpsWiqlResponse.self, from: wiData)
        guard !wiResponse.workItems.isEmpty else { return [] }

        let ids = wiResponse.workItems.prefix(200).map { $0.id }.joined(separator: ",")
        let detailURL = host
            .appendingPathComponent(organization)
            .appendingPathComponent(project)
            .appendingPathComponent("_apis/wit/workitems")
        var detailComponents = URLComponents(url: detailURL, resolvingAgainstBaseURL: true)!
        detailComponents.queryItems = [
            URLQueryItem(name: "api-version", value: "7.0"),
            URLQueryItem(name: "ids", value: ids),
            URLQueryItem(name: "$top", value: String(min(limit, 200)))
        ]

        guard let finalDetailURL = detailComponents.url else { throw URLError(.badURL) }
        let (data, _) = try await self.requestRunner.get(url: finalDetailURL, pat: pat)
        return try AzureDevOpsRecentDecoders.decodeRecentWorkItems(from: data)
    }

    // MARK: - Pipeline API

    func pipelineRuns(
        organization: String,
        project: String,
        repository: String?,
        limit: Int
    ) async throws -> [RepoWorkflowRunSummary] {
        let host = self.apiHost()
        let url = host
            .appendingPathComponent(organization)
            .appendingPathComponent(project)
            .appendingPathComponent("_apis/build/builds")

        var components = URLComponents(url: url, resolvingAgainstBaseURL: true)!
        var queryItems = [
            URLQueryItem(name: "api-version", value: "7.0"),
            URLQueryItem(name: "$top", value: String(limit))
        ]
        if let repo = repository {
            queryItems.append(URLQueryItem(name: "repositoryId", value: repo))
        }
        components.queryItems = queryItems

        guard let finalURL = components.url else { throw URLError(.badURL) }
        let pat = try await self.tokenProvider()
        let (data, _) = try await self.requestRunner.get(url: finalURL, pat: pat)
        return try AzureDevOpsRecentDecoders.decodeRecentPipelineRuns(from: data)
    }

    // MARK: - Commit API

    func commits(
        organization: String,
        project: String,
        repository: String,
        limit: Int
    ) async throws -> [RepoCommitSummary] {
        let host = self.apiHost()
        let url = host
            .appendingPathComponent(organization)
            .appendingPathComponent(project)
            .appendingPathComponent("_apis/git/repositories/\(repository)/commits")

        var components = URLComponents(url: url, resolvingAgainstBaseURL: true)!
        components.queryItems = [
            URLQueryItem(name: "api-version", value: "7.0"),
            URLQueryItem(name: "$top", value: String(limit)),
            URLQueryItem(name: "searchCriteria.itemVersion.version", value: "main")
        ]

        guard let finalURL = components.url else { throw URLError(.badURL) }
        let pat = try await self.tokenProvider()
        let (data, _) = try await self.requestRunner.get(url: finalURL, pat: pat)
        return try AzureDevOpsRecentDecoders.decodeRecentCommits(from: data)
    }

    func commitDetails(
        organization: String,
        project: String,
        repository: String,
        commitId: String
    ) async throws -> AzureCommit {
        let host = self.apiHost()
        let url = host
            .appendingPathComponent(organization)
            .appendingPathComponent(project)
            .appendingPathComponent("_apis/git/repositories/\(repository)/commits/\(commitId)")

        var components = URLComponents(url: url, resolvingAgainstBaseURL: true)!
        components.queryItems = [URLQueryItem(name: "api-version", value: "7.0")]

        guard let finalURL = components.url else { throw URLError(.badURL) }
        let pat = try await self.tokenProvider()
        let (data, _) = try await self.requestRunner.get(url: finalURL, pat: pat)
        return try AzureDevOpsDecoding.decode(AzureCommit.self, from: data)
    }

    // MARK: - Branch API

    func branches(
        organization: String,
        project: String,
        repository: String,
        limit: Int
    ) async throws -> [RepoBranchSummary] {
        let host = self.apiHost()
        let url = host
            .appendingPathComponent(organization)
            .appendingPathComponent(project)
            .appendingPathComponent("_apis/git/repositories/\(repository)/refs")

        var components = URLComponents(url: url, resolvingAgainstBaseURL: true)!
        components.queryItems = [
            URLQueryItem(name: "api-version", value: "7.0"),
            URLQueryItem(name: "$top", value: String(limit)),
            URLQueryItem(name: "filter", value: "heads")
        ]

        guard let finalURL = components.url else { throw URLError(.badURL) }
        let pat = try await self.tokenProvider()
        let (data, _) = try await self.requestRunner.get(url: finalURL, pat: pat)
        return try AzureDevOpsRecentDecoders.decodeRecentBranches(from: data)
    }

    // MARK: - Project API

    func projects(organization: String, limit: Int) async throws -> [AzureDevOpsProject] {
        let host = self.apiHost()
        let url = host.appendingPathComponent(organization).appendingPathComponent("_apis/projects")

        var components = URLComponents(url: url, resolvingAgainstBaseURL: true)!
        components.queryItems = [
            URLQueryItem(name: "api-version", value: "7.0"),
            URLQueryItem(name: "$top", value: String(limit))
        ]

        guard let finalURL = components.url else { throw URLError(.badURL) }
        let pat = try await self.tokenProvider()
        let (data, _) = try await self.requestRunner.get(url: finalURL, pat: pat)
        return try AzureDevOpsRecentDecoders.decodeProjects(from: data)
    }

    // MARK: - User API

    func profile(organization: String) async throws -> AzureDevOpsProfile {
        let host = self.apiHost()
        let url = host.appendingPathComponent(organization).appendingPathComponent("_apis/profile")

        var components = URLComponents(url: url, resolvingAgainstBaseURL: true)!
        components.queryItems = [URLQueryItem(name: "api-version", value: "7.0")]

        guard let finalURL = components.url else { throw URLError(.badURL) }
        let pat = try await self.tokenProvider()
        let (data, _) = try await self.requestRunner.get(url: finalURL, pat: pat)
        return try AzureDevOpsDecoding.decode(AzureDevOpsProfile.self, from: data)
    }

    // MARK: - Simplified Raw API Methods

    func fetchRepositoriesRaw(organization: String) async throws -> [AzureDevOpsRepository] {
        let host = self.apiHost()
        var components = URLComponents(url: host.appendingPathComponent(organization), resolvingAgainstBaseURL: true)!
        components.path += "/_apis/git/repositories"
        components.queryItems = [
            URLQueryItem(name: "api-version", value: "7.0")
        ]

        guard let url = components.url else { throw URLError(.badURL) }
        let pat = try await self.tokenProvider()
        let (data, _) = try await self.requestRunner.get(url: url, pat: pat)
        let response = try AzureDevOpsDecoding.decode(AzureDevOpsListResponse<AzureDevOpsRepository>.self, from: data)
        return response.value
    }

    func fetchWorkItemsRaw(organization: String, project: String, assignedTo: String?) async throws -> [AzureDevOpsWorkItem] {
        let host = self.apiHost()

        // First, execute WIQL query to get work item IDs
        let wiqlURL = host
            .appendingPathComponent(organization)
            .appendingPathComponent(project)
            .appendingPathComponent("_apis/wit/wiql")

        var wiqlComponents = URLComponents(url: wiqlURL, resolvingAgainstBaseURL: true)!

        // Build WIQL query
        var wiqlQuery = """
        SELECT [System.Id], [System.Title], [System.State], [System.ChangedDate], [System.CreatedBy], [System.AssignedTo]
        FROM WorkItems
        WHERE [System.WorkItemType] IN ('Bug', 'Issue', 'Task', 'User Story')
        """
        if let assignedTo = assignedTo {
            wiqlQuery += " AND [System.AssignedTo] = '\(assignedTo)'"
        }
        wiqlQuery += " ORDER BY [System.ChangedDate] DESC"

        wiqlComponents.queryItems = [
            URLQueryItem(name: "api-version", value: "7.0"),
            URLQueryItem(name: "query", value: wiqlQuery)
        ]

        guard let wiqlURLFinal = wiqlComponents.url else { throw URLError(.badURL) }
        let pat = try await self.tokenProvider()

        let (wiData, _) = try await self.requestRunner.get(url: wiqlURLFinal, pat: pat)
        let wiqlResponse = try AzureDevOpsDecoding.decode(AzureDevOpsWIQLResult.self, from: wiData)

        guard let workItems = wiqlResponse.workItems, !workItems.isEmpty else { return [] }

        // Get work item IDs (limited to 200 per API call)
        let ids = workItems.prefix(200).map { String($0.id) }.joined(separator: ",")

        // Fetch work item details
        let detailURL = host
            .appendingPathComponent(organization)
            .appendingPathComponent(project)
            .appendingPathComponent("_apis/wit/workitems")
        var detailComponents = URLComponents(url: detailURL, resolvingAgainstBaseURL: true)!
        detailComponents.queryItems = [
            URLQueryItem(name: "api-version", value: "7.0"),
            URLQueryItem(name: "ids", value: ids),
            URLQueryItem(name: "$top", value: "200"),
            URLQueryItem(name: "fields", value: "System.Title,System.State,System.AssignedTo,System.WorkItemType,System.ChangedDate,System.CreatedDate,System.CreatedBy,System.Description,Microsoft.VSTS.Common.Priority,System.Tags")
        ]

        guard let detailURLFinal = detailComponents.url else { throw URLError(.badURL) }
        let (data, _) = try await self.requestRunner.get(url: detailURLFinal, pat: pat)
        let response = try AzureDevOpsDecoding.decode(AzureDevOpsListResponse<AzureDevOpsWorkItem>.self, from: data)
        return response.value
    }

    func fetchPullRequestsRaw(organization: String) async throws -> [AzureDevOpsPullRequest] {
        let host = self.apiHost()
        let url = host.appendingPathComponent(organization).appendingPathComponent("_apis/git/pullrequests")

        var components = URLComponents(url: url, resolvingAgainstBaseURL: true)!
        components.queryItems = [
            URLQueryItem(name: "api-version", value: "7.0"),
            URLQueryItem(name: "$top", value: "100"),
            URLQueryItem(name: "searchCriteria.status", value: "all")
        ]

        guard let finalURL = components.url else { throw URLError(.badURL) }
        let pat = try await self.tokenProvider()
        let (data, _) = try await self.requestRunner.get(url: finalURL, pat: pat)
        let response = try AzureDevOpsDecoding.decode(AzureDevOpsListResponse<AzureDevOpsPullRequest>.self, from: data)
        return response.value
    }

    func fetchPipelinesRaw(organization: String) async throws -> [AzureDevOpsPipeline] {
        let host = self.apiHost()
        let url = host.appendingPathComponent(organization).appendingPathComponent("_apis/pipelines")

        var components = URLComponents(url: url, resolvingAgainstBaseURL: true)!
        components.queryItems = [
            URLQueryItem(name: "api-version", value: "7.0"),
            URLQueryItem(name: "$top", value: "100")
        ]

        guard let finalURL = components.url else { throw URLError(.badURL) }
        let pat = try await self.tokenProvider()
        let (data, _) = try await self.requestRunner.get(url: finalURL, pat: pat)
        let response = try AzureDevOpsDecoding.decode(AzureDevOpsListResponse<AzureDevOpsPipeline>.self, from: data)
        return response.value
    }

    func fetchCurrentUserRaw(organization: String) async throws -> AzureDevOpsUser {
        let host = self.apiHost()
        let profileURL = host.appendingPathComponent(organization).appendingPathComponent("_apis/profile/profiles/me")

        var profileComponents = URLComponents(url: profileURL, resolvingAgainstBaseURL: true)!
        profileComponents.queryItems = [URLQueryItem(name: "api-version", value: "6.0")]

        guard let url = profileComponents.url else { throw URLError(.badURL) }
        let pat = try await self.tokenProvider()

        var request = URLRequest(url: url)
        let credentials = ":\(pat)"
        if let encoded = credentials.data(using: .utf8)?.base64EncodedString() {
            request.addValue("Basic \(encoded)", forHTTPHeaderField: "Authorization")
        }
        request.addValue("application/json", forHTTPHeaderField: "Accept")

        let (profileData, _) = try await self.requestRunner.get(url: url, pat: pat)

        struct ProfileResponse: Decodable {
            let id: String
            let displayName: String?
            let emailAddress: String?
        }

        let profile = try JSONDecoder().decode(ProfileResponse.self, from: profileData)

        // Also fetch identities to get uniqueName
        let identitiesURL = host.appendingPathComponent(organization).appendingPathComponent("_apis/identities")
        var identitiesComponents = URLComponents(url: identitiesURL, resolvingAgainstBaseURL: true)!
        identitiesComponents.queryItems = [
            URLQueryItem(name: "api-version", value: "7.0"),
            URLQueryItem(name: "ids", value: profile.id)
        ]

        guard let identitiesUrlFinal = identitiesComponents.url else {
            return AzureDevOpsUser(
                id: profile.id,
                displayName: profile.displayName ?? "Azure User",
                uniqueName: "",
                emailAddress: profile.emailAddress
            )
        }

        var identitiesRequest = URLRequest(url: identitiesUrlFinal)
        if let encoded = credentials.data(using: .utf8)?.base64EncodedString() {
            identitiesRequest.addValue("Basic \(encoded)", forHTTPHeaderField: "Authorization")
        }
        identitiesRequest.addValue("application/json", forHTTPHeaderField: "Accept")

        struct IdentityResponse: Decodable {
            let value: [IdentityItem]
            struct IdentityItem: Decodable {
                let id: String
                let displayName: String?
                let uniqueName: String?
            }
        }

        let (identitiesData, _) = try await self.requestRunner.get(url: identitiesUrlFinal, pat: pat)
        let identitiesResponse = try JSONDecoder().decode(IdentityResponse.self, from: identitiesData)
        let identity = identitiesResponse.value.first

        return AzureDevOpsUser(
            id: profile.id,
            displayName: profile.displayName ?? "Azure User",
            uniqueName: identity?.uniqueName ?? "",
            emailAddress: profile.emailAddress
        )
    }
}

// MARK: - WIQL Response

struct AzureDevOpsWiqlResponse: Decodable {
    let queryType: String?
    let queryResultType: String?
    let asOf: Date?
    let workItems: [WorkItemRef]

    struct WorkItemRef: Decodable {
        let id: String
        let url: String?
    }

    enum CodingKeys: String, CodingKey {
        case queryType
        case queryResultType
        case asOf = "asOf"
        case workItems
    }
}

// MARK: - Diagnostics Summary

/// Diagnostics summary for Azure DevOps client
public struct AzureDevOpsDiagnosticsSummary: Sendable {
    public let apiHost: URL
    public let organization: String?
    public let defaultProject: String?
    public let rateLimitReset: Date?
    public let lastRateLimitError: String?
    public let etagEntries: Int
    public let backoffEntries: Int
    public let rateLimit: RateLimitSnapshot?

    public static let empty = AzureDevOpsDiagnosticsSummary(
        apiHost: URL(string: "https://dev.azure.com")!,
        organization: nil,
        defaultProject: nil,
        rateLimitReset: nil,
        lastRateLimitError: nil,
        etagEntries: 0,
        backoffEntries: 0,
        rateLimit: nil
    )
}

// MARK: - AzurePullRequest Conversion

extension AzurePullRequest {
    static func from(api: AzureDevOpsPullRequest, organization: String, project: String, repository: String) -> AzurePullRequest {
        let status = AzurePullRequestStatus(rawValue: api.status.lowercased()) ?? .notSet
        let mergeStatus = AzureMergeStatus(rawValue: api.mergeStatus?.lowercased() ?? "notset") ?? .notSet

        let createdBy = AzureIdentity(
            id: api.createdBy?.id,
            displayName: api.createdBy?.displayName ?? "Unknown",
            uniqueName: api.createdBy?.uniqueName,
            imageURL: api.createdBy?.imageUrl.flatMap { URL(string: $0) },
            descriptor: api.createdBy?.descriptor
        )

        let repoRef = AzureRepositoryRef(
            id: api.repository?.id ?? "",
            name: api.repository?.name ?? repository,
            url: nil
        )

        let reviewers = (api.reviewers ?? []).map { reviewer in
            AzureReviewer(
                id: reviewer.reviewerUrl ?? UUID().uuidString,
                displayName: reviewer.displayName ?? "Unknown",
                uniqueName: reviewer.uniqueName,
                imageURL: reviewer.imageUrl.flatMap { URL(string: $0) },
                vote: reviewer.vote ?? 0,
                isRequired: reviewer.isRequired ?? false,
                isFlagged: false
            )
        }

        let labels = (api.labels ?? []).map { label in
            AzureLabel(id: label.id ?? UUID().uuidString, name: label.name, active: true)
        }

        let webURL = URL(string: "https://dev.azure.com/\(organization)/\(project)/_git/\(repository)/pullrequest/\(api.pullRequestId)")!

        return AzurePullRequest(
            id: "\(api.pullRequestId)",
            pullRequestId: api.pullRequestId,
            title: api.title,
            description: api.description,
            status: status,
            mergeStatus: mergeStatus,
            createdBy: createdBy,
            creationDate: api.creationDate ?? Date(),
            closedDate: api.closedDate,
            sourceRefName: api.sourceRefName ?? "",
            targetRefName: api.targetRefName ?? "",
            repository: repoRef,
            url: webURL,
            isDraft: api.isDraft ?? false,
            reviewers: reviewers,
            labels: labels,
            workItemRefs: []
        )
    }
}

// MARK: - AzureRepository Conversion

extension AzureRepository {
    static func from(apiRepo: AzureDevOpsRepository, organization: String, stats: AzureRepositoryStats? = nil) -> AzureRepository {
        let webURL: URL
        if let webUrlString = apiRepo.webUrl, let url = URL(string: webUrlString) {
            webURL = url
        } else {
            let projectName = apiRepo.project?.name ?? ""
            webURL = URL(string: "https://dev.azure.com/\(organization)/\(projectName)/_git/\(apiRepo.name)")!
        }

        return AzureRepository(
            id: apiRepo.id,
            name: apiRepo.name,
            project: apiRepo.project?.name ?? "",
            organization: organization,
            defaultBranch: apiRepo.defaultBranch?.replacingOccurrences(of: "refs/heads/", with: ""),
            size: apiRepo.size,
            isDisabled: apiRepo.isDisabled ?? false,
            webURL: webURL,
            remoteURL: apiRepo.remoteUrl.flatMap { URL(string: $0) }
        )
    }

    static func from(
        apiRepo: AzureDevOpsRepository,
        organization: String,
        stats: AzureRepositoryStats?,
        openPulls: Int = 0,
        latestActivity: RepoCommitSummary? = nil,
        error: String? = nil,
        rateLimitedUntil: Date? = nil
    ) -> AzureRepository {
        var repo = self.from(apiRepo: apiRepo, organization: organization)
        return repo
    }
}
