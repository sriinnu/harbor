import Foundation

/// A repository named by owner and name.
struct RepoRef: Hashable, Sendable {
    let owner: String
    let name: String

    var fullName: String { "\(self.owner)/\(self.name)" }
}

/// What one batched GraphQL query learns about a repository: everything the list and the menu
/// show, in one round trip for up to `GitHubRepoBatch.maxPerQuery` repositories.
struct RepoSnapshot: Equatable, Sendable {
    var openPulls: Int
    var openIssues: Int
    var ci: CIStatus
    var release: Release?
    var dependabot: DependabotTally?
    var latestCommit: ActivityEvent?
}

/// Builds and reads the batched repository query: many repositories per request, one alias each.
enum GitHubRepoBatch {
    /// Small groups, many at once: measured faster than 25 per query, because each repository's
    /// check rollup and alert list cost the server time and the groups run in parallel.
    static let maxPerQuery = 6

    /// `query RepoBatch($o0: String!, $n0: String!, …) { r0: repository(owner: $o0, name: $n0) {…} … }`.
    /// Owner and name travel as variables, never spliced into the query text.
    static func query(count: Int) -> String {
        let declarations = (0 ..< count).map { "$o\($0): String!, $n\($0): String!" }.joined(separator: ", ")
        let aliases = (0 ..< count)
            .map { "  r\($0): repository(owner: $o\($0), name: $n\($0)) { ...RepoBatchFields }" }
            .joined(separator: "\n")
        return "query RepoBatch(\(declarations)) {\n\(aliases)\n}\n\(self.fragment)"
    }

    static let fragment = """
    fragment RepoBatchFields on Repository {
      pullRequests(states: OPEN) { totalCount }
      issues(states: OPEN) { totalCount }
      releases(first: 5, orderBy: {field: CREATED_AT, direction: DESC}) {
        nodes { name tagName createdAt publishedAt url isDraft }
      }
      vulnerabilityAlerts(first: 100, states: OPEN) { totalCount nodes { securityVulnerability { severity } } }
      defaultBranchRef {
        target {
          ... on Commit {
            oid
            committedDate
            messageHeadline
            url
            author { name user { login avatarUrl } }
            statusCheckRollup { state }
          }
        }
      }
    }
    """

    static func variables(for repos: [RepoRef]) -> [String: GraphQLVariable] {
        var variables: [String: GraphQLVariable] = [:]
        for (index, repo) in repos.enumerated() {
            variables["o\(index)"] = .string(repo.owner)
            variables["n\(index)"] = .string(repo.name)
        }
        return variables
    }

    /// Splits a repository list into query-sized groups, keeping order.
    static func chunks(_ repos: [RepoRef]) -> [[RepoRef]] {
        stride(from: 0, to: repos.count, by: self.maxPerQuery).map {
            Array(repos[$0 ..< min($0 + self.maxPerQuery, repos.count)])
        }
    }

    /// Reads the response. A repository that came back `null` (not found, no access, an SSO
    /// grant missing) or that does not decode is left out of the result rather than failing the
    /// whole batch; the others still parse. `GitHubClient.enrich` flags every one left out.
    static func parse(_ data: Data, repos: [RepoRef]) throws -> [RepoRef: RepoSnapshot] {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let object = try JSONSerialization.jsonObject(with: data) as? [String: Any]
        guard let payload = object?["data"] as? [String: Any] else { throw URLError(.cannotParseResponse) }
        var out: [RepoRef: RepoSnapshot] = [:]
        for (index, repo) in repos.enumerated() {
            guard let node = payload["r\(index)"] as? [String: Any],
                  let json = try? JSONSerialization.data(withJSONObject: node),
                  let decoded = try? decoder.decode(Node.self, from: json) else { continue }
            out[repo] = decoded.snapshot(for: repo)
        }
        return out
    }

    /// GitHub's check rollup mapped onto Harbor's four CI states.
    static func ciStatus(rollup state: String?) -> CIStatus {
        switch state {
        case "SUCCESS": .passing
        case "FAILURE", "ERROR": .failing
        case "PENDING", "EXPECTED": .pending
        default: .unknown
        }
    }

    // MARK: - Wire models

    private struct Count: Decodable { let totalCount: Int }

    private struct Node: Decodable {
        struct ReleaseNode: Decodable {
            let name: String?
            let tagName: String
            let createdAt: Date?
            let publishedAt: Date?
            let url: URL
            let isDraft: Bool?
        }

