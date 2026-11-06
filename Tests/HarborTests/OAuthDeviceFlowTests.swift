import Foundation
@testable import HarborCore
import Testing

/// Scripted HTTP responses, consumed in order; records every request body.
private final class ScriptedHTTP: @unchecked Sendable {
    private let lock = NSLock()
    private var responses: [(Int, String)]
    private(set) var bodies: [String] = []
    private(set) var urls: [String] = []

    init(_ responses: [(Int, String)]) { self.responses = responses }

    var requestCount: Int { self.lock.withLock { self.bodies.count } }

    func handle(_ request: URLRequest) throws -> (Data, URLResponse) {
        try self.lock.withLock {
            self.bodies.append(request.httpBody.flatMap { String(data: $0, encoding: .utf8) } ?? "")
            self.urls.append(request.url?.absoluteString ?? "")
            guard self.responses.isEmpty == false else { throw URLError(.resourceUnavailable) }
            let (status, body) = self.responses.removeFirst()
            let response = HTTPURLResponse(url: request.url!, statusCode: status, httpVersion: nil, headerFields: nil)!
            return (Data(body.utf8), response)
        }
    }
}

private final class SleepLog: @unchecked Sendable {
    private let lock = NSLock()
    private(set) var intervals: [TimeInterval] = []
    func record(_ seconds: TimeInterval) { self.lock.withLock { self.intervals.append(seconds) } }
}

private let host = URL(string: "https://github.com")!
private let codeResponse = """
{"device_code":"dev-123","user_code":"WDJB-MJHT","verification_uri":"https://github.com/login/device","expires_in":900,"interval":5}
"""

private func makeFlow(_ http: ScriptedHTTP, storage: InMemoryTokenStorage = InMemoryTokenStorage(), sleeps: SleepLog = SleepLog(), now: @escaping @Sendable () -> Date = { Date() }) -> OAuthDeviceFlow {
    OAuthDeviceFlow(
        tokenStorage: storage,
        dataProvider: { try http.handle($0) },
        sleep: { sleeps.record($0) },
        now: now
    )
}

struct OAuthDeviceFlowTests {
    @Test
    func startRequestsCodeWithClientIDOnly() async throws {
        let http = ScriptedHTTP([(200, codeResponse)])
        let auth = try await makeFlow(http).start(clientID: "cid", host: host)

        #expect(auth.userCode == "WDJB-MJHT")
        #expect(auth.deviceCode == "dev-123")
        #expect(auth.verificationURL.absoluteString == "https://github.com/login/device")
        #expect(auth.pollInterval == 5)
        #expect(http.urls == ["https://github.com/login/device/code"])
        #expect(http.bodies[0].contains("client_id=cid"))
        #expect(http.bodies[0].contains("client_secret") == false)
    }

