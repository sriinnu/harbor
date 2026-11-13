import Foundation
import Synchronization

/// Lightweight GitHub client using REST plus a minimal GraphQL enrichment step.
public actor GitHubClient {
    public private(set) var apiHost: URL = .init(string: "https://api.github.com")!

    private let tokenStore = TokenStore()
    private var tokenProvider: (@Sendable () async throws -> OAuthTokens?)?
    let graphQL = GraphQLClient()
    private let diag = DiagnosticsLogger.shared
    private let requestRunner = GitHubRequestRunner()
    lazy var restAPI = GitHubRestAPI(
        apiHost: { [weak self] in await self?.apiHost ?? URL(string: "https://api.github.com")! },
        tokenProvider: { [weak self] in
            guard let self else { throw URLError(.userAuthenticationRequired) }
            return try await self.validAccessToken()
        },
        requestRunner: requestRunner,
        diag: diag
    )
    private let inflightRepoDetails = InflightCoalescer<String, Repository>()
    private var repoDetailCoordinator: RepoDetailCoordinator {
        RepoDetailCoordinator(restAPI: restAPI, graphQL: graphQL)
    }

    public init() {}

    // MARK: - Config

    /// REST and GraphQL move together before this returns, so no request after it can pair the
    /// new host's token with the old host.
    public func setAPIHost(_ host: URL) async {
        do {
            let trusted = try self.trusted(host)
            self.apiHost = trusted
            await self.graphQL.setEndpoint(apiHost: trusted)
            Task { await self.diag.message("API host set to \(trusted.absoluteString)") }
        } catch {
            Task { await self.diag.message("Rejected API host \(host) (must be https with hostname)") }
        }
    }

    private func trusted(_ host: URL) throws -> URL {
        guard host.scheme?.lowercased() == "https" else { throw GitHubAPIError.invalidHost }
        guard host.host != nil else { throw GitHubAPIError.invalidHost }
        return host
    }

    public func setTokenProvider(_ provider: @Sendable @escaping () async throws -> OAuthTokens?) {
        self.tokenProvider = provider
        Task {
            await self.graphQL.setTokenProvider {
                guard let tokens = try await provider() else { throw URLError(.userAuthenticationRequired) }
                return tokens.accessToken
            }
        }
    }

    /// The later of the REST and GraphQL limit resets, or nil when neither is limited.
    /// Account changed: drop the previous account's rate-limit blocks so the new one starts free.
    public func resetAccountScope() async {
        await self.requestRunner.resetAccountScope()
        await self.graphQL.resetAccountScope()
    }

    /// Points GitHub last reported left on the GraphQL budget; nil before any answer, and 0 while limited.
    public func graphQLPointsRemaining(now: Date = Date()) async -> Int? {
        if await self.graphQL.rateLimitReset(now: now) != nil { return 0 }
        return await self.graphQL.rateLimitSnapshot()?.remaining
    }

    public func rateLimitReset(now: Date = Date()) async -> Date? {
        let rest = await self.requestRunner.rateLimitReset(now: now)
        let graphQL = await self.graphQL.rateLimitReset(now: now)
        return [rest, graphQL].compactMap { $0 }.max()
    }

    public func rateLimitMessage(now: Date = Date()) async -> String? {
        let rest = await self.requestRunner.rateLimitReset(now: now)
        let graphQL = await self.graphQL.rateLimitReset(now: now)
        if let graphQL, rest.map({ graphQL > $0 }) ?? true { return await self.graphQL.rateLimitMessage(now: now) }
        return await self.requestRunner.rateLimitMessage(now: now)
    }

    // MARK: - High level fetchers

    public func defaultRepositories(limit: Int, for _: String) async throws -> [Repository] {
        let items = try await self.restAPI.userReposSorted(limit: max(limit, 10))
        let listed = items.prefix(limit).map { Repository.from(item: $0) }
        let results = Mutex<[String: Repository]>([:])
        await self.enrich(Array(listed)) { batch in
            results.withLock { map in for repo in batch { map[repo.fullName] = repo } }
        }
        let enriched = results.withLock { $0 }
        return listed.map { enriched[$0.fullName] ?? $0 }
    }

    /// Every repository the signed-in user works in (owned, collaborated on, any organisation they belong to) plus the pinned ones outside that set, newest push first.
    /// Counts are not known yet: pass the result to `enrich` to fill them in. The `/user/repos` pages come first; any pinned repo they lack is fetched by name, side by side.
    /// Every repository comes back with `pullCountsKnown == false`: the list carries no PR
    /// count, so a zero there must never read as "no pull requests".
    public func listRepositories(limit: Int?, pinned: [String] = []) async throws -> [Repository] {
        try await self.restAPI.userReposIncludingPinned(limit: limit, pinned: pinned).map { item in
            var repo = Repository.from(item: item)
            repo.pullCountsKnown = false
            return repo
        }
    }

    /// Fills open pull request, issue and security counts, CI state, latest release and latest
    /// commit for `repos` with batched GraphQL: `maxPerQuery` repositories per request, a few
    /// requests in flight at once. `onBatch` is called as each request lands, so a caller can
    /// show results while the rest are still coming. A failed batch, and any repository GitHub
    /// left out of an answer, comes back flagged with the reason and with unknown counts and CI.
    public func enrich(
        _ repos: [Repository],
        maxConcurrent: Int = 10,
        onBatch: @Sendable ([Repository]) async -> Void
    ) async {
        let graphQL = self.graphQL
        await Self.enrich(repos, maxConcurrent: maxConcurrent, fetch: { try await graphQL.repoBatch($0) }, onBatch: onBatch)
    }

    /// `enrich` with the batch request passed in, so tests can answer it.
    static func enrich(
        _ repos: [Repository],
        maxConcurrent: Int = 10,
        fetch: @escaping @Sendable ([RepoRef]) async throws -> [RepoRef: RepoSnapshot],
        onBatch: @Sendable ([Repository]) async -> Void
    ) async {
        let groups = GitHubRepoBatch.chunks(repos.map { RepoRef(owner: $0.owner, name: $0.name) })
        let byName = Dictionary(repos.map { ($0.fullName, $0) }, uniquingKeysWith: { first, _ in first })
        await withTaskGroup(of: [Repository].self) { group in
            var next = 0
            func launch() {
                guard next < groups.count else { return }
                let refs = groups[next]
                next += 1
                group.addTask {
                    do {
                        let snapshots = try await fetch(refs)
                        return refs.compactMap { ref in
                            guard let repo = byName[ref.fullName] else { return nil }
                            guard let snapshot = snapshots[ref] else {
                                return repo.markedUnavailable(error: GitHubRepoBatch.missingMessage(for: ref), rateLimitedUntil: nil)
                            }
                            return repo.applying(snapshot)
                        }
                    } catch {
                        var accumulator = RepoErrorAccumulator()
                        accumulator.absorb(error)
                        return refs.compactMap { ref in
                            byName[ref.fullName]?.markedUnavailable(error: accumulator.message, rateLimitedUntil: accumulator.rateLimit)
                        }
                    }
                }
            }
            for _ in 0 ..< max(1, min(maxConcurrent, groups.count)) { launch() }
            while let batch = await group.next() {
                await onBatch(batch)
                launch()
            }
        }
    }

    /// The list with counts, all at once (for the CLI). The app uses `listRepositories` + `enrich`.
    public func activityRepositories(limit: Int?) async throws -> [Repository] {
        let listed = try await self.listRepositories(limit: limit)
        let results = Mutex<[String: Repository]>([:])
        await self.enrich(listed) { batch in
            results.withLock { map in for repo in batch { map[repo.fullName] = repo } }
        }
        let enriched = results.withLock { $0 }
        return listed.map { enriched[$0.fullName] ?? $0 }
    }

    /// The detail-only data (activity feed, run count, traffic, secret and code scanning) for a
    /// repository the list already knows. Called when its detail opens, never for the whole list.
    /// `includeAlertCounts: false` leaves the secret and code-scanning counts to the caller:
    /// the repo health card reads them itself, so reading them here too would ask GitHub twice.
    public func loadDetails(for repository: Repository, includeAlertCounts: Bool = true) async -> Repository {
        await self.repoDetailCoordinator.loadDetails(for: repository, includeAlertCounts: includeAlertCounts)
    }

    public func userActivityEvents(
        username: String,
        scope: GlobalActivityScope,
        limit: Int
    ) async throws -> [ActivityEvent] {
        let events = try await self.restAPI.userEvents(username: username, scope: scope)
        let mapped = events.compactMap { $0.activityEventFromRepo() }
        return Array(mapped.prefix(max(limit, 0)))
    }

    public func userCommitEvents(
        username: String,
        scope: GlobalActivityScope,
        limit: Int
    ) async throws -> [RepoCommitSummary] {
        let events = try await self.restAPI.userEvents(username: username, scope: scope)
        let commits = events.flatMap { $0.commitSummaries() }
        return Array(commits.prefix(max(limit, 0)))
    }

    /// Latest release (including prereleases). Returns `nil` if the repo has no releases.
    public func latestRelease(owner: String, name: String) async throws -> Release? {
        do {
            return try await self.restAPI.latestReleaseAny(owner: owner, name: name)
        } catch let error as URLError where error.code == .fileDoesNotExist {
            return nil
        }
    }

    public func fullRepository(owner: String, name: String) async throws -> Repository {
        let key = "\(owner.lowercased())/\(name.lowercased())"
        let coordinator = self.repoDetailCoordinator
        return try await self.inflightRepoDetails.run(key: key) {
            try await coordinator.fullRepository(owner: owner, name: name)
        }
    }

    public func currentUser() async throws -> UserIdentity {
        let user = try await self.restAPI.fetchCurrentUser()
        var components = URLComponents()
        components.scheme = self.apiHost.scheme ?? "https"
        let rawHost = self.apiHost.host ?? "github.com"
        components.host = rawHost == "api.github.com" ? "github.com" : rawHost
        let hostURL = components.url ?? URL(string: "https://github.com")!
        return UserIdentity(username: user.login, host: hostURL)
    }

    public func searchRepositories(matching query: String) async throws -> [Repository] {
        let items = try await self.restAPI.searchRepositories(matching: query)
        return items.map { Repository.from(item: $0) }
    }

    public func diagnostics() async -> DiagnosticsSummary {
        let requestDiagnostics = await self.requestRunner.diagnosticsSnapshot()
        return await DiagnosticsSummary(
            apiHost: self.apiHost,
            rateLimitReset: requestDiagnostics.rateLimitReset,
            lastRateLimitError: requestDiagnostics.lastRateLimitError,
            backoffEntries: requestDiagnostics.backoffEntries,
            restRateLimit: requestDiagnostics.restRateLimit,
            graphQLRateLimit: self.graphQL.rateLimitSnapshot()
        )
    }

    /// Recent repositories for the authenticated user, sorted by activity.
    public func recentRepositories(limit: Int = 8) async throws -> [Repository] {
        let items = try await self.restAPI.userReposSorted(limit: limit)
        return items.map { Repository.from(item: $0) }
    }

    /// Contribution heatmap for a user (year view), used to render the header without fetching remote images.
    public func userContributionHeatmap(login: String) async throws -> [HeatmapCell] {
        try await self.graphQL.userContributionHeatmap(login: login)
    }

    /// Per-year contribution totals and their split by kind, for every year the account has
    /// activity. One year is the most a single contributions query returns.
    public func userContributionYears(login: String) async throws -> [ContributionYear] {
        try await self.graphQL.userContributionYears(login: login)
    }

    /// Up to `max` of the user's repositories for autocomplete. Asks GitHub every time.
    public func prefetchedRepositories(
        max: Int = RepoListLimits.maxRepositoriesToPrefetch
    ) async throws -> [Repository] {
        let items = try await self.restAPI.userReposPaginated(limit: max)
        return items.map { Repository.from(item: $0) }
    }

    /// One repo's commits per day for the last 52 weeks (GitHub's `stats/commit_activity`).
    /// Throws `serviceUnavailable` while GitHub is still computing the stats (HTTP 202).
    public func repoCommitActivity(owner: String, name: String) async throws -> [HeatmapCell] {
        try await self.restAPI.commitHeatmap(owner: owner, name: name)
    }

    public func recentPullRequests(owner: String, name: String, limit: Int = 20) async throws -> [RepoPullRequestSummary] {
        try await self.restAPI.recentPullRequests(owner: owner, name: name, limit: limit)
    }

    public func recentIssues(owner: String, name: String, limit: Int = 20) async throws -> [RepoIssueSummary] {
        try await self.restAPI.recentIssues(owner: owner, name: name, limit: limit)
    }

    public func recentReleases(owner: String, name: String, limit: Int = 20) async throws -> [RepoReleaseSummary] {
        try await self.restAPI.recentReleases(owner: owner, name: name, limit: limit)
    }

    public func recentWorkflowRuns(owner: String, name: String, limit: Int = 20) async throws -> [RepoWorkflowRunSummary] {
        try await self.restAPI.recentWorkflowRuns(owner: owner, name: name, limit: limit)
    }

    public func recentCommits(owner: String, name: String, limit: Int = 20) async throws -> RepoCommitList {
        try await self.restAPI.recentCommits(owner: owner, name: name, limit: limit)
    }

    public func recentDiscussions(owner: String, name: String, limit: Int = 20) async throws -> [RepoDiscussionSummary] {
        try await self.restAPI.recentDiscussions(owner: owner, name: name, limit: limit)
    }

    public func recentTags(owner: String, name: String, limit: Int = 20) async throws -> [RepoTagSummary] {
        try await self.restAPI.recentTags(owner: owner, name: name, limit: limit)
    }

    public func recentBranches(owner: String, name: String, limit: Int = 20) async throws -> [RepoBranchSummary] {
        try await self.restAPI.recentBranches(owner: owner, name: name, limit: limit)
    }

    public func topContributors(owner: String, name: String, limit: Int = 20) async throws -> [RepoContributorSummary] {
        try await self.restAPI.topContributors(owner: owner, name: name, limit: limit)
    }

    // MARK: - Internal helpers

    private func validAccessToken() async throws -> String {
        if let provider = tokenProvider, let tokens = try await provider() { return tokens.accessToken }
        if let token = try tokenStore.load()?.accessToken { return token }
        throw URLError(.userAuthenticationRequired)
    }
}

public struct DiagnosticsSummary: Sendable {
    public let apiHost: URL
    public let rateLimitReset: Date?
    public let lastRateLimitError: String?
    public let backoffEntries: Int
    public let restRateLimit: RateLimitSnapshot?
    public let graphQLRateLimit: RateLimitSnapshot?

    public static let empty = DiagnosticsSummary(
        apiHost: URL(string: "https://api.github.com")!,
        rateLimitReset: nil,
        lastRateLimitError: nil,
        backoffEntries: 0,
        restRateLimit: nil,
        graphQLRateLimit: nil
    )
}
