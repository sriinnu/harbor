import Foundation
@testable import HarborCore
import Synchronization
import Testing

/// What a failed, limited or partial answer from GitHub must look like: never calm, never a
/// number that was not read, never another account's answer.
struct HonestDataTests {
    private let now = Date(timeIntervalSince1970: 1_800_000_000)

    private func repo(_ name: String = "a", error: String? = nil, known: Bool = true, ci: CIStatus = .passing) -> Repository {
        Repository(
            id: name, name: name, owner: "o", sortOrder: nil, error: error, rateLimitedUntil: nil, ciStatus: ci,
            openIssues: 9, openPulls: 4, latestRelease: nil, latestActivity: nil, traffic: nil, heatmap: [],
            pullCountsKnown: known
        )
    }

    private func rest(host: String, token: String = "tok", _ route: @escaping StubURLProtocol.Route) -> GitHubRestAPI {
        StubURLProtocol.register(host: host, route: route)
        return GitHubRestAPI(
            apiHost: { URL(string: "https://\(host)")! },
            tokenProvider: { token },
            requestRunner: GitHubRequestRunner(session: StubURLProtocol.session()),
            diag: .shared
        )
    }

    /// A 403 that carries quota, so it is a permission refusal and not a rate limit.
    private static let forbidden = StubURLProtocol.Reply(status: 403, headers: ["X-RateLimit-Remaining": "4000"])

    // MARK: #7 GraphQL rate limits

    private func limit(status: Int, retryAfter: String? = nil, remaining: String? = nil, reset: String? = nil, body: Data) -> Date? {
        GraphQLRateLimit.resetDate(
            GraphQLRateLimit.Answer(status: status, retryAfter: retryAfter, remaining: remaining, reset: reset, body: body), now: self.now
        )
    }

