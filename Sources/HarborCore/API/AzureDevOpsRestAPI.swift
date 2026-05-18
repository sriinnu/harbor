import Foundation

// MARK: - Azure DevOps REST API Client

struct AzureDevOpsRestAPI: Sendable {
    let apiHost: @Sendable () async -> URL
    let patProvider: @Sendable () async throws -> String
    let requestRunner: AzureDevOpsRequestRunner
    let diag: DiagnosticsLogger

    // MARK: - User & Organization

    /// Gets current user and organization connection data
    /// GET /{org}/_apis/connectionData
    func fetchConnectionData() async throws -> AzureDevOpsConnectionData {
        let pat = try await patProvider()
        let baseURL = await apiHost()
        let url = baseURL.appending(path: "/_apis/connectionData")
        let (data, _) = try await authorizedGet(url: url, pat: pat)
        return try AzureDevOpsDecoding.decode(AzureDevOpsConnectionData.self, from: data)
    }

    /// Lists all projects in the organization
    /// GET /{org}/_apis/projects
    func fetchProjects(top: Int? = nil, skip: Int? = nil) async throws -> [AzureDevOpsProject] {
        let pat = try await patProvider()
        let baseURL = await apiHost()
        guard var components = URLComponents(url: baseURL.appending(path: "/_apis/projects"), resolvingAgainstBaseURL: false) else {
            throw URLError(.badURL)
        }
        components.queryItems = buildPaginationParams(top: top, skip: skip)
        guard let url = components.url else { throw URLError(.badURL) }
        let (data, _) = try await authorizedGet(url: url, pat: pat)
        let response = try AzureDevOpsDecoding.decode(AzureDevOpsListResponse<AzureDevOpsProject>.self, from: data)
        return response.value
    }

    /// Lists all projects with pagination support
    func fetchAllProjects(limit: Int? = nil) async throws -> [AzureDevOpsProject] {
        try await fetchAllPages(
            path: "/_apis/projects",
            queryItems: [],
            limit: limit,
            decode: { try AzureDevOpsDecoding.decode(AzureDevOpsListResponse<AzureDevOpsProject>.self, from: $0).value }
        )
    }

    // MARK: - Repositories

    /// Lists all repositories in a project
    /// GET /{org}/{project}/_apis/git/repositories
    func fetchRepositories(project: String, top: Int? = nil, skip: Int? = nil) async throws -> [AzureDevOpsRepository] {
        let pat = try await patProvider()
        let baseURL = await apiHost()
        guard var components = URLComponents(
            url: baseURL.appending(path: "/\(project)/_apis/git/repositories"),
            resolvingAgainstBaseURL: false
        ) else {
            throw URLError(.badURL)
        }
        components.queryItems = buildPaginationParams(top: top, skip: skip)
        guard let url = components.url else { throw URLError(.badURL) }
        let (data, _) = try await authorizedGet(url: url, pat: pat)
        let response = try AzureDevOpsDecoding.decode(AzureDevOpsListResponse<AzureDevOpsRepository>.self, from: data)
        return response.value
    }

    /// Gets details of a specific repository
    /// GET /{org}/{project}/_apis/git/repositories/{repoId}
    func fetchRepository(project: String, repoId: String) async throws -> AzureDevOpsRepository {
        let pat = try await patProvider()
        let baseURL = await apiHost()
        let url = baseURL.appending(path: "/\(project)/_apis/git/repositories/\(repoId)")
        let (data, _) = try await authorizedGet(url: url, pat: pat)
        return try AzureDevOpsDecoding.decode(AzureDevOpsRepository.self, from: data)
    }

    /// Lists all repositories with pagination
    func fetchAllRepositories(project: String, limit: Int? = nil) async throws -> [AzureDevOpsRepository] {
        try await fetchAllPages(
            path: "/\(project)/_apis/git/repositories",
            queryItems: [],
            limit: limit,
            decode: { try AzureDevOpsDecoding.decode(AzureDevOpsListResponse<AzureDevOpsRepository>.self, from: $0).value }
        )
    }

