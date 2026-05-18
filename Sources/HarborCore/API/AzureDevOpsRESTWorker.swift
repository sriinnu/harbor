import Foundation

// MARK: - Azure DevOps REST API Internal

/// Internal REST API implementation for Azure DevOps
internal actor AzureDevOpsRESTWorker {
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
        var queryItems = [URLQueryItem(name: "api-version", value: "7.0")]
        if let limit { queryItems.append(URLQueryItem(name: "$top", value: String(limit))) }
        components.queryItems = queryItems

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
