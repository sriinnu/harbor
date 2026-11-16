import Foundation

/// Errors that can occur when interacting with the GitLab API
public enum GitLabAPIError: Error, LocalizedError, Sendable {
    case invalidURL
    case invalidResponse
    case httpError(statusCode: Int, message: String?)
    case decodingError(Error)
    case unauthorized
    case rateLimited(retryAfter: Int?)
    case networkError(Error)
    case invalidInstanceURL

    public var errorDescription: String? {
        switch self {
        case .invalidURL:
            return "Invalid URL"
        case .invalidResponse:
            return "Invalid response from server"
        case let .httpError(statusCode, message):
            return "HTTP error \(statusCode): \(message ?? "Unknown error")"
        case let .decodingError(error):
            return "Failed to decode response: \(error.localizedDescription)"
        case .unauthorized:
            return "Unauthorized - check your access token"
        case let .rateLimited(retryAfter):
            if let retryAfter = retryAfter {
                return "Rate limited. Retry after \(retryAfter) seconds"
            }
            return "Rate limited"
        case let .networkError(error):
            return "Network error: \(error.localizedDescription)"
        case .invalidInstanceURL:
            return "Invalid GitLab instance URL"
        }
    }
}

/// GitLab REST API client for interacting with GitLab instances
public actor GitLabClient {
    // MARK: - Configuration

    /// The base URL for the GitLab API (e.g., https://gitlab.com/api/v4)
    public let apiBaseURL: URL

    /// The authentication token (PRIVATE-TOKEN or OAuth)
    private var token: String

    private let session: URLSession
    private let decoder: JSONDecoder
    private let diag = DiagnosticsLogger.shared

    // MARK: - Initialization

    /// Creates a new GitLab client
    /// - Parameters:
    ///   - instanceURL: The base URL of the GitLab instance (e.g., https://gitlab.com)
    ///   - token: The authentication token (PRIVATE-TOKEN or OAuth token)
    public init(instanceURL: URL, token: String) {
        // Validate the instance URL
        guard instanceURL.scheme?.lowercased() == "https" else {
            fatalError("GitLab API requires HTTPS")
        }

        // Build the API v4 base URL
        self.apiBaseURL = instanceURL.appendingPathComponent("api/v4")
        self.token = token

        // Configure session with default settings
        let config = HarborURLSession.configuration()
        config.timeoutIntervalForRequest = 30
        config.timeoutIntervalForResource = 60
        self.session = URLSession(configuration: config)

        // Configure JSON decoder for GitLab API responses
        self.decoder = JSONDecoder()
        self.decoder.dateDecodingStrategy = .iso8601
        self.decoder.keyDecodingStrategy = .convertFromSnakeCase
    }

    /// Creates a new GitLab client from URL string
    /// - Parameters:
    ///   - instanceURLString: The base URL string of the GitLab instance
    ///   - token: The authentication token
    public init(instanceURLString: String, token: String) {
        guard let url = URL(string: instanceURLString) else {
            fatalError("Invalid GitLab instance URL: \(instanceURLString)")
        }
        self.init(instanceURL: url, token: token)
    }

    // MARK: - Projects

    /// Fetches projects for the authenticated user
    /// - Parameter membership: If true, returns only projects where the user is a member
    /// - Returns: Array of GitLab projects
    public func fetchProjects(membership: Bool = true) async throws -> [GitLabProject] {
        var components = URLComponents(url: apiBaseURL.appendingPathComponent("projects"), resolvingAgainstBaseURL: true)!
        components.queryItems = [
            URLQueryItem(name: "membership", value: membership ? "true" : "false"),
            URLQueryItem(name: "per_page", value: "100"),
            URLQueryItem(name: "order_by", value: "last_activity_at")
        ]

        guard let url = components.url else {
            throw GitLabAPIError.invalidURL
        }

        return try await fetchAllPages(url: url)
    }

    /// Fetches a specific project by ID
    /// - Parameter projectId: The project ID (can be numeric ID or path-encoded path)
    /// - Returns: The GitLab project
    public func fetchProject(projectId: String) async throws -> GitLabProject {
        let url = apiBaseURL.appendingPathComponent("projects/\(projectId)")

        let (data, response) = try await performRequest(url: url)

        try validateResponse(response)

        do {
            return try decoder.decode(GitLabProject.self, from: data)
        } catch {
            throw GitLabAPIError.decodingError(error)
        }
    }

    // MARK: - Issues

    /// Fetches issues for the authenticated user
    /// - Parameters:
    ///   - state: Filter by state (opened, closed, all)
    ///   - scope: Filter by scope (created_by_me, assigned_to_me, all)
    /// - Returns: Array of GitLab issues
    public func fetchIssues(state: String = "opened", scope: String = "all") async throws -> [GitLabIssue] {
        var components = URLComponents(url: apiBaseURL.appendingPathComponent("issues"), resolvingAgainstBaseURL: true)!
        components.queryItems = [
            URLQueryItem(name: "state", value: state),
            URLQueryItem(name: "scope", value: scope),
            URLQueryItem(name: "per_page", value: "100")
        ]

        guard let url = components.url else {
            throw GitLabAPIError.invalidURL
        }

        return try await fetchAllPages(url: url)
    }

    /// Fetches issues for a specific project
    /// - Parameters:
    ///   - projectId: The project ID
    ///   - state: Filter by state (opened, closed, all)
    /// - Returns: Array of GitLab issues
    public func fetchIssues(projectId: Int, state: String = "opened") async throws -> [GitLabIssue] {
        var components = URLComponents(url: apiBaseURL.appendingPathComponent("projects/\(projectId)/issues"), resolvingAgainstBaseURL: true)!
        components.queryItems = [
            URLQueryItem(name: "state", value: state),
            URLQueryItem(name: "per_page", value: "100")
        ]

        guard let url = components.url else {
            throw GitLabAPIError.invalidURL
        }

        return try await fetchAllPages(url: url)
    }

    // MARK: - Merge Requests

    /// Fetches merge requests for the authenticated user
    /// - Parameters:
    ///   - state: Filter by state (opened, closed, merged, all)
    ///   - scope: Filter by scope (created_by_me, assigned_to_me, all)
    /// - Returns: Array of GitLab merge requests
    public func fetchMergeRequests(state: String = "opened", scope: String = "all") async throws -> [GitLabMergeRequest] {
        var components = URLComponents(url: apiBaseURL.appendingPathComponent("merge_requests"), resolvingAgainstBaseURL: true)!
        components.queryItems = [
            URLQueryItem(name: "state", value: state),
            URLQueryItem(name: "scope", value: scope),
            URLQueryItem(name: "per_page", value: "100"),
            URLQueryItem(name: "order_by", value: "created_at")
        ]

        guard let url = components.url else {
            throw GitLabAPIError.invalidURL
        }

        return try await fetchAllPages(url: url)
    }

    /// Fetches merge requests for a specific project
    /// - Parameters:
    ///   - projectId: The project ID
    ///   - state: Filter by state (opened, closed, merged, all)
    /// - Returns: Array of GitLab merge requests
    public func fetchMergeRequests(projectId: Int, state: String = "opened") async throws -> [GitLabMergeRequest] {
        var components = URLComponents(url: apiBaseURL.appendingPathComponent("projects/\(projectId)/merge_requests"), resolvingAgainstBaseURL: true)!
        components.queryItems = [
            URLQueryItem(name: "state", value: state),
            URLQueryItem(name: "per_page", value: "100")
        ]

        guard let url = components.url else {
            throw GitLabAPIError.invalidURL
        }

        return try await fetchAllPages(url: url)
    }

    // MARK: - Pipelines

    /// Fetches pipelines for a specific project
    /// - Parameters:
    ///   - projectId: The project ID
    ///   - ref: Optional ref (branch/tag) to filter by
    ///   - status: Optional status to filter by
    /// - Returns: Array of GitLab pipelines
    public func fetchPipelines(projectId: Int, ref: String? = nil, status: String? = nil) async throws -> [GitLabPipeline] {
        var components = URLComponents(url: apiBaseURL.appendingPathComponent("projects/\(projectId)/pipelines"), resolvingAgainstBaseURL: true)!
        var queryItems = [
            URLQueryItem(name: "per_page", value: "100")
        ]

        if let ref = ref {
            queryItems.append(URLQueryItem(name: "ref", value: ref))
        }

        if let status = status {
            queryItems.append(URLQueryItem(name: "status", value: status))
        }

        components.queryItems = queryItems

        guard let url = components.url else {
            throw GitLabAPIError.invalidURL
        }

        return try await fetchAllPages(url: url)
    }

    /// Fetches a specific pipeline by ID
    /// - Parameters:
    ///   - projectId: The project ID
    ///   - pipelineId: The pipeline ID
    /// - Returns: The GitLab pipeline
    public func fetchPipeline(projectId: Int, pipelineId: Int) async throws -> GitLabPipeline {
        let url = apiBaseURL.appendingPathComponent("projects/\(projectId)/pipelines/\(pipelineId)")

        let (data, response) = try await performRequest(url: url)

        try validateResponse(response)

        do {
            return try decoder.decode(GitLabPipeline.self, from: data)
        } catch {
            throw GitLabAPIError.decodingError(error)
        }
    }

    // MARK: - User

    /// Fetches the current user's profile
    /// - Returns: The current GitLab user
    public func fetchCurrentUser() async throws -> GitLabUser {
        let url = apiBaseURL.appendingPathComponent("user")

        let (data, response) = try await performRequest(url: url)

        try validateResponse(response)

        do {
            return try decoder.decode(GitLabUser.self, from: data)
        } catch {
            throw GitLabAPIError.decodingError(error)
        }
    }

    // MARK: - Activity

    /// The user's events between two days, newest first, as per-day activity. Follows
    /// `Link` pages up to `maxPages` (100 events each); `partial` is set when pages remain,
    /// so the oldest days are undercounted. GitLab only keeps three years of events.
    public func userActivity(since: Date, until: Date, maxPages: Int, timeZone: TimeZone = .current) async throws -> ProviderActivityResult {
        let user = try await fetchCurrentUser()
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = timeZone
        formatter.dateFormat = "yyyy-MM-dd"
        // `after` and `before` are exclusive dates.
        let day: TimeInterval = 86400
        var components = URLComponents(url: apiBaseURL.appendingPathComponent("users/\(user.id)/events"), resolvingAgainstBaseURL: true)!
        components.queryItems = [
            URLQueryItem(name: "after", value: formatter.string(from: since.addingTimeInterval(-day))),
            URLQueryItem(name: "before", value: formatter.string(from: until.addingTimeInterval(day))),
            URLQueryItem(name: "per_page", value: "100")
        ]
        guard let first = components.url else { throw GitLabAPIError.invalidURL }

        var events: [GitLabEvent] = []
        var next: URL? = first
        var pages = 0
        while let url = next, pages < maxPages {
            let (data, response) = try await performRequest(url: url)
            try validateResponse(response)
            do {
                events.append(contentsOf: try decoder.decode([GitLabEvent].self, from: data))
            } catch {
                throw GitLabAPIError.decodingError(error)
            }
            pages += 1
            next = (response as? HTTPURLResponse)?.value(forHTTPHeaderField: "Link").flatMap(parseNextPageURL(from:))
        }
        return ProviderActivityResult(
            provider: .gitlab, days: GitLabActivityMapper.days(events: events, timeZone: timeZone), partial: next != nil
        )
    }

    // MARK: - Private Helpers

    private func performRequest(url: URL) async throws -> (Data, URLResponse) {
        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.setValue("Bearer \(token)", forHTTPHeaderField: "PRIVATE-TOKEN")
        request.setValue("application/json", forHTTPHeaderField: "Accept")

        do {
            let (data, response) = try await self.session.data(for: request)
            return (data, response)
        } catch let error as URLError {
            throw GitLabAPIError.networkError(error)
        }
    }

    private func validateResponse(_ response: URLResponse) throws {
        guard let httpResponse = response as? HTTPURLResponse else {
            throw GitLabAPIError.invalidResponse
        }

        switch httpResponse.statusCode {
        case 200...299:
            return
        case 401:
            throw GitLabAPIError.unauthorized
        case 429:
            let retryAfter = httpResponse.value(forHTTPHeaderField: "Retry-After").flatMap(Int.init)
            throw GitLabAPIError.rateLimited(retryAfter: retryAfter)
        default:
            throw GitLabAPIError.httpError(statusCode: httpResponse.statusCode, message: nil)
        }
    }

    private func fetchAllPages<T: Decodable>(url: URL) async throws -> [T] {
        var allItems: [T] = []
        var currentURL: URL? = url

        while let url = currentURL {
            let (data, response) = try await performRequest(url: url)

            try validateResponse(response)

            // Check for pagination headers
            let httpResponse = response as? HTTPURLResponse
            let linkHeader = httpResponse?.value(forHTTPHeaderField: "Link")

            // Decode items
            do {
                let items = try decoder.decode([T].self, from: data)
                allItems.append(contentsOf: items)
            } catch {
                throw GitLabAPIError.decodingError(error)
            }

            // Parse next page URL from Link header
            if let linkHeader = linkHeader, let nextURL = parseNextPageURL(from: linkHeader) {
                currentURL = nextURL
            } else {
                currentURL = nil
            }
        }

        return allItems
    }

    private func parseNextPageURL(from linkHeader: String) -> URL? {
        // Parse Link header format: <https://gitlab.com/api/v4/projects?page=2>; rel="next"
        let components = linkHeader.components(separatedBy: ",")
        for component in components {
            let parts = component.components(separatedBy: ";")
            guard parts.count == 2,
                  let urlRange = parts[0].range(of: "<([^>]+)>", options: .regularExpression) else {
                continue
            }

            let urlString = String(parts[0][urlRange]).trimmingCharacters(in: CharacterSet(charactersIn: "<>"))
            let rel = parts[1].trimmingCharacters(in: .whitespaces)

            if rel.contains("rel=\"next\"") {
                return URL(string: urlString)
            }
        }

        return nil
    }
}