        struct Alert: Decodable {
            struct Vulnerability: Decodable { let severity: String? }
            let securityVulnerability: Vulnerability?
        }

        struct Commit: Decodable {
            struct Author: Decodable {
                struct User: Decodable {
                    let login: String
                    let avatarUrl: URL?
                }

                let name: String?
                let user: User?
            }

            struct Rollup: Decodable { let state: String }
            let oid: String?
            let committedDate: Date?
            let messageHeadline: String?
            let url: URL?
            let author: Author?
            let statusCheckRollup: Rollup?
        }

        struct Branch: Decodable { let target: Commit? }
        struct Releases: Decodable { let nodes: [ReleaseNode]? }
        struct Alerts: Decodable {
            let totalCount: Int?
            let nodes: [Alert]?
        }

        let pullRequests: Count
        let issues: Count
        let releases: Releases?
        let vulnerabilityAlerts: Alerts?
        let defaultBranchRef: Branch?

        func snapshot(for _: RepoRef) -> RepoSnapshot {
            let release = (self.releases?.nodes ?? [])
                .filter { $0.isDraft != true }
                .max { ($0.publishedAt ?? $0.createdAt ?? .distantPast) < ($1.publishedAt ?? $1.createdAt ?? .distantPast) }
                .map {
                    Release(
                        name: $0.name?.isEmpty == false ? ($0.name ?? $0.tagName) : $0.tagName,
                        tag: $0.tagName,
                        publishedAt: $0.publishedAt ?? $0.createdAt ?? .distantPast,
                        url: $0.url
                    )
                }
            let commit = self.defaultBranchRef?.target
            let event: ActivityEvent? = commit.flatMap { commit in
                guard let date = commit.committedDate, let url = commit.url else { return nil }
                return ActivityEvent(
                    title: commit.messageHeadline ?? "Commit",
                    actor: commit.author?.user?.login ?? commit.author?.name ?? "unknown",
                    actorAvatarURL: commit.author?.user?.avatarUrl,
                    date: date,
                    url: url,
                    eventType: ActivityEventType.push.rawValue
                )
            }
            return RepoSnapshot(
                openPulls: self.pullRequests.totalCount,
                openIssues: self.issues.totalCount,
                ci: GitHubRepoBatch.ciStatus(rollup: commit?.statusCheckRollup?.state),
                release: release,
                dependabot: self.vulnerabilityAlerts.flatMap(Self.tally),
                latestCommit: event
            )
        }

        /// The severities come from the first 100 alerts; the total is GitHub's own `totalCount`.
        /// Alerts past 100 (or without a severity) have no severity here, so they are counted as
        /// low: the total is right, and the breakdown is only exact up to 100.
        private static func tally(_ alerts: Alerts) -> DependabotTally? {
            guard let nodes = alerts.nodes else { return nil }
            let severities = nodes.compactMap { $0.securityVulnerability?.severity }
            func count(_ name: String) -> Int { severities.count(where: { $0 == name }) }
            let classified = count("CRITICAL") + count("HIGH") + count("MODERATE") + count("LOW")
            let unclassified = max((alerts.totalCount ?? nodes.count) - classified, 0)
            return DependabotTally(critical: count("CRITICAL"), high: count("HIGH"), medium: count("MODERATE"), low: count("LOW") + unclassified)
        }
    }
}

extension Repository {
    /// This repository with a batch snapshot applied; every count is now known.
    func applying(_ snapshot: RepoSnapshot) -> Repository {
        var copy = self
        copy.openPulls = snapshot.openPulls
        copy.openIssues = snapshot.openIssues
        copy.ciStatus = snapshot.ci
        copy.latestRelease = snapshot.release
        if let commit = snapshot.latestCommit { copy.latestActivity = commit }
        // The snapshot owns the Dependabot tally, so alerts that are now withheld (nil) clear an
        // old tally instead of leaving it on a repo whose alerts Harbor can no longer see.
        if snapshot.dependabot != nil || self.security != nil {
            copy.security = RepoSecurity(
                dependabot: snapshot.dependabot,
                secretLeaks: self.security?.secretLeaks,
                codeScanning: self.security?.codeScanning
            )
        }
        copy.pullCountsKnown = true
        // A good batch answers for the repo: an error or limit from an earlier one is over.
        copy.error = nil
        copy.rateLimitedUntil = nil
        return copy
    }

    /// This repository after a lookup that did not answer for it: counts unknown, CI unknown,
    /// the reason on the row. Never zero-and-known, and never old numbers that look fresh.
    func markedUnavailable(error: String?, rateLimitedUntil: Date?) -> Repository {
        var copy = self
        copy.pullCountsKnown = false
        copy.ciStatus = .unknown
        copy.error = error
        copy.rateLimitedUntil = rateLimitedUntil
        return copy
    }
}