    // MARK: - Pull Requests

    /// Lists pull requests for a repository
    /// GET /{org}/{project}/_apis/git/repositories/{repoId}/pullrequests
    func fetchPullRequests(
        project: String,
        repoId: String,
        status: AzureDevOpsPullRequestStatus = .active,
        top: Int? = nil,
        skip: Int? = nil
    ) async throws -> [AzureDevOpsPullRequest] {
        let pat = try await patProvider()
        let baseURL = await apiHost()
        guard var components = URLComponents(
            url: baseURL.appending(path: "/\(project)/_apis/git/repositories/\(repoId)/pullrequests"),
            resolvingAgainstBaseURL: false
        ) else {
            throw URLError(.badURL)
        }
        var items = buildPaginationParams(top: top, skip: skip)
        items.append(URLQueryItem(name: "searchParameters.status", value: status.queryValue))
        components.queryItems = items
        guard let url = components.url else { throw URLError(.badURL) }
        let (data, _) = try await authorizedGet(url: url, pat: pat)
        let response = try AzureDevOpsDecoding.decode(AzureDevOpsListResponse<AzureDevOpsPullRequest>.self, from: data)
        return response.value
    }

    /// Gets a specific pull request by ID
    /// GET /{org}/{project}/_apis/git/repositories/{repoId}/pullrequests/{prId}
    func fetchPullRequest(project: String, repoId: String, prId: Int) async throws -> AzureDevOpsPullRequest {
        let pat = try await patProvider()
        let baseURL = await apiHost()
        let url = baseURL.appending(path: "/\(project)/_apis/git/repositories/\(repoId)/pullrequests/\(prId)")
        let (data, _) = try await authorizedGet(url: url, pat: pat)
        return try AzureDevOpsDecoding.decode(AzureDevOpsPullRequest.self, from: data)
    }

    /// Lists all pull requests with pagination
    func fetchAllPullRequests(
        project: String,
        repoId: String,
        status: AzureDevOpsPullRequestStatus = .active,
        limit: Int? = nil
    ) async throws -> [AzureDevOpsPullRequest] {
        try await fetchAllPages(
            path: "/\(project)/_apis/git/repositories/\(repoId)/pullrequests",
            queryItems: [URLQueryItem(name: "searchParameters.status", value: status.queryValue)],
            limit: limit,
            decode: { try AzureDevOpsDecoding.decode(AzureDevOpsListResponse<AzureDevOpsPullRequest>.self, from: $0).value }
        )
    }

    // MARK: - Work Items (WIQL)

    /// Executes a WIQL query
    /// POST /{org}/{project}/_apis/wit/wiql
    func executeWIQLQuery(project: String, query: String) async throws -> AzureDevOpsWIQLResult {
        let pat = try await patProvider()
        let baseURL = await apiHost()
        let url = baseURL.appending(path: "/\(project)/_apis/wit/wiql")
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")

        let body = AzureDevOpsWIQLQuery(query: query)
        request.httpBody = try JSONEncoder().encode(body)

        let (data, _) = try await authorizedPost(url: url, request: request, pat: pat)
        return try AzureDevOpsDecoding.decode(AzureDevOpsWIQLResult.self, from: data)
    }

    /// Gets a specific work item by ID
    /// GET /{org}/{project}/_apis/wit/workitems/{id}
    func fetchWorkItem(project: String, id: Int) async throws -> AzureDevOpsWorkItem {
        let pat = try await patProvider()
        let baseURL = await apiHost()
        let url = baseURL.appending(path: "/\(project)/_apis/wit/workitems/\(id)")
        let (data, _) = try await authorizedGet(url: url, pat: pat)
        return try AzureDevOpsDecoding.decode(AzureDevOpsWorkItem.self, from: data)
    }

