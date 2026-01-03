import Testing
import Foundation
@testable import HarborCore

/// Comprehensive tests for OAuthCallbackServer implementations
@Suite("OAuthCallbackServer Tests")
struct OAuthCallbackServerTests {

    // MARK: - MockCallbackServer Tests

    @Suite("MockCallbackServer")
    struct MockCallbackServerTestSuite {

        @Test("Start returns callback URL")
        func startReturnsCallbackURL() async throws {
            let server = MockCallbackServer()

            let url = try await server.start()

            #expect(url.scheme == "http")
            #expect(url.host == "127.0.0.1")
            #expect(url.path == "/callback")
        }

        @Test("Wait for callback returns configured response")
        func waitForCallbackReturnsConfiguredResponse() async throws {
            let server = MockCallbackServer()
            let expectedCode = "test_auth_code"
            let expectedState = "test_state"

            await server.configureMock(code: expectedCode, state: expectedState)
            _ = try await server.start()

            let result = try await server.waitForCallback(timeout: 1.0)

            #expect(result.code == expectedCode)
            #expect(result.state == expectedState)
        }

        @Test("Wait for callback throws when not configured")
        func waitForCallbackThrowsWhenNotConfigured() async throws {
            let server = MockCallbackServer()

            _ = try await server.start()

            await #expect(throws: URLError.self) {
                _ = try await server.waitForCallback(timeout: 0.1)
            }
        }

