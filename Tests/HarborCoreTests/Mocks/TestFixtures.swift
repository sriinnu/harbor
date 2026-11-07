import Foundation
@testable import HarborCore

/// Common test data and fixtures for HarborCore tests
public enum TestFixtures {
    // MARK: - OAuth Test Data

    /// Sample OAuth tokens for testing
    public static let sampleTokens = OAuthTokens(
        accessToken: "gho_test_access_token_1234567890abcdef",
        refreshToken: "ghr_test_refresh_token_1234567890abcdef",
        expiresAt: Date(timeIntervalSinceNow: 3600)
    )

    /// Expired OAuth tokens for refresh testing
    public static let expiredTokens = OAuthTokens(
        accessToken: "gho_expired_token",
        refreshToken: "ghr_refresh_token",
        expiresAt: Date(timeIntervalSinceNow: -3600)
    )

    /// Sample client credentials
    public static let sampleClientCredentials = OAuthClientCredentials(
        clientID: "test_client_id_12345",
        clientSecret: "test_client_secret_67890"
    )

    // MARK: - User Settings Test Data

    /// Default user settings
    public static let defaultSettings = UserSettings()

    /// Customized user settings for testing
    public static let customSettings: UserSettings = {
        var settings = UserSettings()
        settings.appearance.accentTone = .system
        settings.appearance.cardDensity = .compact
        settings.heatmap.display = .submenu
        settings.heatmap.span = .sixMonths
        settings.repoList.displayLimit = 10
        settings.repoList.showForks = true
        settings.refreshInterval = .twoMinutes
        settings.launchAtLogin = true
        return settings
    }()

    // MARK: - Mock HTTP Responses

    /// Mock successful token response
    public static let tokenResponseJSON = """
    {
        "access_token": "gho_test_access_token",
        "token_type": "bearer",
        "scope": "repo read:org",
        "expires_in": 3600,
        "refresh_token": "ghr_test_refresh_token"
    }
    """

    /// Mock GitHub user response
    public static let userResponseJSON = """
    {
        "login": "testuser",
        "id": 12345,
        "avatar_url": "https://avatars.githubusercontent.com/u/12345",
        "name": "Test User",
        "email": "test@example.com"
    }
    """

    // MARK: - Test URLs and Paths

    /// Test GitHub host URL
    public static let githubHost = URL(string: "https://github.com")!

    /// Test enterprise GitHub host URL
    public static let enterpriseHost = URL(string: "https://github.enterprise.com")!

    /// Test callback URL
    public static let callbackURL = URL(string: "http://127.0.0.1:53682/callback")!

    /// Test git executable path
    public static let gitExecutablePath = "/usr/bin/git"

    /// Test git version string
    public static let gitVersionString = "git version 2.42.0"

    // MARK: - OAuth Flow Test Data

    /// Test authorization code
    public static let authCode = "test_auth_code_12345"

    /// Test state parameter
    public static let stateParameter = "test_state_parameter_67890"

    /// Test PKCE verifier
    public static let pkceVerifier = "test_pkce_verifier_1234567890"

    /// Test PKCE challenge
    public static let pkceChallenge = "test_pkce_challenge_1234567890"

    // MARK: - Helper Functions

    /// Create a temporary directory for testing
    public static func createTemporaryDirectory() throws -> URL {
        let tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("HarborTests")
            .appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        return tempDir
    }

    /// Clean up a temporary directory
    public static func cleanupTemporaryDirectory(_ url: URL) {
        try? FileManager.default.removeItem(at: url)
    }

    /// Create a mock HTTP response
    public static func mockHTTPResponse(
        statusCode: Int = 200,
        headerFields: [String: String]? = nil
    ) -> HTTPURLResponse {
        HTTPURLResponse(
            url: githubHost,
            statusCode: statusCode,
            httpVersion: "HTTP/1.1",
            headerFields: headerFields
        )!
    }

    /// Create mock response data from JSON string
    public static func mockData(from json: String) -> Data {
        json.data(using: .utf8)!
    }
}