    /// Gets multiple work items by IDs
    /// GET /{org}/{project}/_apis/wit/workitems?ids=1,2,3
    func fetchWorkItems(project: String, ids: [Int], fields: [String]? = nil) async throws -> [AzureDevOpsWorkItem] {
        let pat = try await patProvider()
        let baseURL = await apiHost()
        guard var components = URLComponents(
            url: baseURL.appending(path: "/\(project)/_apis/wit/workitems"),
            resolvingAgainstBaseURL: false
        ) else {
            throw URLError(.badURL)
        }
        components.queryItems = [
            URLQueryItem(name: "ids", value: ids.map(String.init).joined(separator: ",")),
            URLQueryItem(name: "api-version", value: "7.0")
        ]
        if let fields = fields {
            components.queryItems?.append(URLQueryItem(name: "fields", value: fields.joined(separator: ",")))
        }
        guard let url = components.url else { throw URLError(.badURL) }
        let (data, _) = try await authorizedGet(url: url, pat: pat)
        let response = try AzureDevOpsDecoding.decode(AzureDevOpsListResponse<AzureDevOpsWorkItem>.self, from: data)
        return response.value
    }

    // MARK: - Pipelines

    /// Lists all pipelines in a project
    /// GET /{org}/{project}/_apis/pipelines
    func fetchPipelines(project: String, top: Int? = nil, skip: Int? = nil) async throws -> [AzureDevOpsPipeline] {
        let pat = try await patProvider()
        let baseURL = await apiHost()
        guard var components = URLComponents(
            url: baseURL.appending(path: "/\(project)/_apis/pipelines"),
            resolvingAgainstBaseURL: false
        ) else {
            throw URLError(.badURL)
        }
        components.queryItems = buildPaginationParams(top: top, skip: skip)
        guard let url = components.url else { throw URLError(.badURL) }
        let (data, _) = try await authorizedGet(url: url, pat: pat)
        let response = try AzureDevOpsDecoding.decode(AzureDevOpsListResponse<AzureDevOpsPipeline>.self, from: data)
        return response.value
    }

    /// Lists all pipelines with pagination
    func fetchAllPipelines(project: String, limit: Int? = nil) async throws -> [AzureDevOpsPipeline] {
        try await fetchAllPages(
            path: "/\(project)/_apis/pipelines",
            queryItems: [],
            limit: limit,
            decode: { try AzureDevOpsDecoding.decode(AzureDevOpsListResponse<AzureDevOpsPipeline>.self, from: $0).value }
        )
    }

    /// Lists pipeline runs for a specific pipeline
    /// GET /{org}/{project}/_apis/pipelines/{pipelineId}/runs
    func fetchPipelineRuns(project: String, pipelineId: Int, top: Int? = nil, skip: Int? = nil) async throws -> [AzureDevOpsPipelineRun] {
        let pat = try await patProvider()
        let baseURL = await apiHost()
        guard var components = URLComponents(
            url: baseURL.appending(path: "/\(project)/_apis/pipelines/\(pipelineId)/runs"),
            resolvingAgainstBaseURL: false
        ) else {
            throw URLError(.badURL)
        }
        components.queryItems = buildPaginationParams(top: top, skip: skip)
        guard let url = components.url else { throw URLError(.badURL) }
        let (data, _) = try await authorizedGet(url: url, pat: pat)
        let response = try AzureDevOpsDecoding.decode(AzureDevOpsListResponse<AzureDevOpsPipelineRun>.self, from: data)
        return response.value
    }

    /// Gets details of a specific pipeline run
    /// GET /{org}/{project}/_apis/pipelines/runs/{runId}
    func fetchPipelineRun(project: String, runId: Int) async throws -> AzureDevOpsPipelineRun {
        let pat = try await patProvider()
        let baseURL = await apiHost()
        let url = baseURL.appending(path: "/\(project)/_apis/pipelines/runs/\(runId)")
        let (data, _) = try await authorizedGet(url: url, pat: pat)
        return try AzureDevOpsDecoding.decode(AzureDevOpsPipelineRun.self, from: data)
    }

    /// Lists all pipeline runs with pagination
    func fetchAllPipelineRuns(project: String, pipelineId: Int, limit: Int? = nil) async throws -> [AzureDevOpsPipelineRun] {
        try await fetchAllPages(
            path: "/\(project)/_apis/pipelines/\(pipelineId)/runs",
            queryItems: [],
            limit: limit,
            decode: { try AzureDevOpsDecoding.decode(AzureDevOpsListResponse<AzureDevOpsPipelineRun>.self, from: $0).value }
        )
    }