    @Test
    func startSurfacesDisabledDeviceFlow() async throws {
        let http = ScriptedHTTP([(200, #"{"error":"device_flow_disabled","error_description":"Device Flow must be explicitly enabled"}"#)])
        await #expect(throws: DeviceFlowError.disabled) {
            _ = try await makeFlow(http).start(clientID: "cid", host: host)
        }
    }

    @Test
    func pollWaitsThroughPendingAndSlowDownThenStoresNonExpiringToken() async throws {
        let http = ScriptedHTTP([
            (200, codeResponse),
            (200, #"{"error":"authorization_pending"}"#),
            (200, #"{"error":"slow_down","interval":10}"#),
            (200, #"{"access_token":"gho_test","token_type":"bearer","scope":"repo"}"#)
        ])
        let storage = InMemoryTokenStorage()
        let sleeps = SleepLog()
        let flow = makeFlow(http, storage: storage, sleeps: sleeps)
        let auth = try await flow.start(clientID: "cid", host: host)
        let tokens = try await flow.poll(auth, clientID: "cid", host: host)

        #expect(tokens.accessToken == "gho_test")
        // GitHub sent no expires_in: the token must not get an invented expiry.
        #expect(tokens.expiresAt == nil)
        #expect(sleeps.intervals == [5, 5, 10])
        #expect(http.bodies[1].contains("grant_type=urn%3Aietf%3Aparams%3Aoauth%3Agrant-type%3Adevice_code"))
        #expect(http.bodies[1].contains("device_code=dev-123"))
        #expect(http.bodies.allSatisfy { $0.contains("client_secret") == false })
        #expect(try storage.load()?.accessToken == "gho_test")
        #expect(try storage.loadClientCredentials() == OAuthClientCredentials(clientID: "cid", clientSecret: ""))
    }

    @Test
    func pollStopsWhenUserDenies() async throws {
        let http = ScriptedHTTP([(200, codeResponse), (200, #"{"error":"access_denied"}"#)])
        let flow = makeFlow(http)
        let auth = try await flow.start(clientID: "cid", host: host)
        await #expect(throws: DeviceFlowError.denied) {
            try await flow.poll(auth, clientID: "cid", host: host)
        }
    }

    @Test
    func pollStopsAtExpiryWithoutAnotherRequest() async throws {
        let http = ScriptedHTTP([(200, codeResponse)])
        let start = Date()
        let auth = try await makeFlow(http, now: { start }).start(clientID: "cid", host: host)
        // By the time polling wakes up, the 900s code has expired.
        let later = makeFlow(http, now: { start.addingTimeInterval(901) })
        await #expect(throws: DeviceFlowError.expired) {
            try await later.poll(auth, clientID: "cid", host: host)
        }
        #expect(http.requestCount == 1) // only the code request
    }

    @Test
    func pollHonoursCancellation() async throws {
        let http = ScriptedHTTP([(200, codeResponse)])
        let flow = OAuthDeviceFlow(
            tokenStorage: InMemoryTokenStorage(),
            dataProvider: { try http.handle($0) },
            sleep: { try await Task.sleep(nanoseconds: UInt64($0 * 1_000_000_000)) }
        )
        let auth = try await flow.start(clientID: "cid", host: host)
        let task = Task { try await flow.poll(auth, clientID: "cid", host: host) }
        task.cancel()
        await #expect(throws: CancellationError.self) { try await task.value }
        #expect(http.requestCount == 1)
    }
}

struct OAuthTokenRefresherNoSecretTests {
    @Test
    func nonExpiringTokenIsReturnedWithoutNetwork() async throws {
        let storage = InMemoryTokenStorage()
        try storage.save(tokens: OAuthTokens(accessToken: "gho_x", refreshToken: "", expiresAt: nil))
        let http = ScriptedHTTP([])
        let refresher = OAuthTokenRefresher(tokenStorage: storage) { try http.handle($0) }

        #expect(try await refresher.refreshIfNeeded(host: host)?.accessToken == "gho_x")
        #expect(http.requestCount == 0)
    }

    @Test
    func expiredTokenWithoutSecretIsNotRefreshedWithABundledSecret() async throws {
        let storage = InMemoryTokenStorage()
        try storage.save(tokens: OAuthTokens(accessToken: "gho_x", refreshToken: "r1", expiresAt: .distantPast))
        try storage.save(clientCredentials: OAuthClientCredentials(clientID: "cid", clientSecret: ""))
        let http = ScriptedHTTP([])
        let refresher = OAuthTokenRefresher(tokenStorage: storage) { try http.handle($0) }

        #expect(try await refresher.refreshIfNeeded(host: host)?.accessToken == "gho_x")
        #expect(http.requestCount == 0)
    }
}

@MainActor
private final class RecordingLoopbackServer: LoopbackServing {
    private(set) var stopCount = 0
    func start() throws -> URL { URL(string: "http://127.0.0.1:12345/callback")! }
    func waitForCallback(timeout _: TimeInterval) async throws -> (code: String, state: String) { ("code-1", "state-1") }
    func stop() { self.stopCount += 1 }
}

struct OAuthLoginFlowHardeningTests {
    @MainActor
    private func login(responding status: Int, _ body: String, server: RecordingLoopbackServer) async throws -> OAuthTokens {
        let http = ScriptedHTTP([(status, body)])
        let flow = OAuthLoginFlow(
            tokenStorage: InMemoryTokenStorage(),
            openURL: { _ in },
            dataProvider: { try http.handle($0) },
            makeLoopbackServer: { _ in server },
            stateProvider: { "state-1" }
        )
        return try await flow.login(clientID: "cid", clientSecret: "own-secret", host: host, loopbackPort: 12345, timeout: 1)
    }

    @Test @MainActor
    func undecodableSuccessBodyNeverLeaksTheTokenIntoTheError() async throws {
        let server = RecordingLoopbackServer()
        // Missing token_type/scope makes decoding fail while the body still holds a token.
        do {
            _ = try await self.login(responding: 200, #"{"access_token":"LEAK-1234"}"#, server: server)
            Issue.record("Expected a decode failure")
        } catch {
            #expect(error.localizedDescription.contains("LEAK-1234") == false)
            #expect("\(error)".contains("LEAK-1234") == false)
        }
        #expect(server.stopCount == 1) // the port is released on failure too
    }

    @Test @MainActor
    func exchangeErrorKeepsOnlyTheOAuthErrorFields() async throws {
        let server = RecordingLoopbackServer()
        do {
            _ = try await self.login(responding: 200, #"{"error":"bad_verification_code","error_description":"The code passed is incorrect or expired."}"#, server: server)
            Issue.record("Expected an exchange failure")
        } catch {
            #expect(error.localizedDescription.contains("bad_verification_code"))
        }
    }

    @Test @MainActor
    func tokenWithoutExpiresInHasNoInventedExpiry() async throws {
        let server = RecordingLoopbackServer()
        let tokens = try await self.login(responding: 200, #"{"access_token":"gho_ok","token_type":"bearer","scope":"repo"}"#, server: server)
        #expect(tokens.expiresAt == nil)
        #expect(server.stopCount == 1)
    }
}