        @Test("Start throws when configured to fail")
        func startThrowsWhenConfiguredToFail() async throws {
            let server = MockCallbackServer()

            await server.configureFailure()

            await #expect(throws: URLError.self) {
                _ = try await server.start()
            }
        }

        @Test("Wait for callback throws when configured to fail")
        func waitForCallbackThrowsWhenConfiguredToFail() async throws {
            let server = MockCallbackServer()

            await server.configureFailure()

            await #expect(throws: URLError.self) {
                _ = try await server.start()
                _ = try await server.waitForCallback(timeout: 0.1)
            }
        }

        @Test("Stop clears mock response")
        func stopClearsMockResponse() async throws {
            let server = MockCallbackServer()

            await server.configureMock(code: "code", state: "state")
            _ = try await server.start()
            await server.stop()

            // After stop, should throw because no response configured
            await #expect(throws: URLError.self) {
                _ = try await server.start()
                _ = try await server.waitForCallback(timeout: 0.1)
            }
        }

        @Test("Multiple start and stop cycles")
        func multipleStartStopCycles() async throws {
            let server = MockCallbackServer()

            for i in 0..<3 {
                await server.configureMock(code: "code_\(i)", state: "state_\(i)")
                let url = try await server.start()
                #expect(url.absoluteString.contains("127.0.0.1"))

                let result = try await server.waitForCallback(timeout: 1.0)
                #expect(result.code == "code_\(i)")

                await server.stop()
            }
        }

        @Test("Respects timeout parameter")
        func respectsTimeoutParameter() async throws {
            let server = MockCallbackServer()

            await server.configureFailure()

            let start = Date()
            await #expect(throws: URLError.self) {
                _ = try await server.start()
                _ = try await server.waitForCallback(timeout: 0.1)
            }
            let elapsed = Date().timeIntervalSince(start)

            // Should fail quickly, not wait for default timeout
            #expect(elapsed < 1.0)
        }
    }

    // MARK: - NetworkFrameworkCallbackServer Tests (macOS only)

    #if os(macOS)
    @Suite("NetworkFrameworkCallbackServer")
    @MainActor
    struct NetworkFrameworkCallbackServerTestSuite {

        @Test("Start returns valid callback URL with correct port")
        func startReturnsValidCallbackURL() throws {
            let port = 53682
            let server = NetworkFrameworkCallbackServer(port: port)

            let url = try server.start()

            #expect(url.scheme == "http")
            #expect(url.host == "127.0.0.1")
            #expect(url.port == port)
            #expect(url.path == "/callback")

            server.stop()
        }

        @Test("Parse HTTP request correctly")
        func parseHTTPRequestCorrectly() {
            let request = """
            GET /callback?code=test_code_12345&state=test_state_67890 HTTP/1.1\r
            Host: 127.0.0.1:53682\r
            User-Agent: Mozilla/5.0\r
            \r

            """

            let result = NetworkFrameworkCallbackServer.parse(request: request)

            #expect(result?.code == "test_code_12345")
            #expect(result?.state == "test_state_67890")
        }

        @Test("Parse request with URL-encoded parameters")
        func parseRequestWithURLEncodedParameters() {
            let request = """
            GET /callback?code=abc%2B123&state=xyz%2F456 HTTP/1.1\r
            Host: 127.0.0.1:53682\r
            \r

            """

            let result = NetworkFrameworkCallbackServer.parse(request: request)

            #expect(result?.code == "abc+123")
            #expect(result?.state == "xyz/456")
        }

        @Test("Parse request with parameters in different order")
        func parseRequestWithParametersInDifferentOrder() {
            let request = """
            GET /callback?state=state_first&code=code_second HTTP/1.1\r
            Host: 127.0.0.1:53682\r
            \r

            """

            let result = NetworkFrameworkCallbackServer.parse(request: request)

            #expect(result?.code == "code_second")
            #expect(result?.state == "state_first")
        }

        @Test("Parse request with additional query parameters")
        func parseRequestWithAdditionalQueryParameters() {
            let request = """
            GET /callback?code=my_code&state=my_state&extra=ignored HTTP/1.1\r
            Host: 127.0.0.1:53682\r
            \r

            """

            let result = NetworkFrameworkCallbackServer.parse(request: request)

            #expect(result?.code == "my_code")
            #expect(result?.state == "my_state")
        }

        @Test("Parse returns nil for malformed request")
        func parseReturnsNilForMalformedRequest() {
            let request = "Not a valid HTTP request"

            let result = NetworkFrameworkCallbackServer.parse(request: request)

            #expect(result == nil)
        }

        @Test("Parse returns empty strings for missing parameters")
        func parseReturnsEmptyStringsForMissingParameters() {
            let request = """
            GET /callback?other=value HTTP/1.1\r
            Host: 127.0.0.1:53682\r
            \r

            """

            let result = NetworkFrameworkCallbackServer.parse(request: request)

            #expect(result?.code == "")
            #expect(result?.state == "")
        }

        @Test("Stop cleans up server resources")
        func stopCleansUpServerResources() throws {
            let server = NetworkFrameworkCallbackServer(port: 53683)

            _ = try server.start()
            server.stop()

            // Should be able to start again on same port
            _ = try server.start()
            server.stop()
        }

        @Test("Can create servers on different ports")
        func canCreateServersOnDifferentPorts() throws {
            let server1 = NetworkFrameworkCallbackServer(port: 53684)
            let server2 = NetworkFrameworkCallbackServer(port: 53685)

            let url1 = try server1.start()
            let url2 = try server2.start()

            #expect(url1.port == 53684)
            #expect(url2.port == 53685)

            server1.stop()
            server2.stop()
        }

        @Test("Default port is 53682")
        func defaultPortIs53682() throws {
            let server = NetworkFrameworkCallbackServer()

            let url = try server.start()

            #expect(url.port == 53682)

            server.stop()
        }
    }
    #endif

    // MARK: - Protocol Conformance Tests

    @Suite("Protocol Conformance")
    struct ProtocolConformanceTests {

        @Test("MockCallbackServer conforms to OAuthCallbackServer")
        func mockConformsToProtocol() async {
            let _: any OAuthCallbackServer = MockCallbackServer()
            // Test passes if it compiles
        }

        #if os(macOS)
        @Test("NetworkFrameworkCallbackServer conforms to OAuthCallbackServer")
        @MainActor
        func networkFrameworkConformsToProtocol() {
            let _: any OAuthCallbackServer = NetworkFrameworkCallbackServer()
            // Test passes if it compiles
        }
        #endif

        @Test("Can use protocol type for dependency injection")
        func protocolDependencyInjection() async throws {
            let server: any OAuthCallbackServer = MockCallbackServer()

            await (server as! MockCallbackServer).configureMock(code: "test", state: "test")
            let url = try await server.start()
            #expect(url.absoluteString.contains("callback"))

            let result = try await server.waitForCallback(timeout: 1.0)
            #expect(result.code == "test")

            await server.stop()
        }
    }

    // MARK: - Integration-style Tests

    @Suite("Integration")
    struct IntegrationTests {

        @Test("Complete OAuth callback flow with mock server")
        func completeOAuthCallbackFlowWithMock() async throws {
            let server = MockCallbackServer()
            let expectedCode = TestFixtures.authCode
            let expectedState = TestFixtures.stateParameter

            // Configure mock response
            await server.configureMock(code: expectedCode, state: expectedState)

            // Start server
            let callbackURL = try await server.start()
            #expect(callbackURL.absoluteString.contains("callback"))

            // Simulate receiving callback
            let result = try await server.waitForCallback(timeout: 5.0)

            // Verify results
            #expect(result.code == expectedCode)
            #expect(result.state == expectedState)

            // Clean up
            await server.stop()
        }
    }
}