    // MARK: - Commits

    /// Lists commits for a repository
    /// GET /{org}/{project}/_apis/git/repositories/{repoId}/commits
    func fetchCommits(
        project: String,
        repoId: String,
        branchName: String? = nil,
        top: Int? = nil,
        skip: Int? = nil
    ) async throws -> [AzureDevOpsCommit] {
        let pat = try await patProvider()
        let baseURL = await apiHost()
        guard var components = URLComponents(
            url: baseURL.appending(path: "/\(project)/_apis/git/repositories/\(repoId)/commits"),
            resolvingAgainstBaseURL: false
        ) else {
            throw URLError(.badURL)
        }
        var items = buildPaginationParams(top: top, skip: skip)
        if let branchName = branchName {
            items.append(URLQueryItem(name: "searchCriteria.branchName", value: branchName))
        }
        components.queryItems = items
        guard let url = components.url else { throw URLError(.badURL) }
        let (data, _) = try await authorizedGet(url: url, pat: pat)
        let response = try AzureDevOpsDecoding.decode(AzureDevOpsListResponse<AzureDevOpsCommit>.self, from: data)
        return response.value
    }

    /// Lists commits with pagination
    func fetchAllCommits(
        project: String,
        repoId: String,
        branchName: String? = nil,
        limit: Int? = nil
    ) async throws -> [AzureDevOpsCommit] {
        var queryItems: [URLQueryItem] = []
        if let branchName = branchName {
            queryItems.append(URLQueryItem(name: "searchCriteria.branchName", value: branchName))
        }
        return try await fetchAllPages(
            path: "/\(project)/_apis/git/repositories/\(repoId)/commits",
            queryItems: queryItems,
            limit: limit,
            decode: { try AzureDevOpsDecoding.decode(AzureDevOpsListResponse<AzureDevOpsCommit>.self, from: $0).value }
        )
    }

    // MARK: - Branches / Refs

    /// Lists refs (branches and tags) for a repository
    /// GET /{org}/{project}/_apis/git/repositories/{repoId}/refs
    func fetchRefs(
        project: String,
        repoId: String,
        filter: String? = nil,
        top: Int? = nil,
        skip: Int? = nil
    ) async throws -> [AzureDevOpsBranch] {
        let pat = try await patProvider()
        let baseURL = await apiHost()
        guard var components = URLComponents(
            url: baseURL.appending(path: "/\(project)/_apis/git/repositories/\(repoId)/refs"),
            resolvingAgainstBaseURL: false
        ) else {
            throw URLError(.badURL)
        }
        var items = buildPaginationParams(top: top, skip: skip)
        if let filter = filter {
            items.append(URLQueryItem(name: "filter", value: filter))
        }
        components.queryItems = items
        guard let url = components.url else { throw URLError(.badURL) }
        let (data, _) = try await authorizedGet(url: url, pat: pat)
        let response = try AzureDevOpsDecoding.decode(AzureDevOpsListResponse<AzureDevOpsBranch>.self, from: data)
        return response.value
    }

    /// Lists branches (refs/heads) for a repository
    func fetchBranches(project: String, repoId: String, top: Int? = nil, skip: Int? = nil) async throws -> [AzureDevOpsBranch] {
        try await fetchRefs(project: project, repoId: repoId, filter: "heads", top: top, skip: skip)
    }

    /// Lists tags (refs/tags) for a repository
    func fetchTags(project: String, repoId: String, top: Int? = nil, skip: Int? = nil) async throws -> [AzureDevOpsBranch] {
        try await fetchRefs(project: project, repoId: repoId, filter: "tags", top: top, skip: skip)
    }

    // MARK: - Private Helpers

