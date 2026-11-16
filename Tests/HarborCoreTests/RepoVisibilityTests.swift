import Foundation
@testable import HarborCore
import Testing

/// The repo list shows every repo the user works in, and pinned repos outside it still load.
struct RepoVisibilityTests {
    private func api(host: String) -> GitHubRestAPI {
        GitHubRestAPI(
            apiHost: { URL(string: "https://\(host)")! },
            tokenProvider: { "test-token" },
            requestRunner: GitHubRequestRunner(session: StubURLProtocol.session()),
            diag: .shared
        )
    }

    private func repoJSON(_ fullName: String, id: Int) -> String {
        let parts = fullName.split(separator: "/")
        return """
        {"id":\(id),"name":"\(parts[1])","full_name":"\(fullName)","fork":false,"archived":false,
        "open_issues_count":0,"stargazers_count":0,"forks_count":0,"pushed_at":null,"owner":{"login":"\(parts[0])"}}
        """
    }

    @Test
    func theListingAsksForOwnedCollaboratorAndOrgMemberRepos() async throws {
        let host = "visibility-listing.stub.test"
        let web = self.repoJSON("acme/web", id: 2)
        StubURLProtocol.register(host: host) { seen in
            seen.path == "/user/repos" ? .init(body: "[\(web)]") : .init(status: 404)
        }
        let repos = try await self.api(host: host).userReposPaginated(limit: nil)
        #expect(repos.map(\.fullName) == ["acme/web"])
        let seen = StubURLProtocol.requests(host: host)
        #expect(seen.map(\.path) == ["/user/repos"])
        #expect(seen.map(\.query) == [
            "sort=pushed&direction=desc&affiliation=owner,collaborator,organization_member&per_page=100&page=1"
        ])
    }

    @Test
    func aPinnedRepoOutsideTheListingIsFetchedByNameAndAnUnreadableOneIsSkipped() async throws {
        let host = "visibility-pinned.stub.test"
        let mine = self.repoJSON("me/app", id: 1)
        let pinned = self.repoJSON("outside/tool", id: 3)
        StubURLProtocol.register(host: host) { seen in
            switch seen.path {
            case "/user/repos": .init(body: "[\(mine)]")
            case "/repos/outside/tool": .init(body: pinned)
            default: .init(status: 404, body: #"{"message":"Not Found"}"#)
            }
        }
        let repos = try await self.api(host: host).userReposIncludingPinned(
            limit: nil,
            // `ME/app` is already listed (case differs), `gone/x` is unreadable, `junk` is not a name.
            pinned: ["outside/tool", "ME/app", "gone/x", "junk"]
        )
        #expect(repos.map(\.fullName) == ["me/app", "outside/tool"])
        // One listing request, then exactly the missing pinned repos: no org lookup, no /user call.
        #expect(StubURLProtocol.requests(host: host).map(\.path).sorted() == ["/repos/gone/x", "/repos/outside/tool", "/user/repos"])
    }

    @Test
    func withNothingPinnedOnlyTheListingIsRequested() async throws {
        let host = "visibility-nopins.stub.test"
        StubURLProtocol.register(host: host) { _ in .init(body: "[]") }
        let repos = try await self.api(host: host).userReposIncludingPinned(limit: nil, pinned: [])
        #expect(repos.isEmpty)
        #expect(StubURLProtocol.requests(host: host).map(\.path) == ["/user/repos"])
    }
}
