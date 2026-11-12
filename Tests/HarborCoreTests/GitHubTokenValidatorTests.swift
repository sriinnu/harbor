import Foundation
@testable import HarborCore
import Testing

/// Personal access token sign-in: `GET /user` decides, and nothing is stored unless it passes.
/// The token below is a made-up string; the in-memory storage stands in for the Keychain.
struct GitHubTokenValidatorTests {
    private static let token = "ghp_TESTONLYnotarealtoken0123456789"

    private func validator(_ host: String, _ route: @escaping StubURLProtocol.Route) -> GitHubTokenValidator {
        StubURLProtocol.register(host: host, route: route)
        return GitHubTokenValidator(apiHost: URL(string: "https://\(host)")!) { request in
            try await StubURLProtocol.session().data(for: request)
        }
    }

    private func failure(_ validator: GitHubTokenValidator, _ token: String = GitHubTokenValidatorTests.token) async -> GitHubTokenError? {
        do {
            _ = try await validator.validate(token)
            return nil
        } catch { return error as? GitHubTokenError }
    }

    @Test
    func classicTokenWithBothScopesIsAccepted() async throws {
        let host = "pat-ok.stub.test"
        let validator = self.validator(host) { _ in
            .init(headers: ["X-OAuth-Scopes": "repo, read:org, gist"], body: #"{"login":"octo"}"#)
        }
        let check = try await validator.validate("  \(Self.token)\n")
        #expect(check == GitHubTokenCheck(login: "octo", scopes: ["repo", "read:org", "gist"]))
        #expect(StubURLProtocol.requests(host: host) == [
            .init(path: "/user", query: nil, authorization: "Bearer \(Self.token)")
        ])
    }

    @Test
    func adminOrgSatisfiesReadOrg() async throws {
        let validator = self.validator("pat-admin.stub.test") { _ in
            .init(headers: ["X-OAuth-Scopes": "admin:org,repo"], body: #"{"login":"octo"}"#)
        }
        #expect(try await validator.validate(Self.token).login == "octo")
    }

    @Test
    func missingScopesAreNamed() async {
        let noRepo = self.validator("pat-norepo.stub.test") { _ in
            .init(headers: ["X-OAuth-Scopes": "read:org"], body: #"{"login":"octo"}"#)
        }
        #expect(await self.failure(noRepo) == .missingScopes(["repo"]))
        let none = self.validator("pat-none.stub.test") { _ in
            .init(headers: ["X-OAuth-Scopes": ""], body: #"{"login":"octo"}"#)
        }
        let error = await self.failure(none)
        #expect(error == .missingScopes(["repo", "read:org"]))
        #expect(error?.errorDescription == "This token is missing the repo and read:org scopes. Edit the token on GitHub, tick them, and paste it again.")
    }

    @Test
    func fineGrainedTokenHasNoScopeHeaderAndIsAccepted() async throws {
        let validator = self.validator("pat-fine.stub.test") { _ in .init(body: #"{"login":"octo"}"#) }
        let check = try await validator.validate("github_pat_TESTONLY")
        #expect(check == GitHubTokenCheck(login: "octo", scopes: nil))
        #expect(check.isFineGrained)
    }

    @Test
    func statusesMapToHonestErrors() async {
        func make(_ host: String, _ reply: StubURLProtocol.Reply) -> GitHubTokenValidator {
            self.validator(host) { _ in reply }
        }
        #expect(await self.failure(make("pat-401.stub.test", .init(status: 401))) == .rejected)
        #expect(await self.failure(make("pat-sso.stub.test", .init(status: 403, headers: ["X-GitHub-SSO": "required; url=https://x"]))) == .needsSSO)
        #expect(await self.failure(make("pat-rl.stub.test", .init(status: 403, headers: ["X-RateLimit-Remaining": "0"]))) == .rateLimited)
        #expect(await self.failure(make("pat-403.stub.test", .init(status: 403, body: "{}"))) == .forbidden)
        #expect(await self.failure(make("pat-500.stub.test", .init(status: 500))) == .unexpected(500))
        #expect(await self.failure(make("pat-junk.stub.test", .init(body: "not json"))) == .unexpected(200))
    }

    @Test
    func networkFailureIsReportedWithoutEchoingAnything() async {
        let validator = GitHubTokenValidator(apiHost: URL(string: "https://offline.stub.test")!) { _ in
            throw URLError(.notConnectedToInternet)
        }
        let error = await self.failure(validator)
        #expect(error == .network("No internet connection."))
    }

    @Test
    func badPastesAreRefusedBeforeAnyRequest() async {
        let host = "pat-badpaste.stub.test"
        let validator = self.validator(host) { _ in .init(body: #"{"login":"octo"}"#) }
        #expect(await self.failure(validator, "   ") == .empty)
        #expect(await self.failure(validator, "ghp_two words") == .malformed)
        #expect(await self.failure(validator, "ghp_line\nbreak") == .malformed)
        #expect(StubURLProtocol.requests(host: host).isEmpty)
    }

    @Test
    func theKeychainShapeKeepsTheKindAndReadsOldItems() throws {
        let secrets = InMemorySecretStore()
        let storage = KeychainTokenStorage(service: "com.sriinnu.harbor.auth", store: secrets)
        try storage.save(tokens: OAuthTokens(accessToken: Self.token, refreshToken: "", expiresAt: nil, kind: .personalAccessToken))
        #expect(try storage.load()?.kind == .personalAccessToken)
        #expect(try secrets.accounts(service: "com.sriinnu.harbor.auth") == ["default"])

        let old = Data(#"{"accessToken":"a","refreshToken":"b"}"#.utf8)
        #expect(try JSONDecoder().decode(OAuthTokens.self, from: old) == OAuthTokens(accessToken: "a", refreshToken: "b", expiresAt: nil))

        storage.clear()
        #expect(try storage.load() == nil)
    }

    @Test
    func noMessageThisFlowProducesContainsTheToken() async {
        let cases: [GitHubTokenError] = [
            .empty, .malformed, .rejected, .missingScopes(["repo"]), .needsSSO, .forbidden, .rateLimited,
            .network("offline"), .unexpected(500)
        ]
        for error in cases {
            #expect(error.localizedDescription.contains(Self.token) == false)
            #expect("\(error)".contains(Self.token) == false)
        }
        // An unknown transport error whose own text carries the token is not repeated.
        struct Leaky: Error, LocalizedError { var errorDescription: String? { "boom \(GitHubTokenValidatorTests.token)" } }
        let leaky = GitHubTokenValidator(apiHost: URL(string: "https://leaky.stub.test")!) { _ in throw Leaky() }
        let error = await self.failure(leaky)
        #expect(error == .network("network error."))
        #expect("\(error!)".contains(Self.token) == false)
        // The URL (which logs may show) never holds the token.
        let host = "pat-url.stub.test"
        let ok = self.validator(host) { _ in .init(headers: ["X-OAuth-Scopes": "repo,read:org"], body: #"{"login":"octo"}"#) }
        _ = try? await ok.validate(Self.token)
        let seen = StubURLProtocol.requests(host: host)
        #expect(seen.map(\.path) == ["/user"])
        #expect(seen.allSatisfy { ($0.query ?? "").contains(Self.token) == false })
    }
}