extension GitHubRepoBatch {
    /// What the row says when GitHub left a repository out of a batch.
    static func missingMessage(for repo: RepoRef) -> String {
        "GitHub returned nothing for \(repo.fullName); it may need SSO authorization or access was lost."
    }
}

extension Repository {
    /// This repository (with the counts and detail it already shows) taking everything the
    /// fresh list owns: stars, forks, push time, archived, fork, sort order, and the open-issue
    /// count while no batch has answered for this repo. Lets a refresh redraw at once without
    /// blanking rows. Counts, CI, security and detail stay as they are until their own
    /// request lands.
    public func updatingListFields(from fresh: Repository) -> Repository {
        Repository(
            id: self.id,
            name: self.name,
            owner: self.owner,
            isFork: fresh.isFork,
            isArchived: fresh.isArchived,
            sortOrder: fresh.sortOrder,
            error: self.error,
            rateLimitedUntil: self.rateLimitedUntil,
            ciStatus: self.ciStatus,
            ciRunCount: self.ciRunCount,
            openIssues: self.pullCountsKnown ? self.openIssues : fresh.openIssues,
            openPulls: self.openPulls,
            stars: fresh.stars,
            forks: fresh.forks,
            pushedAt: fresh.pushedAt,
            latestRelease: self.latestRelease,
            latestActivity: self.latestActivity,
            activityEvents: self.activityEvents,
            traffic: self.traffic,
            heatmap: self.heatmap,
            security: self.security,
            pullCountsKnown: self.pullCountsKnown
        )
    }

    /// This (current, on-screen) repository after a batch answered for it. The batch owns
    /// pull and issue counts, CI, the Dependabot tally, the latest release and, when it did
    /// answer, the error state. Everything a detail load fetched meanwhile (activity feed, run
    /// count, traffic, secret and code counts) stays as it is.
    public func mergingBatch(_ batch: Repository) -> Repository {
        var copy = self
        copy.openPulls = batch.openPulls
        copy.openIssues = batch.openIssues
        copy.ciStatus = batch.ciStatus
        copy.pullCountsKnown = batch.pullCountsKnown
        copy.error = batch.error
        copy.rateLimitedUntil = batch.rateLimitedUntil
        if batch.pullCountsKnown {
            copy.latestRelease = batch.latestRelease
            copy.security = RepoSecurity(
                dependabot: batch.security?.dependabot,
                secretLeaks: self.security?.secretLeaks,
                codeScanning: self.security?.codeScanning
            )
        }
        if let commit = batch.latestActivity, commit.date >= (self.latestActivity?.date ?? .distantPast) {
            copy.latestActivity = commit
        }
        return copy
    }

    /// This (current, on-screen) repository after a detail load that started from `base`. The
    /// detail owns the activity feed, run count, traffic and the secret and code-scanning
    /// counts; a batch that landed while it ran keeps its counts, CI, release and Dependabot
    /// tally. A detail error replaces the row's error; a clean detail clears it, unless a
    /// failed batch put it there.
    public func mergingDetails(_ detailed: Repository, loadedFrom base: Repository) -> Repository {
        var copy = self
        copy.activityEvents = detailed.activityEvents
        copy.ciRunCount = detailed.ciRunCount
        copy.traffic = detailed.traffic
        // Only fills in CI the batch left unknown; a rollup the batch read is never replaced.
        if detailed.ciStatus != base.ciStatus, self.pullCountsKnown, self.ciStatus == .unknown { copy.ciStatus = detailed.ciStatus }
        if let commit = detailed.latestActivity, commit.date >= (self.latestActivity?.date ?? .distantPast) {
            copy.latestActivity = commit
        }
        if detailed.security?.secretLeaks != base.security?.secretLeaks || detailed.security?.codeScanning != base.security?.codeScanning {
            copy.security = RepoSecurity(
                dependabot: self.security?.dependabot,
                secretLeaks: detailed.security?.secretLeaks,
                codeScanning: detailed.security?.codeScanning
            )
        }
        if detailed.error != nil, detailed.error != base.error {
            copy.error = detailed.error
            copy.rateLimitedUntil = detailed.rateLimitedUntil
        } else if detailed.error == nil, self.pullCountsKnown {
            copy.error = nil
            copy.rateLimitedUntil = nil
        }
        return copy
    }
}
