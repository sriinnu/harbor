import Foundation
@testable import HarborCore

/// Mock GitHub API for testing without making real network requests
public actor MockGitHubAPI {
    // MARK: - Configuration

    private var responses: [String: (Data, HTTPURLResponse)] = [:]
    private var errors: [String: Error] = [:]
    private var requestHistory: [(request: URLRequest, timestamp: Date)] = []

    public init() {}

    // MARK: - Mock Configuration

    /// Configure a mock response for a specific URL pattern
    public func mockResponse(
        for urlPattern: String,
        data: Data,
        statusCode: Int = 200,
        headers: [String: String]? = nil
    ) {
        let response = HTTPURLResponse(
            url: URL(string: "https://api.github.com")!,
            statusCode: statusCode,
            httpVersion: "HTTP/1.1",
            headerFields: headers
        )!
        responses[urlPattern] = (data, response)
    }

    /// Configure a mock error for a specific URL pattern
    public func mockError(for urlPattern: String, error: Error) {
        errors[urlPattern] = error
    }

    /// Reset all mock configurations
    public func reset() {
        responses.removeAll()
        errors.removeAll()
        requestHistory.removeAll()
    }

    // MARK: - Data Provider

    /// Data provider function that can be used with URLSession-based APIs
    public func dataProvider(for request: URLRequest) async throws -> (Data, URLResponse) {
        // Record the request
        requestHistory.append((request, Date()))

        guard let url = request.url?.absoluteString else {
            throw URLError(.badURL)
        }

        // Check for configured errors first
        for (pattern, error) in errors where url.contains(pattern) {
            throw error
        }

        // Check for configured responses
        for (pattern, response) in responses where url.contains(pattern) {
            return response
        }

        // Default: return not found error
        throw URLError(.resourceUnavailable)
    }

    // MARK: - Request History

    /// Get all recorded requests
    public func getRequestHistory() -> [(request: URLRequest, timestamp: Date)] {
        return requestHistory
    }

    /// Get the count of requests made
    public func getRequestCount() -> Int {
        return requestHistory.count
    }

    /// Clear request history
    public func clearHistory() {
        requestHistory.removeAll()
    }

    // MARK: - Common Mock Responses

    /// Configure mock for successful token exchange
    public func mockSuccessfulTokenExchange() {
        let json = """
        {
            "access_token": "gho_mock_token",
            "token_type": "bearer",
            "scope": "repo read:org",
            "expires_in": 3600,
            "refresh_token": "ghr_mock_refresh"
        }
        """
        mockResponse(
            for: "/login/oauth/access_token",
            data: json.data(using: .utf8)!,
            statusCode: 200
        )
    }

    /// Configure mock for failed token exchange
    public func mockFailedTokenExchange() {
        let json = """
        {
            "error": "invalid_grant",
            "error_description": "The authorization code is invalid or expired"
        }
        """
        mockResponse(
            for: "/login/oauth/access_token",
            data: json.data(using: .utf8)!,
            statusCode: 401
        )
    }

    /// Configure mock for successful token refresh
    public func mockSuccessfulTokenRefresh() {
        let json = """
        {
            "access_token": "gho_refreshed_token",
            "token_type": "bearer",
            "scope": "repo read:org",
            "expires_in": 3600,
            "refresh_token": "ghr_new_refresh_token"
        }
        """
        mockResponse(
            for: "/login/oauth/access_token",
            data: json.data(using: .utf8)!,
            statusCode: 200
        )
    }

    /// Configure mock for user info endpoint
    public func mockUserInfo(login: String = "testuser", id: Int = 12345) {
        let json = """
        {
            "login": "\(login)",
            "id": \(id),
            "avatar_url": "https://avatars.githubusercontent.com/u/\(id)",
            "name": "Test User",
            "email": "test@example.com",
            "bio": "Test bio",
            "public_repos": 10,
            "followers": 100,
            "following": 50
        }
        """
        mockResponse(
            for: "/user",
            data: json.data(using: .utf8)!,
            statusCode: 200
        )
    }

    /// Configure mock for rate limit exceeded
    public func mockRateLimitExceeded() {
        let json = """
        {
            "message": "API rate limit exceeded",
            "documentation_url": "https://docs.github.com/rest/overview/resources-in-the-rest-api#rate-limiting"
        }
        """
        mockResponse(
            for: "/",
            data: json.data(using: .utf8)!,
            statusCode: 403,
            headers: [
                "X-RateLimit-Limit": "60",
                "X-RateLimit-Remaining": "0",
                "X-RateLimit-Reset": String(Int(Date().timeIntervalSince1970) + 3600)
            ]
        )
    }

    /// Configure mock for network timeout
    public func mockNetworkTimeout() {
        mockError(for: "/", error: URLError(.timedOut))
    }

    /// Configure mock for no internet connection
    public func mockNoInternet() {
        mockError(for: "/", error: URLError(.notConnectedToInternet))
    }
}
