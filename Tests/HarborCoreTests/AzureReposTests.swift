import Foundation
@testable import HarborCore
import Testing

/// Azure DevOps repositories beside GitHub's: one identity across providers, one listing
/// request per organization, and one provider failing never blanking the other. The PAT is a
/// made-up string; nothing here reaches the network or the Keychain.
struct AzureReposTests {
    private static let pat = "azure-test-pat-0002"

    private func github(_ owner: String, _ name: String, pushedAt: Date? = nil) -> Repository {
        Repository(
            id: "\(owner)/\(name)", name: name, owner: owner, sortOrder: nil, error: nil, rateLimitedUntil: nil,
            ciStatus: .unknown, openIssues: 0, openPulls: 0, pushedAt: pushedAt, latestRelease: nil, latestActivity: nil,
            traffic: nil, heatmap: []
        )
    }

    private func azure(_ org: String, _ project: String, _ name: String, disabled: Bool = false) -> Repository {
        let item = AzureDevOpsRepository(
            id: "guid-\(name)", name: name, url: nil, project: .init(id: "p-\(project)", name: project),
            defaultBranch: "refs/heads/main", size: nil, remoteUrl: nil, sshUrl: nil,
            webUrl: "https://dev.azure.com/\(org)/\(project)/_git/\(name)", isDisabled: disabled
        )
        return AzureRepoLister.repository(from: item, host: "dev.azure.com", organization: org)!
    }

    // MARK: Identity

    @Test
    func legacyGitHubPinsReadBackByteIdentical() {
        let stored = ["Octo/Repo", "sriinnu/harbor", "a.b/c-d_e"]
        #expect(stored.map { RepoKey($0)?.string } == stored)
        #expect(RepoKey.githubOnly(stored) == stored)
        #expect(self.github("Octo", "Repo").fullName == "Octo/Repo")
        #expect(self.github("Octo", "Repo").key == .github(owner: "Octo", name: "Repo"))
    }

    @Test
    func anAzureKeyRoundTripsAndIsNeverAGitHubName() {
        let repo = self.azure("acme", "Web", "site")
        #expect(repo.fullName == "azure:dev.azure.com/acme/Web/site")
        #expect(RepoKey(repo.fullName) == .azure(host: "dev.azure.com", organization: "acme", project: "Web", name: "site"))
        #expect(repo.displayName == "Web/site")
        #expect(RepoKey.isAzure(repo.fullName))
        #expect(RepoKey.isAzure("acme/site") == false)
    }

    @Test
    func onlyGitHubPinsAreHandedToGitHub() {
        let pins = ["octo/one", "azure:dev.azure.com/acme/Web/site", "junk", "octo/two"]
        #expect(RepoKey.githubOnly(pins) == ["octo/one", "octo/two"])
    }

