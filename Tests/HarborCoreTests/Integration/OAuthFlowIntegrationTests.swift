import Testing
import Foundation
@testable import HarborCore

/// Thread-safe wrapper for test state capture
private final class TestState<T>: @unchecked Sendable {
    private var value: T
    private let lock = NSLock()

    init(_ initial: T) {
        self.value = initial
    }

    func set(_ newValue: T) {
        lock.lock()
        defer { lock.unlock() }
        value = newValue
    }

    func get() -> T {
        lock.lock()
        defer { lock.unlock() }
        return value
    }
}

/// Integration tests for complete OAuth authentication flow
@Suite("OAuth Flow Integration Tests")
@MainActor
struct OAuthFlowIntegrationTests {

    // MARK: - Complete OAuth Flow Tests

    @Test("Complete OAuth login flow with mocks")
    func completeOAuthLoginFlowWithMocks() async throws {
        // Setup platform services with mocks
        let mockAPI = MockGitHubAPI()
        await mockAPI.mockSuccessfulTokenExchange()

        let tokenStorage = InMemoryTokenStorage()
        let callbackServer = MockCallbackServer()
        let services = MockPlatformServices(
            tokenStorage: tokenStorage,
            callbackServer: callbackServer
        )

        // Configure mock callback
        await callbackServer.configureMock(
            code: TestFixtures.authCode,
            state: TestFixtures.stateParameter
        )

        // Create OAuth flow
        let flow = OAuthLoginFlow(
            platform: services,
            openURL: { _ in },
            dataProvider: { request in
                try await mockAPI.dataProvider(for: request)
            }
        )

        // Execute login
        let tokens = try await flow.login(
            clientID: TestFixtures.sampleClientCredentials.clientID,
            clientSecret: TestFixtures.sampleClientCredentials.clientSecret,
            host: TestFixtures.githubHost,
            loopbackPort: 53682,
            timeout: 5.0
        )

        // Verify tokens were returned
        #expect(tokens.accessToken == "gho_mock_token")
        #expect(tokens.refreshToken == "ghr_mock_refresh")

        // Verify tokens were saved to storage
        let savedTokens = try await tokenStorage.load()
        #expect(savedTokens?.accessToken == "gho_mock_token")

        // Verify client credentials were saved
        let savedCredentials = try await tokenStorage.loadClientCredentials()
        #expect(savedCredentials?.clientID == TestFixtures.sampleClientCredentials.clientID)
    }

