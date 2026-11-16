import Foundation

/// Which listed repositories get their counts this refresh. The listing can hold thousands
/// (every repo of every org the user belongs to); one GraphQL query covers
/// `GitHubRepoBatch.maxPerQuery` of them, so counting all of them every few minutes would spend
/// the hourly budget on rows nobody is looking at.
///
/// The rule is bounded cost, not a memo: pinned repos always, then the most recently pushed
/// ones up to `recentCap`, then no more than the remaining GraphQL budget can pay for. Every
/// other repo is counted when its detail opens (`AppState.loadRepoDetails`), and the panel says
/// how many were left out.
public struct RepoEnrichmentPlan: Equatable, Sendable {
    /// Newest-pushed repositories counted on every refresh, besides the pinned ones.
    public static let recentCap = 60
    /// Points kept for everything else that spends GraphQL (searches, details, contribution data).
    public static let budgetReserve = 500
    /// A deliberately high estimate of one batch query's cost, so the plan errs toward fewer queries.
    public static let pointsPerQuery = 5

    public let enrich: [Repository]
    public let deferred: [Repository]

    /// - Parameters:
    ///   - repos: The visible list, newest push first (the order GitHub lists them in).
    ///   - pinned: Full names that always count.
    ///   - opened: Repos whose detail was opened this session (a short, bounded list kept in memory,
    ///     not a response cache): they stay counted on the refreshes that follow, so numbers just
    ///     loaded from a detail do not blink out. They go first, like pinned ones.
    ///   - graphQLRemaining: Points GitHub last reported left, or nil when none has been seen.
    public static func make(
        repos: [Repository],
        pinned: Set<String>,
        opened: Set<String> = [],
        graphQLRemaining: Int?,
        cap: Int = RepoEnrichmentPlan.recentCap
    ) -> RepoEnrichmentPlan {
        let first = pinned.union(opened)
        let pinnedRepos = repos.filter { first.contains($0.fullName) }
        let others = repos.filter { !first.contains($0.fullName) }
            .sorted { ($0.pushedAt ?? .distantPast) > ($1.pushedAt ?? .distantPast) }
        var take = pinnedRepos + others.prefix(max(cap, 0))
        if let remaining = graphQLRemaining {
            let queries = max(remaining - self.budgetReserve, 0) / self.pointsPerQuery
            take = Array(take.prefix(queries * GitHubRepoBatch.maxPerQuery))
        }
        let taken = Set(take.map(\.fullName))
        return RepoEnrichmentPlan(enrich: take, deferred: repos.filter { !taken.contains($0.fullName) })
    }
}
