import Foundation
@testable import HarborCore
import Testing

/// A GET that GitHub refuses with a secondary limit is a rate limit, not "not visible".
struct SecondaryLimitTests {
    private enum Outcome: Equatable {
        case ok
        case rateLimited
        case badStatus(Int)
        case other
    }

    private func outcome(_ body: () async throws -> Void) async -> Outcome {
        do {
            try await body()
            return .ok
        } catch GitHubAPIError.rateLimited { return .rateLimited
        } catch let GitHubAPIError.badStatus(code, _) { return .badStatus(code)
        } catch { return .other }
    }

    private func get(_ runner: GitHubRequestRunner, _ host: String, _ path: String = "/repos/o/r/x") async -> Outcome {
        await self.outcome { _ = try await runner.get(url: URL(string: "https://\(host)\(path)")!, token: "t") }
    }

    @Test
    func aForbiddenGetWithRetryAfterIsRateLimitedAndBlocksTheNextRequest() async {
        let host = "secondary-retry.stub.test"
        StubURLProtocol.register(host: host) { _ in
            .init(status: 403, headers: ["Retry-After": "30", "X-RateLimit-Remaining": "4000"], body: "{}")
        }
        let runner = GitHubRequestRunner(session: StubURLProtocol.session())
        #expect(await self.get(runner, host) == .rateLimited)
        #expect(StubURLProtocol.requests(host: host).count == 1)
        // Blocked: the next one fails fast without being sent.
        #expect(await self.get(runner, host, "/repos/o/r/y") == .rateLimited)
        #expect(StubURLProtocol.requests(host: host).count == 1)
        #expect(await runner.rateLimitReset() != nil)
    }

    @Test
    func aForbiddenGetWhoseBodyNamesTheRateLimitIsRateLimited() async {
        let host = "secondary-body.stub.test"
        StubURLProtocol.register(host: host) { _ in
            .init(status: 403, headers: ["X-RateLimit-Remaining": "4000"], body: #"{"message":"You have exceeded a secondary rate limit."}"#)
        }
        let runner = GitHubRequestRunner(session: StubURLProtocol.session())
        #expect(await self.get(runner, host) == .rateLimited)
    }

    @Test
    func aPlainForbiddenGetWithQuotaLeftStaysAPermissionFailure() async {
        let host = "secondary-plain.stub.test"
        StubURLProtocol.register(host: host) { _ in
            .init(status: 403, headers: ["X-RateLimit-Remaining": "4000"], body: #"{"message":"Resource not accessible by integration"}"#)
        }
        let runner = GitHubRequestRunner(session: StubURLProtocol.session())
        #expect(await self.get(runner, host) == .badStatus(403))
        #expect(await runner.rateLimitReset() == nil)
    }

    @Test
    func a429IsRateLimited() async {
        let host = "secondary-429.stub.test"
        StubURLProtocol.register(host: host) { _ in .init(status: 429, headers: ["X-RateLimit-Remaining": "4000"]) }
        let runner = GitHubRequestRunner(session: StubURLProtocol.session())
        #expect(await self.get(runner, host) == .rateLimited)
    }

    @Test
    func anAccountChangeClearsTheBlock() async {
        let host = "secondary-reset.stub.test"
        StubURLProtocol.register(host: host) { seen in
            seen.path.hasSuffix("/limited")
                ? .init(status: 403, headers: ["Retry-After": "300"])
                : .init(body: "ok")
        }
        let runner = GitHubRequestRunner(session: StubURLProtocol.session())
        #expect(await self.get(runner, host, "/limited") == .rateLimited)
        #expect(await self.get(runner, host, "/fine") == .rateLimited)
        await runner.resetAccountScope()
        #expect(await self.get(runner, host, "/fine") == .ok)
        #expect(await runner.rateLimitReset() == nil)
    }

    /// The per-URL cooldown a 202 sets is keyed by URL alone: a new account asking for the same
    /// URL must not be told "Cooling down" because of the old one.
    @Test
    func anAccountChangeClearsThePerUrlCooldownToo() async {
        let host = "secondary-cooldown.stub.test"
        StubURLProtocol.register(host: host) { _ in
            StubURLProtocol.requests(host: host).count == 1 ? .init(status: 202, headers: ["Retry-After": "300"]) : .init(body: "ok")
        }
        let runner = GitHubRequestRunner(session: StubURLProtocol.session())
        #expect(await self.get(runner, host, "/repos/o/r/stats") == .other)
        // Same URL, still cooling down: refused without a request.
        #expect(await self.get(runner, host, "/repos/o/r/stats") == .other)
        #expect(StubURLProtocol.requests(host: host).count == 1)
        await runner.resetAccountScope()
        #expect(await self.get(runner, host, "/repos/o/r/stats") == .ok)
        #expect(StubURLProtocol.requests(host: host).count == 2)
    }

    @Test
    func deleteGoesThroughTheInjectedSession() async {
        let host = "secondary-delete.stub.test"
        StubURLProtocol.register(host: host) { seen in
            seen.path.hasSuffix("/limited") ? .init(status: 403, headers: ["Retry-After": "30"]) : .init(status: 204)
        }
        let runner = GitHubRequestRunner(session: StubURLProtocol.session())
        #expect(await self.outcome { try await runner.delete(url: URL(string: "https://\(host)/repos/o/r/actions/runs/1")!, token: "t") } == .ok)
        #expect(StubURLProtocol.requests(host: host).count == 1)
        #expect(await self.outcome { try await runner.delete(url: URL(string: "https://\(host)/limited")!, token: "t") } == .rateLimited)
    }

    @Test
    func graphQLBlockIsClearedOnAccountChange() async {
        let host = "secondary-graphql.stub.test"
        StubURLProtocol.register(host: host) { _ in .init(status: 403, headers: ["Retry-After": "300"], body: "{}") }
        let client = GraphQLClient(session: StubURLProtocol.session())
        await client.setEndpoint(apiHost: URL(string: "https://\(host)")!)
        await client.setTokenProvider { "t" }
        _ = try? await client.execute(query: "query { viewer { login } }", variables: [:], label: "probe")
        #expect(await client.rateLimitReset() != nil)
        await client.resetAccountScope()
        #expect(await client.rateLimitReset() == nil)
    }
}