    @Test("OAuth flow handles callback timeout")
    func oauthFlowHandlesCallbackTimeout() async throws {
        let mockAPI = MockGitHubAPI()
        await mockAPI.mockSuccessfulTokenExchange()

        let callbackServer = MockCallbackServer()
        await callbackServer.configureFailure()

        let services = MockPlatformServices(callbackServer: callbackServer)

        let flow = OAuthLoginFlow(
            platform: services,
            openURL: { _ in },
            dataProvider: { request in
                try await mockAPI.dataProvider(for: request)
            }
        )

        await #expect(throws: URLError.self) {
            _ = try await flow.login(
                clientID: "test_client",
                clientSecret: "test_secret",
                host: TestFixtures.githubHost,
                loopbackPort: 53682,
                timeout: 0.1
            )
        }
    }

    @Test("OAuth flow handles token exchange failure")
    func oauthFlowHandlesTokenExchangeFailure() async throws {
        let mockAPI = MockGitHubAPI()
        await mockAPI.mockFailedTokenExchange()

        let callbackServer = MockCallbackServer()
        await callbackServer.configureMock(code: "invalid_code", state: "state")

        let services = MockPlatformServices(callbackServer: callbackServer)

        let flow = OAuthLoginFlow(
            platform: services,
            openURL: { _ in },
            dataProvider: { request in
                try await mockAPI.dataProvider(for: request)
            }
        )

        await #expect(throws: URLError.self) {
            _ = try await flow.login(
                clientID: "test_client",
                clientSecret: "test_secret",
                host: TestFixtures.githubHost,
                loopbackPort: 53682,
                timeout: 5.0
            )
        }
    }

    @Test("OAuth flow validates state parameter")
    func oauthFlowValidatesStateParameter() async throws {
        let mockAPI = MockGitHubAPI()
        await mockAPI.mockSuccessfulTokenExchange()

        let callbackServer = MockCallbackServer()
        // Configure callback with wrong state
        await callbackServer.configureMock(code: "code", state: "wrong_state")

        let services = MockPlatformServices(callbackServer: callbackServer)

        let flow = OAuthLoginFlow(
            platform: services,
            openURL: { _ in },
            dataProvider: { request in
                try await mockAPI.dataProvider(for: request)
            }
        )

        await #expect(throws: URLError.self) {
            _ = try await flow.login(
                clientID: "test_client",
                clientSecret: "test_secret",
                host: TestFixtures.githubHost,
                loopbackPort: 53682,
                timeout: 5.0
            )
        }
    }

    @Test("OAuth flow works with enterprise GitHub host")
    func oauthFlowWorksWithEnterpriseGitHubHost() async throws {
        let mockAPI = MockGitHubAPI()
        await mockAPI.mockSuccessfulTokenExchange()

        let callbackServer = MockCallbackServer()
        await callbackServer.configureMock(code: "code", state: "state")

        let services = MockPlatformServices(callbackServer: callbackServer)

        let flow = OAuthLoginFlow(
            platform: services,
            openURL: { _ in },
            dataProvider: { request in
                // Verify request goes to enterprise host
                if let url = request.url?.absoluteString {
                    #expect(url.contains("github.enterprise.com"))
                }
                return try await mockAPI.dataProvider(for: request)
            }
        )

        let tokens = try await flow.login(
            clientID: "test_client",
            clientSecret: "test_secret",
            host: TestFixtures.enterpriseHost,
            loopbackPort: 53682,
            timeout: 5.0
        )

        #expect(tokens.accessToken == "gho_mock_token")
    }

    @Test("OAuth flow normalizes host URL")
    func oauthFlowNormalizesHostURL() throws {
        // Test various host formats
        let testCases: [(input: String, expected: String)] = [
            ("github.com", "https://github.com"),
            ("http://github.com", "https://github.com"),
            ("https://github.com", "https://github.com"),
            ("https://github.com/", "https://github.com"),
            ("https://github.com/path", "https://github.com"),
            ("https://github.com?query=value", "https://github.com")
        ]

        for testCase in testCases {
            let input = URL(string: testCase.input)!
            let normalized = try OAuthLoginFlow.normalizeHost(input)
            #expect(normalized.absoluteString == testCase.expected)
        }
    }

    @Test("OAuth flow rejects invalid hosts")
    func oauthFlowRejectsInvalidHosts() {
        let invalidHosts = [
            URL(string: "ftp://github.com")!,
            URL(string: "http://localhost")!
        ]

        for host in invalidHosts {
            #expect(throws: GitHubAPIError.self) {
                _ = try OAuthLoginFlow.normalizeHost(host)
            }
        }
    }

    // MARK: - Token Storage Integration

    @Test("OAuth tokens persist to storage")
    func oauthTokensPersistToStorage() async throws {
        let mockAPI = MockGitHubAPI()
        await mockAPI.mockSuccessfulTokenExchange()

        let tokenStorage = InMemoryTokenStorage()
        let callbackServer = MockCallbackServer()
        await callbackServer.configureMock(code: "code", state: "state")

        let services = MockPlatformServices(
            tokenStorage: tokenStorage,
            callbackServer: callbackServer
        )

        let flow = OAuthLoginFlow(
            platform: services,
            openURL: { _ in },
            dataProvider: { request in
                try await mockAPI.dataProvider(for: request)
            }
        )

        _ = try await flow.login(
            clientID: "client_id",
            clientSecret: "client_secret",
            host: TestFixtures.githubHost,
            loopbackPort: 53682,
            timeout: 5.0
        )

        // Verify storage
        let storedTokens = try await tokenStorage.load()
        let storedCredentials = try await tokenStorage.loadClientCredentials()

        #expect(storedTokens != nil)
        #expect(storedCredentials != nil)
        #expect(storedCredentials?.clientID == "client_id")
    }

    @Test("Multiple OAuth flows with different services")
    func multipleOAuthFlowsWithDifferentServices() async throws {
        // Simulate multiple users or accounts
        let mockAPI1 = MockGitHubAPI()
        await mockAPI1.mockSuccessfulTokenExchange()

        let mockAPI2 = MockGitHubAPI()
        await mockAPI2.mockSuccessfulTokenExchange()

        let storage1 = InMemoryTokenStorage()
        let storage2 = InMemoryTokenStorage()

        let server1 = MockCallbackServer()
        let server2 = MockCallbackServer()

        await server1.configureMock(code: "code1", state: "state1")
        await server2.configureMock(code: "code2", state: "state2")

        let services1 = MockPlatformServices(
            tokenStorage: storage1,
            callbackServer: server1
        )
        let services2 = MockPlatformServices(
            tokenStorage: storage2,
            callbackServer: server2
        )

        let flow1 = OAuthLoginFlow(
            platform: services1,
            openURL: { _ in },
            dataProvider: { request in try await mockAPI1.dataProvider(for: request) }
        )

        let flow2 = OAuthLoginFlow(
            platform: services2,
            openURL: { _ in },
            dataProvider: { request in try await mockAPI2.dataProvider(for: request) }
        )

        // Execute both flows
        _ = try await flow1.login(
            clientID: "client1",
            clientSecret: "secret1",
            host: TestFixtures.githubHost,
            loopbackPort: 53682,
            timeout: 5.0
        )

        _ = try await flow2.login(
            clientID: "client2",
            clientSecret: "secret2",
            host: TestFixtures.githubHost,
            loopbackPort: 53683,
            timeout: 5.0
        )

        // Verify isolation
        let creds1 = try await storage1.loadClientCredentials()
        let creds2 = try await storage2.loadClientCredentials()

        #expect(creds1?.clientID == "client1")
        #expect(creds2?.clientID == "client2")
    }

    // MARK: - Callback Server Integration

    @Test("Callback server lifecycle during OAuth flow")
    func callbackServerLifecycleDuringOAuthFlow() async throws {
        let mockAPI = MockGitHubAPI()
        await mockAPI.mockSuccessfulTokenExchange()

        let callbackServer = MockCallbackServer()
        await callbackServer.configureMock(code: "code", state: "state")

        let services = MockPlatformServices(callbackServer: callbackServer)

        let serverStarted = TestState(false)

        let flow = OAuthLoginFlow(
            platform: services,
            openURL: { url in
                // Callback URL should be available when browser opens
                serverStarted.set(url.absoluteString.contains("callback"))
            },
            dataProvider: { request in
                try await mockAPI.dataProvider(for: request)
            }
        )

        _ = try await flow.login(
            clientID: "client",
            clientSecret: "secret",
            host: TestFixtures.githubHost,
            loopbackPort: 53682,
            timeout: 5.0
        )

        // Server should have been started
        #expect(serverStarted.get() == true)

        // Note: MockCallbackServer doesn't track stop state,
        // but real implementation should stop after callback
    }

    // MARK: - Error Recovery Tests

    @Test("OAuth flow cleans up on failure")
    func oauthFlowCleansUpOnFailure() async throws {
        let mockAPI = MockGitHubAPI()
        await mockAPI.mockNetworkTimeout()

        let callbackServer = MockCallbackServer()
        await callbackServer.configureMock(code: "code", state: "state")

        let tokenStorage = InMemoryTokenStorage()
        let services = MockPlatformServices(
            tokenStorage: tokenStorage,
            callbackServer: callbackServer
        )

        let flow = OAuthLoginFlow(
            platform: services,
            openURL: { _ in },
            dataProvider: { request in
                try await mockAPI.dataProvider(for: request)
            }
        )

        await #expect(throws: URLError.self) {
            _ = try await flow.login(
                clientID: "client",
                clientSecret: "secret",
                host: TestFixtures.githubHost,
                loopbackPort: 53682,
                timeout: 5.0
            )
        }

        // Storage should remain empty after failed login
        let tokens = try await tokenStorage.load()
        #expect(tokens == nil)
    }

    @Test("OAuth flow handles network errors gracefully")
    func oauthFlowHandlesNetworkErrorsGracefully() async throws {
        let mockAPI = MockGitHubAPI()
        await mockAPI.mockNoInternet()

        let callbackServer = MockCallbackServer()
        await callbackServer.configureMock(code: "code", state: "state")

        let services = MockPlatformServices(callbackServer: callbackServer)

        let flow = OAuthLoginFlow(
            platform: services,
            openURL: { _ in },
            dataProvider: { request in
                try await mockAPI.dataProvider(for: request)
            }
        )

        await #expect(throws: URLError.self) {
            _ = try await flow.login(
                clientID: "client",
                clientSecret: "secret",
                host: TestFixtures.githubHost,
                loopbackPort: 53682,
                timeout: 5.0
            )
        }
    }

    // MARK: - PKCE Integration

    @Test("OAuth flow includes PKCE parameters")
    func oauthFlowIncludesPKCEParameters() async throws {
        let mockAPI = MockGitHubAPI()
        await mockAPI.mockSuccessfulTokenExchange()

        let callbackServer = MockCallbackServer()
        await callbackServer.configureMock(code: "code", state: "state")

        let services = MockPlatformServices(callbackServer: callbackServer)

        let capturedAuthURL = TestState<URL?>(nil)
        let capturedTokenRequest = TestState<URLRequest?>(nil)

        let flow = OAuthLoginFlow(
            platform: services,
            openURL: { url in
                capturedAuthURL.set(url)
            },
            dataProvider: { request in
                capturedTokenRequest.set(request)
                return try await mockAPI.dataProvider(for: request)
            }
        )

        _ = try await flow.login(
            clientID: "client",
            clientSecret: "secret",
            host: TestFixtures.githubHost,
            loopbackPort: 53682,
            timeout: 5.0
        )

        // Verify PKCE challenge in authorization URL
        if let authURL = capturedAuthURL.get() {
            let components = URLComponents(url: authURL, resolvingAgainstBaseURL: false)
            let hasCodeChallenge = components?.queryItems?.contains { $0.name == "code_challenge" } ?? false
            let hasChallengeMethod = components?.queryItems?.contains { $0.name == "code_challenge_method" } ?? false

            #expect(hasCodeChallenge)
            #expect(hasChallengeMethod)
        }

        // Verify PKCE verifier in token request
        if let tokenRequest = capturedTokenRequest.get(),
           let body = tokenRequest.httpBody,
           let bodyString = String(data: body, encoding: .utf8) {
            #expect(bodyString.contains("code_verifier"))
        }
    }
}
