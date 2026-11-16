import Foundation

/// Loads one repository's detail: what only its detail view shows (activity feed, run count,
/// traffic, secret and code scanning). Nothing is stored; each call asks GitHub again, and the
/// independent requests run concurrently.
struct RepoDetailCoordinator {
    let restAPI: GitHubRestAPI
    let graphQL: GraphQLClient

    /// A repository by name: its REST record and the batched snapshot together, then the detail.
    func fullRepository(owner: String, name: String) async throws -> Repository {
        let restAPI = self.restAPI
        let graphQL = self.graphQL
        async let item = Self.capture { try await restAPI.repoDetails(owner: owner, name: name) }
        async let snapshots = Self.capture { try await graphQL.repoBatch([RepoRef(owner: owner, name: name)]) }
        let details: RepoItem
        switch await item {
        case let .success(value): details = value
        case let .failure(error):
            var accumulator = RepoErrorAccumulator()
            accumulator.absorb(error)
            return Repository.placeholder(owner: owner, name: name, error: accumulator.message, rateLimitedUntil: accumulator.rateLimit)
        }
        var repository = Repository.from(item: details)
        var accumulator = RepoErrorAccumulator()
        switch await snapshots {
        case let .success(map):
            if let snapshot = map[RepoRef(owner: details.owner.login, name: details.name)] {
                repository = repository.applying(snapshot)
            }
        case let .failure(error):
            accumulator.absorb(error)
            repository.pullCountsKnown = false
        }
        repository.error = accumulator.message
        repository.rateLimitedUntil = accumulator.rateLimit
        return await self.loadDetails(for: repository)
    }

    /// Adds the detail-only data to a repository the list already knows. With
    /// `includeAlertCounts` false the secret-scanning and code-scanning lookups are left out
    /// (the repo health card runs them), so one detail open asks GitHub for them once.
    func loadDetails(for repository: Repository, includeAlertCounts: Bool = true) async -> Repository {
        let owner = repository.owner
        let name = repository.name
        let restAPI = self.restAPI
        async let activityResult = Self.capture { try await restAPI.recentActivity(owner: owner, name: name, limit: 10) }
        async let ciResult = Self.capture { try await restAPI.ciStatus(owner: owner, name: name) }
        async let trafficResult = Self.capture { try await restAPI.trafficStats(owner: owner, name: name) }
        async let secretsResult = Self.capture {
            includeAlertCounts ? try await restAPI.openAlertCount(owner: owner, name: name, kind: "secret-scanning") : nil
        }
        async let codeResult = Self.capture {
            includeAlertCounts ? try await restAPI.openAlertCount(owner: owner, name: name, kind: "code-scanning") : nil
        }

        var updated = repository
        var accumulator = RepoErrorAccumulator()

        switch await activityResult {
        case let .success(snapshot):
            updated.activityEvents = snapshot.events
            if let latest = snapshot.latest ?? snapshot.events.first { updated.latestActivity = latest }
        case let .failure(error): accumulator.absorb(error)
        }
        switch await ciResult {
        case let .success(details):
            updated.ciRunCount = details.runCount
            // The batch's check rollup owns CI. The newest run of one workflow only fills in a
            // repo whose rollup was unknown, so opening a detail can't turn a failing row green.
            if repository.ciStatus == .unknown, details.status != .unknown { updated.ciStatus = details.status }
        case let .failure(error): accumulator.absorb(error)
        }
        switch await trafficResult {
        case let .success(traffic): updated.traffic = traffic
        case let .failure(error): accumulator.absorb(error)
        }
        var secrets: Int?
        var code: Int?
        switch await secretsResult {
        case let .success(count): secrets = count
        case let .failure(error): accumulator.absorb(error)
        }
        switch await codeResult {
        case let .success(count): code = count
        case let .failure(error): accumulator.absorb(error)
        }
        if includeAlertCounts {
            updated.security = RepoSecurity(dependabot: repository.security?.dependabot, secretLeaks: secrets, codeScanning: code)
        }

        if let message = accumulator.message {
            updated.error = message
            updated.rateLimitedUntil = accumulator.rateLimit
        } else if repository.pullCountsKnown {
            // A clean detail load ends an earlier detail error. A failed batch's error stays: the
            // batch, not this load, owns it.
            updated.error = nil
            updated.rateLimitedUntil = nil
        }
        return updated
    }

    private static func capture<T: Sendable>(_ work: @escaping @Sendable () async throws -> T) async -> Result<T, Error> {
        do { return try await .success(work()) } catch { return .failure(error) }
    }
}