    @Test
    func rateLimit_primaryIs200WithRateLimitedErrorAndNullData() {
        let body = Data(#"{"data":null,"errors":[{"type":"RATE_LIMITED","message":"API rate limit exceeded"}]}"#.utf8)
        let reset = self.now.addingTimeInterval(600)
        let until = self.limit(status: 200, remaining: "0", reset: String(Int(reset.timeIntervalSince1970)), body: body)
        #expect(until == reset)
    }

    @Test
    func rateLimit_partialErrorsWithDataAreNotALimit() {
        let body = Data(#"{"data":{"r0":null},"errors":[{"type":"RATE_LIMITED","message":"x"}]}"#.utf8)
        #expect(self.limit(status: 200, body: body) == nil)
        let missing = Data(#"{"data":{"r0":null},"errors":[{"type":"NOT_FOUND"}]}"#.utf8)
        #expect(self.limit(status: 200, body: missing) == nil)
    }

    @Test
    func rateLimit_secondaryIs403WithRetryAfterOr429_butPlain403IsNot() {
        let empty = Data()
        #expect(self.limit(status: 403, retryAfter: "30", remaining: "4000", body: empty)
            == self.now.addingTimeInterval(30))
        #expect(self.limit(status: 429, body: empty)
            == self.now.addingTimeInterval(GraphQLRateLimit.defaultWait))
        let named = Data(#"{"message":"You have exceeded a secondary rate limit."}"#.utf8)
        #expect(self.limit(status: 403, remaining: "4000", body: named)
            == self.now.addingTimeInterval(GraphQLRateLimit.defaultWait))
        #expect(self.limit(status: 403, remaining: "4000", body: empty) == nil)
    }

    private func graphQL(host: String, _ route: @escaping StubURLProtocol.Route) async -> GraphQLClient {
        StubURLProtocol.register(host: host, route: route)
        let client = GraphQLClient(session: StubURLProtocol.session())
        await client.setEndpoint(apiHost: URL(string: "https://\(host)")!)
        await client.setTokenProvider { "tok" }
        return client
    }

    @Test
    func graphQLClient_limitedResponseThrowsRateLimited_andStopsSending() async throws {
        let reset = Date().addingTimeInterval(900).timeIntervalSince1970.rounded(.down)
        let client = await self.graphQL(host: "limit.stub.test") { _ in
            StubURLProtocol.Reply(
                headers: ["X-RateLimit-Reset": String(Int(reset))],
                body: #"{"data":null,"errors":[{"type":"RATE_LIMITED","message":"API rate limit exceeded"}]}"#
            )
        }
        let repos = [RepoRef(owner: "o", name: "a")]
        do {
            _ = try await client.repoBatch(repos)
            Issue.record("expected a rate limit")
        } catch let GitHubAPIError.rateLimited(until, _) {
            #expect(until == Date(timeIntervalSince1970: reset))
        }
        // The second batch and a PR-pane style call fail fast: nothing goes on the wire.
        await #expect(throws: GitHubAPIError.self) { try await client.repoBatch(repos) }
        await #expect(throws: GitHubAPIError.self) { _ = try await client.execute(query: "query { viewer { login } }", variables: [:], label: "Probe") }
        #expect(StubURLProtocol.requests(host: "limit.stub.test").count == 1)
        #expect(await client.rateLimitReset() == Date(timeIntervalSince1970: reset))
    }

    @Test
    func graphQLClient_secondaryLimit403BlocksUntilRetryAfter() async {
        let client = await self.graphQL(host: "secondary.stub.test") { _ in
            StubURLProtocol.Reply(status: 403, headers: ["Retry-After": "120"], body: #"{"message":"secondary"}"#)
        }
        await #expect(throws: GitHubAPIError.self) { try await client.repoBatch([RepoRef(owner: "o", name: "a")]) }
        let reset = await client.rateLimitReset()
        #expect(reset != nil)
        #expect(StubURLProtocol.requests(host: "secondary.stub.test").count == 1)
    }

    @Test
    func graphQLClient_permissionRefusalIsNotALimit() async {
        let client = await self.graphQL(host: "perm.stub.test") { _ in Self.forbidden }
        await #expect(throws: GitHubAPIError.self) { try await client.repoBatch([RepoRef(owner: "o", name: "a")]) }
        #expect(await client.rateLimitReset() == nil)
        await #expect(throws: GitHubAPIError.self) { try await client.repoBatch([RepoRef(owner: "o", name: "a")]) }
        #expect(StubURLProtocol.requests(host: "perm.stub.test").count == 2)
    }

    // MARK: #5 repos missing from a batch

    private final class Landed: @unchecked Sendable {
        private let lock = NSLock()
        private var repos: [Repository] = []
        func add(_ batch: [Repository]) { self.lock.withLock { self.repos += batch } }
        var all: [Repository] { self.lock.withLock { self.repos } }
    }

    @Test
    func enrich_flagsARepoGitHubLeftOut_notZeroAndKnown() async {
        let known = self.repo("kept", ci: .failing)
        let gone = self.repo("gone", ci: .passing)
        let snapshot = RepoSnapshot(openPulls: 2, openIssues: 3, ci: .passing, release: nil, dependabot: nil, latestCommit: nil)
        let landed = Landed()
        await GitHubClient.enrich([known, gone], fetch: { refs in
            Dictionary(uniqueKeysWithValues: refs.filter { $0.name == "kept" }.map { ($0, snapshot) })
        }, onBatch: { landed.add($0) })
        let byName = Dictionary(uniqueKeysWithValues: landed.all.map { ($0.name, $0) })
        #expect(byName["kept"]?.pullCountsKnown == true)
        #expect(byName["kept"]?.openPulls == 2)
        #expect(byName["kept"]?.error == nil)
        #expect(byName["gone"]?.pullCountsKnown == false)
        #expect(byName["gone"]?.ciStatus == .unknown)
        #expect(byName["gone"]?.error == "GitHub returned nothing for o/gone; it may need SSO authorization or access was lost.")
    }

    @Test
    func enrich_failedBatchIsFlaggedWithItsLimit_andCIGoesUnknown() async {
        let until = self.now.addingTimeInterval(300)
        let landed = Landed()
        await GitHubClient.enrich([self.repo("a", ci: .passing)], fetch: { _ in
            throw GitHubAPIError.rateLimited(until: until, message: "limited")
        }, onBatch: { landed.add($0) })
        let result = landed.all.first
        #expect(result?.error == "limited")
        #expect(result?.rateLimitedUntil == until)
        #expect(result?.pullCountsKnown == false)
        #expect(result?.ciStatus == .unknown)
    }

    // MARK: #4 error clears, list fields update

    @Test
    func applying_clearsAnEarlierErrorAndLimit() {
        var flagged = self.repo("a", error: "old", known: false, ci: .unknown)
        flagged.rateLimitedUntil = self.now
        let snapshot = RepoSnapshot(openPulls: 1, openIssues: 1, ci: .passing, release: nil, dependabot: nil, latestCommit: nil)
        let healed = flagged.applying(snapshot)
        #expect(healed.error == nil)
        #expect(healed.rateLimitedUntil == nil)
        #expect(healed.pullCountsKnown)
    }

    @Test
    func updatingListFields_takesArchivedForkOrderAndStats_keepsCountsAndDetail() {
        let onScreen = self.repo("a")
        let fresh = Repository(
            id: "a", name: "a", owner: "o", isFork: true, isArchived: true, sortOrder: 3, error: nil, rateLimitedUntil: nil,
            ciStatus: .unknown, openIssues: 77, openPulls: 0, stars: 5, forks: 6, pushedAt: self.now,
            latestRelease: nil, latestActivity: nil, traffic: nil, heatmap: [], pullCountsKnown: false
        )
        let merged = onScreen.updatingListFields(from: fresh)
        #expect(merged.isArchived)
        #expect(merged.isFork)
        #expect(merged.sortOrder == 3)
        #expect(merged.stars == 5)
        #expect(merged.forks == 6)
        #expect(merged.pushedAt == self.now)
        // Counts the batch answered stay until the next batch lands.
        #expect(merged.openIssues == 9)
        #expect(merged.openPulls == 4)
        #expect(merged.ciStatus == .passing)
        // A repo no batch has answered for takes the list's issue count.
        #expect(self.repo("a", known: false).updatingListFields(from: fresh).openIssues == 77)
    }

    @Test
    func applying_aWithheldDependabotTallyClearsTheOldOne_andKeepsTheDetailCounts() {
        var onScreen = self.repo("a")
        onScreen.security = RepoSecurity(
            dependabot: DependabotTally(critical: 2, high: 0, medium: 0, low: 0), secretLeaks: 3, codeScanning: 4
        )
        let withheld = RepoSnapshot(openPulls: 1, openIssues: 1, ci: .passing, release: nil, dependabot: nil, latestCommit: nil)
        let batch = onScreen.applying(withheld)
        #expect(batch.security == RepoSecurity(dependabot: nil, secretLeaks: 3, codeScanning: 4))
        // And the merge onto the on-screen row does not bring the old tally back.
        #expect(onScreen.mergingBatch(batch).security == RepoSecurity(dependabot: nil, secretLeaks: 3, codeScanning: 4))
        // A repo that never had any security data stays without it.
        #expect(self.repo("b").applying(withheld).security == nil)
    }

    // MARK: k detail CI

    @Test
    func detailLoad_neverReplacesTheBatchsCheckRollup() async {
        let host = "ci-batch.stub.test"
        let api = self.rest(host: host) { seen in
            switch seen.path {
            case "/repos/o/r": .init(body: #"{"default_branch":"trunk"}"#)
            case "/repos/o/r/actions/runs":
                .init(body: #"{"total_count":3,"workflow_runs":[{"id":1,"status":"completed","conclusion":"success"}]}"#)
            default: .init(status: 404)
            }
        }
        let coordinator = RepoDetailCoordinator(restAPI: api, graphQL: GraphQLClient(session: StubURLProtocol.session()))
        let failing = await coordinator.loadDetails(for: self.repo("r", ci: .failing), includeAlertCounts: false)
        #expect(failing.ciStatus == .failing)
        #expect(failing.ciRunCount == 3)
        // Only a repo whose rollup was unknown takes the run's answer.
        let unknown = await coordinator.loadDetails(for: self.repo("r", ci: .unknown), includeAlertCounts: false)
        #expect(unknown.ciStatus == .passing)
    }

    @Test
    func detailLoad_asksForTheRunsOfTheReposActualDefaultBranch() async {
        let host = "ci-branch.stub.test"
        let api = self.rest(host: host) { seen in
            switch seen.path {
            case "/repos/o/r": .init(body: #"{"default_branch":"trunk"}"#)
            case "/repos/o/r/actions/runs": .init(body: #"{"total_count":0,"workflow_runs":[]}"#)
            default: .init(status: 404)
            }
        }
        _ = try? await api.ciStatus(owner: "o", name: "r")
        let queries = StubURLProtocol.requests(host: host).filter { $0.path.hasSuffix("/actions/runs") }.map(\.query)
        #expect(queries == [String?.some("per_page=1&branch=trunk")])
    }

    @Test
    func mergingDetails_doesNotOverwriteACheckRollupTheBatchLandedMeanwhile() {
        let base = self.repo("a", known: false, ci: .unknown)
        var detailed = base
        detailed.ciStatus = .passing
        let current = self.repo("a", ci: .failing)
        #expect(current.mergingDetails(detailed, loadedFrom: base).ciStatus == .failing)
        let stillUnknown = self.repo("a", ci: .unknown)
        #expect(stillUnknown.mergingDetails(detailed, loadedFrom: base).ciStatus == .passing)
    }

    // MARK: #18 field ownership

    private func event(_ title: String, at date: Date) -> ActivityEvent {
        ActivityEvent(title: title, actor: "ada", date: date, url: URL(string: "https://example.com/\(title)")!)
    }

    @Test
    func mergingBatch_keepsDetailFieldsLoadedMeanwhile() {
        var current = self.repo("a", known: false, ci: .unknown)
        current.traffic = TrafficStats(uniqueVisitors: 3, uniqueCloners: 1)
        current.ciRunCount = 12
        current.activityEvents = [self.event("feed", at: self.now)]
        current.security = RepoSecurity(dependabot: nil, secretLeaks: 2, codeScanning: 1)
        let tally = DependabotTally(critical: 1, high: 0, medium: 0, low: 0)
        var batch = self.repo("a", ci: .failing)
        batch.openPulls = 8
        batch.security = RepoSecurity(dependabot: tally, secretLeaks: nil, codeScanning: nil)
        let merged = current.mergingBatch(batch)
        #expect(merged.openPulls == 8)
        #expect(merged.ciStatus == .failing)
        #expect(merged.pullCountsKnown)
        #expect(merged.traffic == TrafficStats(uniqueVisitors: 3, uniqueCloners: 1))
        #expect(merged.ciRunCount == 12)
        #expect(merged.activityEvents == [self.event("feed", at: self.now)])
        #expect(merged.security == RepoSecurity(dependabot: tally, secretLeaks: 2, codeScanning: 1))
    }

    @Test
    func mergingDetails_keepsBatchCountsLoadedMeanwhile() {
        let base = self.repo("a", known: false, ci: .unknown)
        var detailed = base
        detailed.traffic = TrafficStats(uniqueVisitors: 9, uniqueCloners: 9)
        detailed.ciRunCount = 40
        detailed.activityEvents = [self.event("feed", at: self.now)]
        detailed.security = RepoSecurity(dependabot: nil, secretLeaks: 5, codeScanning: 6)
        // The batch landed while the detail was loading.
        let current = self.repo("a", ci: .failing)
        let merged = current.mergingDetails(detailed, loadedFrom: base)
        #expect(merged.openPulls == 4)
        #expect(merged.openIssues == 9)
        #expect(merged.ciStatus == .failing)
        #expect(merged.pullCountsKnown)
        #expect(merged.traffic == TrafficStats(uniqueVisitors: 9, uniqueCloners: 9))
        #expect(merged.ciRunCount == 40)
        #expect(merged.security == RepoSecurity(dependabot: nil, secretLeaks: 5, codeScanning: 6))
    }

    @Test
    func mergingDetails_cleanLoadClearsADetailError_butNotAFailedBatchsError() {
        var base = self.repo("a")
        base.error = "detail failed"
        let clean = self.repo("a")
        #expect(base.mergingDetails(clean, loadedFrom: base).error == nil)

        var batchFailed = self.repo("a", error: "batch failed", known: false, ci: .unknown)
        batchFailed.rateLimitedUntil = self.now
        let carried = batchFailed.mergingDetails(batchFailed, loadedFrom: batchFailed)
        #expect(carried.error == "batch failed")
        #expect(carried.rateLimitedUntil == self.now)
    }

    // MARK: #19 totals

    @Test
    func parse_vulnerabilityTotalCountBeatsTheFirstHundred() throws {
        let nodes = (0 ..< 3).map { _ in #"{"securityVulnerability":{"severity":"HIGH"}}"# }.joined(separator: ",")
        let json = """
        {"data":{"r0":{"pullRequests":{"totalCount":0},"issues":{"totalCount":0},"releases":{"nodes":[]},
        "vulnerabilityAlerts":{"totalCount":130,"nodes":[\(nodes)]},"defaultBranchRef":null}}}
        """
        let ref = RepoRef(owner: "o", name: "a")
        let snapshot = try #require(GitHubRepoBatch.parse(Data(json.utf8), repos: [ref])[ref])
        #expect(snapshot.dependabot == DependabotTally(critical: 0, high: 3, medium: 0, low: 127))
        #expect(snapshot.dependabot?.total == 130)
    }

    @Test
    func reviewRequests_issueCountSaysHowManyAreHidden() throws {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let wire = try decoder.decode(ReviewRequestsWire.self, from: Data("""
        {"data":{"search":{"issueCount":23,"nodes":[
          {"number":1,"title":"A","url":null,"updatedAt":null,"isDraft":false,"author":null,"repository":{"nameWithOwner":"o/a"}},
          {}
        ]}}}
        """.utf8))
        let list = wire.list()
        #expect(list.requests.count == 1)
        #expect(list.total == 23)
        #expect(list.hiddenCount == 22)
        #expect(ReviewRequestList(requests: [], total: nil).hiddenCount == 0)
    }

    // MARK: #20 health: needs admin vs couldn't load

    private func secureRoute(code: StubURLProtocol.Reply, secrets: StubURLProtocol.Reply = .init(body: "[]")) -> StubURLProtocol.Route {
        { seen in
            switch seen.path {
            case "/repos/o/r/dependabot/alerts": .init(body: "[]")
            case "/repos/o/r/secret-scanning/alerts": secrets
            case "/repos/o/r/code-scanning/alerts": code
            default: .init(status: 404)
            }
        }
    }

    @Test
    func healthSecurity_aFailedReadIsNotNeedsAdmin() async {
        let api = self.rest(host: "sec500.stub.test", self.secureRoute(code: .init(body: "[]"), secrets: .init(status: 500)))
        await #expect(throws: GitHubAPIError.self) { _ = try await api.healthSecurity(owner: "o", name: "r") }
    }

    @Test
    func healthSecurity_aPermissionRefusalStaysNotVisible() async throws {
        let api = self.rest(host: "sec403.stub.test", self.secureRoute(code: .init(body: "[]"), secrets: Self.forbidden))
        let section = try await api.healthSecurity(owner: "o", name: "r")
        #expect(section.alerts.secretLeaks == nil)
        #expect(section.alerts.codeScanning == 0)
    }

    @Test
    func healthSecurity_codeScanningNotEnabledNeverSaysNeedsAdmin() async throws {
        let missing = self.rest(host: "cs404.stub.test", self.secureRoute(code: .init(status: 404)))
        let a = try await missing.healthSecurity(owner: "o", name: "r")
        #expect(a.codeScanning == .notEnabled)
        #expect(a.codeScanningValue == "Not enabled")

        let forbidden = self.rest(host: "cs403.stub.test", self.secureRoute(code: Self.forbidden))
        let nonAdmin = try await forbidden.healthSecurity(owner: "o", name: "r")
        #expect(nonAdmin.codeScanning == .needsAdmin)
        // An admin who is refused is looking at a repo with the feature off.
        let admin = try await forbidden.healthSecurity(owner: "o", name: "r", isAdmin: true)
        #expect(admin.codeScanning == .notEnabled)
        #expect(admin.codeScanningValue == "Not enabled")
    }

    @Test
    func healthFlow_aFailedPullsReadIsNotAnEmptyHealthyList() async {
        let api = self.rest(host: "flow.stub.test") { seen in
            switch seen.path {
            case "/repos/o/r/pulls": .init(status: 500)
            case "/repos/o/r/actions/runs": .init(body: #"{"workflow_runs":[]}"#)
            default: .init(status: 404)
            }
        }
        let basics = RepoHealthBasics(defaultBranch: "main", isAdmin: true)
        await #expect(throws: GitHubAPIError.self) { _ = try await api.healthFlow(owner: "o", name: "r", basics: basics, release: nil) }
    }

    @Test
    func healthFlow_aFailedRunsReadIsNotAnEmptyHealthyList() async {
        let api = self.rest(host: "flowruns.stub.test") { seen in
            switch seen.path {
            case "/repos/o/r/pulls": .init(body: "[]")
            case "/repos/o/r/actions/runs": .init(status: 502)
            default: .init(status: 404)
            }
        }
        let basics = RepoHealthBasics(defaultBranch: "main", isAdmin: true)
        await #expect(throws: GitHubAPIError.self) { _ = try await api.healthFlow(owner: "o", name: "r", basics: basics, release: nil) }
    }

    // MARK: #21 alert lookups run once per detail open

    @Test
    func detailOpen_asksForSecretAndCodeScanningOnce() async throws {
        let host = "once.stub.test"
        let api = self.rest(host: host) { seen in
            seen.path.hasSuffix("/alerts") ? .init(body: "[]") : .init(status: 404)
        }
        let coordinator = RepoDetailCoordinator(restAPI: api, graphQL: GraphQLClient(session: StubURLProtocol.session()))
        // The app's detail open (alert counts left to the health card) plus the health card.
        _ = await coordinator.loadDetails(for: self.repo("r"), includeAlertCounts: false)
        _ = try await api.healthSecurity(owner: "o", name: "r")
        let alertPaths = StubURLProtocol.requests(host: host).map(\.path).filter { $0.hasSuffix("/alerts") }.sorted()
        #expect(alertPaths == [
            "/repos/o/r/code-scanning/alerts", "/repos/o/r/dependabot/alerts", "/repos/o/r/secret-scanning/alerts"
        ])
    }

    @Test
    func loadDetails_withAlertCountsStillReadsThem() async {
        let host = "counts.stub.test"
        let api = self.rest(host: host) { seen in
            seen.path.hasSuffix("/alerts") ? .init(body: "[]") : .init(status: 404)
        }
        let coordinator = RepoDetailCoordinator(restAPI: api, graphQL: GraphQLClient(session: StubURLProtocol.session()))
        let loaded = await coordinator.loadDetails(for: self.repo("r"))
        #expect(loaded.security == RepoSecurity(dependabot: nil, secretLeaks: 0, codeScanning: 0))
        #expect(StubURLProtocol.requests(host: host).map(\.path).filter { $0.hasSuffix("/alerts") }.sorted()
            == ["/repos/o/r/code-scanning/alerts", "/repos/o/r/secret-scanning/alerts"])
    }

    // MARK: #22 coalescing keeps accounts apart

    @Test
    func runner_twoAccountsAskingTogetherNeverShareAnAnswer() async throws {
        let host = "accounts.stub.test"
        StubURLProtocol.register(host: host) { seen in
            .init(body: seen.authorization ?? "none", delay: 0.3)
        }
        let runner = GitHubRequestRunner(session: StubURLProtocol.session())
        let url = URL(string: "https://\(host)/user/repos")!
        async let first = runner.get(url: url, token: "token-a")
        async let second = runner.get(url: url, token: "token-b")
        let (a, b) = try await (first, second)
        #expect(String(data: a.0, encoding: .utf8) == "Bearer token-a")
        #expect(String(data: b.0, encoding: .utf8) == "Bearer token-b")
        #expect(StubURLProtocol.requests(host: host).count == 2)
    }

    @Test
    func runner_sameAccountStillSharesOneRequest() async throws {
        let host = "sameaccount.stub.test"
        StubURLProtocol.register(host: host) { _ in .init(body: "x", delay: 0.3) }
        let runner = GitHubRequestRunner(session: StubURLProtocol.session())
        let url = URL(string: "https://\(host)/user/repos")!
        async let first = runner.get(url: url, token: "token-a")
        async let second = runner.get(url: url, token: "token-a")
        _ = try await (first, second)
        #expect(StubURLProtocol.requests(host: host).count == 1)
    }

    // MARK: #23 the tally stays bounded

    @Test
    func template_hidesShasBranchesAndWorkflowFileNames() {
        let sha = "0123456789abcdef0123456789abcdef01234567"
        #expect(RequestTally.template(forPath: "/repos/o/r/commits/\(sha)/check-runs") == "/repos/{owner}/{repo}/commits/{x}/check-runs")
        #expect(RequestTally.template(forPath: "/repos/o/r/branches/feature-login/protection") == "/repos/{owner}/{repo}/branches/{x}/protection")
        #expect(RequestTally.template(forPath: "/repos/o/r/actions/workflows/ci.yml/runs") == "/repos/{owner}/{repo}/actions/workflows/{x}/runs")
        #expect(RequestTally.template(forPath: "/repos/o/r/contents/.github/workflows/release.yml")
            == "/repos/{owner}/{repo}/contents/{x}/workflows/{x}")
        #expect(RequestTally.template(forPath: "/repos/o/r/compare/v1.2.0...main") == "/repos/{owner}/{repo}/compare/{x}")
    }

    @Test
    func tally_capsDistinctKeys() async {
        let tally = RequestTally()
        for index in 0 ..< (RequestTally.maxKeys + 10) { await tally.recordGraphQL(label: "label-\(index)") }
        let drained = await tally.drain()
        #expect(drained.graphQL.count == RequestTally.maxKeys + 1)
        #expect(drained.graphQL[RequestTally.overflowKey] == 10)
        #expect(drained.graphQLTotal == RequestTally.maxKeys + 10)
        // A known key keeps counting after the cap.
        for index in 0 ..< (RequestTally.maxKeys + 1) { await tally.recordGraphQL(label: "label-\(index)") }
        await tally.recordGraphQL(label: "label-0")
        #expect(await tally.snapshot().graphQL["label-0"] == 2)
    }
}