    /// The real pinned-repo path: the Azure pin never becomes a `/repos/…` request.
    @Test
    func anAzurePinNeverReachesGitHubsPinnedFetch() async throws {
        let host = "azure-pin.stub.test"
        StubURLProtocol.register(host: host) { seen in
            switch seen.path {
            case "/user/repos": .init(body: "[]")
            case "/repos/octo/extra": .init(body: #"""
                {"id":7,"name":"extra","full_name":"octo/extra","fork":false,"archived":false,
                 "open_issues_count":0,"stargazers_count":0,"forks_count":0,"pushed_at":null,"owner":{"login":"octo"}}
                """#)
            default: .init(status: 404)
            }
        }
        let rest = GitHubRestAPI(
            apiHost: { URL(string: "https://\(host)")! },
            tokenProvider: { "tok" },
            requestRunner: GitHubRequestRunner(session: StubURLProtocol.session()),
            diag: .shared
        )
        let pins = RepoKey.githubOnly(["azure:dev.azure.com/acme/Web/site", "octo/extra"])
        let listed = try await rest.userReposIncludingPinned(limit: nil, pinned: pins)
        #expect(listed.map(\.fullName) == ["octo/extra"])
        #expect(StubURLProtocol.requests(host: host).map(\.path) == ["/user/repos", "/repos/octo/extra"])
    }

    @Test
    func sameNamedGitHubAndAzureReposBothSurvive() {
        let gh = self.github("acme", "site")
        let az = self.azure("acme", "Web", "site")
        #expect(RepoListSources.combine(github: [gh], azure: [az]).map(\.fullName) == ["acme/site", "azure:dev.azure.com/acme/Web/site"])
        #expect(RepoListSources.combine(github: [gh], azure: [az, az]).count == 2)
        let picked = RepoAutocompleteScoring.suggestions(mine: [gh, az], public: [gh], query: "site", limit: 10)
        #expect(picked.map(\.fullName) == ["acme/site", "azure:dev.azure.com/acme/Web/site"])
    }

    // MARK: Lister

    @Test
    func theListerAsksOnceForTheWholeOrganization() async throws {
        let host = "ado-list.stub.test"
        let items = (1...250).map { index in
            #"{"id":"g\#(index)","name":"repo\#(index)","project":{"id":"p1","name":"Web"},"defaultBranch":"refs/heads/main","webUrl":"https://dev.azure.com/acme/Web/_git/repo\#(index)","isDisabled":\#(index == 2)}"#
        }
        let body = #"{"count":250,"value":["# + items.joined(separator: ",") + "]}"
        StubURLProtocol.register(host: host) { seen in
            seen.path == "/acme/_apis/git/repositories" ? .init(body: body) : .init(status: 404)
        }
        let lister = AzureRepoLister(host: URL(string: "https://\(host)")!, session: StubURLProtocol.session())
        let repos = try await lister.repositories(organization: "acme", pat: Self.pat)

        let basic = "Basic " + Data(":\(Self.pat)".utf8).base64EncodedString()
        #expect(StubURLProtocol.requests(host: host) == [.init(path: "/acme/_apis/git/repositories", query: "api-version=7.0", authorization: basic)])
        #expect(repos.count == 250)
        let first = try #require(repos.first)
        #expect(first.fullName == "azure:\(host)/acme/Web/repo1")
        #expect(first.azure == AzureRepoInfo(
            host: host, organization: "acme", project: "Web", id: "g1", defaultBranch: "refs/heads/main",
            webURL: URL(string: "https://dev.azure.com/acme/Web/_git/repo1"), isDisabled: false
        ))
        #expect(first.azure?.branchName == "main")
        #expect(first.pullCountsKnown == false)
        #expect(repos[1].azure?.isDisabled == true)
        #expect(repos[1].isArchived == true)
    }

    @Test
    func anExpiredTokenOrTheSignInPageSaysSignInExpired() async {
        for (index, status) in [401, 203].enumerated() {
            let host = "ado-expired-\(index).stub.test"
            StubURLProtocol.register(host: host) { _ in .init(status: status, body: "<html>sign in</html>") }
            let lister = AzureRepoLister(host: URL(string: "https://\(host)")!, session: StubURLProtocol.session())
            do {
                _ = try await lister.repositories(organization: "acme", pat: Self.pat)
                Issue.record("status \(status) listed repositories")
            } catch {
                #expect(error.localizedDescription == "Azure DevOps sign-in for acme has expired. Reconnect it in Settings → Accounts.")
            }
        }
    }

    // MARK: Search

    @Test
    func ownReposFromBothProvidersRankAbovePublicOnes() {
        let mine = [self.github("octo", "site"), self.azure("acme", "Web", "site")]
        let others = [self.github("astral", "site")]
        let picked = RepoAutocompleteScoring.suggestions(mine: mine, public: others, query: "site", limit: 10)
        #expect(picked.map(\.fullName) == ["azure:dev.azure.com/acme/Web/site", "octo/site", "astral/site"])
    }

    @Test
    func aProjectQualifiedQueryFindsTheAzureRepoFirst() {
        let target = self.azure("acme", "Web", "site")
        let other = self.azure("acme", "Docs", "site")
        #expect(RepoAutocompleteScoring.score(repo: target, query: "web/site") == 1000)
        #expect(RepoAutocompleteScoring.score(repo: target, query: "acme/web/site") == 1000)
        let picked = RepoAutocompleteScoring.suggestions(mine: [other, target], public: [], query: "Web/site", limit: 10)
        #expect(picked.map(\.fullName) == ["azure:dev.azure.com/acme/Web/site", "azure:dev.azure.com/acme/Docs/site"])
    }

    @Test
    func anAzureFailureKeepsGitHubsRepos() async {
        struct Down: Error {}
        let gh = self.github("octo", "site")
        let az = self.azure("acme", "Web", "site")
        let whenAzureFails = await RepoListSources.gather(github: { [gh] }, azure: { throw Down() })
        #expect(whenAzureFails.map(\.fullName) == ["octo/site"])
        let whenGitHubFails = await RepoListSources.gather(github: { throw Down() }, azure: { [az] })
        #expect(whenGitHubFails.map(\.fullName) == ["azure:dev.azure.com/acme/Web/site"])
    }

    // MARK: List

    /// Azure's listing has no push date. The year cutoff on the full list must not read that
    /// as "too old" and drop every Azure row; GitHub rows past the cutoff still go.
    @Test
    func undatedAzureRowsPassTheAgeCutoff() {
        let now = Date(timeIntervalSince1970: 1_800_000_000)
        let old = self.github("octo", "old", pushedAt: now.addingTimeInterval(-400 * 86400))
        let az = self.azure("acme", "Web", "site")
        let query = RepositoryQuery(scope: .all, ageCutoff: now.addingTimeInterval(-365 * 86400))
        #expect(RepositoryPipeline.apply([old, az], query: query).map(\.fullName) == ["azure:dev.azure.com/acme/Web/site"])
    }
}

/// The review's fixes: keys that survive the row's rebuilds, no GitHub request for anything
/// that isn't a GitHub owner/name, typed text that can't become a wrong pin.
struct AzureReposReviewTests {
    private func azure(_ org: String = "acme", _ project: String = "Web", _ name: String = "site", host: String = "dev.azure.com") -> Repository {
        let item = AzureDevOpsRepository(
            id: "guid-\(name)", name: name, url: nil, project: .init(id: "p-\(project)", name: project),
            defaultBranch: "refs/heads/main", size: nil, remoteUrl: nil, sshUrl: nil,
            webUrl: "https://dev.azure.com/\(org)/\(project)/_git/\(name)", isDisabled: false
        )
        return AzureRepoLister.repository(from: item, host: host, organization: org)!
    }

    private func github(_ owner: String, _ name: String) -> Repository {
        Repository(
            id: "\(owner)/\(name)", name: name, owner: owner, sortOrder: nil, error: nil, rateLimitedUntil: nil,
            ciStatus: .unknown, openIssues: 0, openPulls: 0, latestRelease: nil, latestActivity: nil, traffic: nil, heatmap: []
        )
    }

    // #6
    @Test
    func anAzureRowKeepsItsKeyThroughReorderAndListUpdates() {
        let row = self.azure()
        #expect(row.withOrder(3).fullName == "azure:dev.azure.com/acme/Web/site")
        #expect(row.withOrder(3).azure == row.azure)
        #expect(row.updatingListFields(from: row.withOrder(1)).fullName == "azure:dev.azure.com/acme/Web/site")
        #expect(row.updatingListFields(from: row).key == row.key)
    }

    @Test
    func enrichNeverAsksGitHubAboutAnAzureRow() async {
        final class Calls: @unchecked Sendable {
            let lock = NSLock()
            var refs: [[String]] = []
        }
        let calls = Calls()
        await GitHubClient.enrich([self.azure(), self.github("octo", "site")], fetch: { refs in
            calls.lock.withLock { calls.refs.append(refs.map(\.fullName)) }
            return [:]
        }, onBatch: { _ in })
        #expect(calls.lock.withLock { calls.refs } == [["octo/site"]])
    }

    @Test
    func aRepoDetailForANonGitHubNameSendsNothing() async throws {
        let host = "azure-detail.stub.test"
        StubURLProtocol.register(host: host) { _ in .init(status: 404) }
        let rest = GitHubRestAPI(
            apiHost: { URL(string: "https://\(host)")! },
            tokenProvider: { "tok" },
            requestRunner: GitHubRequestRunner(session: StubURLProtocol.session()),
            diag: .shared
        )
        let graphQL = GraphQLClient(session: StubURLProtocol.session())
        await graphQL.setEndpoint(apiHost: URL(string: "https://\(host)")!)
        let coordinator = RepoDetailCoordinator(restAPI: rest, graphQL: graphQL)
        let repo = try await coordinator.fullRepository(owner: "azure:dev.azure.com", name: "acme/Web/site")
        #expect(repo.error == "Not a GitHub repository.")
        #expect(StubURLProtocol.requests(host: host) == [])
    }

    // #9
    @Test
    func theOrganizationIsLowercasedInTheKeyAndProjectCaseIsKept() {
        let row = self.azure("Acme", "Web", "Site", host: "Dev.Azure.com")
        #expect(row.fullName == "azure:dev.azure.com/acme/Web/Site")
        #expect(RepoKey("azure:Dev.Azure.com/ACME/Web/Site")?.string == "azure:dev.azure.com/acme/Web/Site")
        #expect(RepoKey(row.fullName)?.string == row.fullName)
    }

    // #11
    @Test
    func onlyAnHTMLBodyCountsAsTheSignInPage() async {
        for (index, body) in ["  \n<!DOCTYPE html><html>sign in</html>", "{\"value\": 3"].enumerated() {
            let host = "ado-body-\(index).stub.test"
            StubURLProtocol.register(host: host) { _ in .init(body: body) }
            let lister = AzureRepoLister(host: URL(string: "https://\(host)")!, session: StubURLProtocol.session())
            do {
                _ = try await lister.repositories(organization: "acme", pat: "azure-test-pat-0003")
                Issue.record("body \(index) listed repositories")
            } catch {
                #expect(error as? AzureRepoListError == (index == 0
                    ? .signInExpired(organization: "acme")
                    : .failed(organization: "acme", message: "Unexpected response.")))
            }
        }
    }

    // #10
    @Test
    func twoClonesOfOneRepoDontTrapTheLocalIndex() {
        func clone(_ path: String) -> LocalRepoStatus {
            LocalRepoStatus(
                path: URL(fileURLWithPath: path), name: "site", fullName: "octo/site", branch: "main",
                isClean: true, aheadCount: nil, behindCount: nil, syncState: .behind
            )
        }
        let index = LocalRepoIndex(statuses: [clone("/tmp/a/site"), clone("/tmp/b/site")])
        #expect(index.byFullName["octo/site"]?.path.path == "/tmp/a/site")
    }

    // #5
    @Test
    func typedTextResolvesToTheRepoItNamesOrIsRefused() {
        let az = self.azure()
        let gh = self.github("Octo", "Site")
        let shown = [gh, az]
        #expect(RepoAutocompleteScoring.resolveTyped("web/site", among: shown) == "azure:dev.azure.com/acme/Web/site")
        #expect(RepoAutocompleteScoring.resolveTyped("acme/Web/site", among: shown) == "azure:dev.azure.com/acme/Web/site")
        #expect(RepoAutocompleteScoring.resolveTyped("octo/site", among: shown) == "Octo/Site")
        #expect(RepoAutocompleteScoring.resolveTyped("someone/else", among: shown) == "someone/else")
        #expect(RepoAutocompleteScoring.resolveTyped("acme/Docs/site", among: shown) == nil)
        #expect(RepoAutocompleteScoring.resolveTyped("site", among: shown) == nil)
        #expect(RepoAutocompleteScoring.resolveTyped("azure:Dev.Azure.com/Acme/Docs/x", among: []) == "azure:dev.azure.com/acme/Docs/x")
    }

    // Nit: empty query
    @Test
    func anEmptyQueryShowsBothProvidersInTurn() {
        let mine = [self.github("o", "a"), self.github("o", "b"), self.github("o", "c"), self.azure("acme", "Web", "x"), self.azure("acme", "Web", "y")]
        #expect(RepoAutocompleteScoring.suggestions(mine: mine, public: [], query: "", limit: 4).map(\.fullName)
            == ["o/a", "azure:dev.azure.com/acme/Web/x", "o/b", "azure:dev.azure.com/acme/Web/y"])
    }
}