    private func buildPaginationParams(top: Int?, skip: Int?) -> [URLQueryItem] {
        var items: [URLQueryItem] = []
        items.append(URLQueryItem(name: "api-version", value: "7.0"))
        if let top = top {
            items.append(URLQueryItem(name: "$top", value: "\(top)"))
        }
        if let skip = skip {
            items.append(URLQueryItem(name: "$skip", value: "\(skip)"))
        }
        return items
    }

    private func authorizedGet(url: URL, pat: String) async throws -> (Data, HTTPURLResponse) {
        try await self.requestRunner.get(url: url, pat: pat)
    }

    private func authorizedPost(url: URL, request: URLRequest, pat: String) async throws -> (Data, HTTPURLResponse) {
        var mutableRequest = request
        let credentials = ":\(pat)"
        if let encodedCredentials = credentials.data(using: .utf8)?.base64EncodedString() {
            mutableRequest.addValue("Basic \(encodedCredentials)", forHTTPHeaderField: "Authorization")
        }
        mutableRequest.addValue("application/json", forHTTPHeaderField: "Accept")
        mutableRequest.addValue("7.0", forHTTPHeaderField: "X-VSS-Api-Version")

        let (data, responseAny) = try await URLSession.shared.data(for: mutableRequest)
        guard let response = responseAny as? HTTPURLResponse else { throw URLError(.badServerResponse) }
        return (data, response)
    }

    private func fetchAllPages<T>(
        path: String,
        queryItems: [URLQueryItem],
        limit: Int?,
        decode: @escaping (Data) throws -> [T]
    ) async throws -> [T] {
        let pageSize = 100 // Azure DevOps maximum
        var collected: [T] = []
        var skip = 0

        while true {
            let pat = try await patProvider()
            let baseURL = await apiHost()
            guard var components = URLComponents(url: baseURL.appending(path: path), resolvingAgainstBaseURL: false) else {
                throw URLError(.badURL)
            }
            var items = queryItems.filter { $0.name != "$top" && $0.name != "$skip" }
            items.append(URLQueryItem(name: "$top", value: "\(pageSize)"))
            items.append(URLQueryItem(name: "$skip", value: "\(skip)"))
            items.append(URLQueryItem(name: "api-version", value: "7.0"))
            components.queryItems = items

            guard let url = components.url else { throw URLError(.badURL) }
            let (data, _) = try await authorizedGet(url: url, pat: pat)
            let itemsPage = try decode(data)
            collected.append(contentsOf: itemsPage)

            if let limit, collected.count >= limit {
                break
            }
            if itemsPage.count < pageSize {
                break // Azure DevOps returned a short page
            }
            skip += pageSize
        }

        if let limit {
            return Array(collected.prefix(limit))
        }
        return collected
    }
}

// MARK: - Supporting Types

enum AzureDevOpsPullRequestStatus: String, Sendable {
    case active
    case completed
    case abandoned
    case all

    var queryValue: String {
        switch self {
        case .active: return "Active"
        case .completed: return "Completed"
        case .abandoned: return "Abandoned"
        case .all: return "All"
        }
    }
}

struct AzureDevOpsConnectionData: Decodable, Sendable {
    let authenticatedUser: IdentityRef?
    let authorizedUser: IdentityRef?
    let organization: AzureDevOpsOrganization?
    let webApiVersion: [String: String]?

    enum CodingKeys: String, CodingKey {
        case authenticatedUser
        case authorizedUser
        case organization
        case webApiVersion
    }
}

struct AzureDevOpsWIQLQuery: Encodable, Sendable {
    let query: String
}

struct AzureDevOpsWIQLResult: Decodable, Sendable {
    let queryType: String?
    let queryResultType: String?
    let asOf: Date?
    let columns: [WorkItemFieldReference]?
    let workItems: [WorkItemReference]?

    enum CodingKeys: String, CodingKey {
        case queryType
        case queryResultType
        case asOf
        case columns
        case workItems
    }

    struct WorkItemFieldReference: Decodable, Sendable {
        let referenceName: String?
        let name: String?
        let type: String?
    }

    struct WorkItemReference: Decodable, Sendable {
        let id: Int
        let url: String?
    }
}
