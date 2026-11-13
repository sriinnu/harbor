import Foundation
import HarborCore

@MainActor
final class RecentMenuService {
    let listLimit: Int
    let previewLimit: Int
    let loadTimeout: TimeInterval

    private let github: GitHubClient
    private let recentIssuesCache = RecentListCache<RepoIssueSummary>()
    private let recentPullRequestsCache = RecentListCache<RepoPullRequestSummary>()
    private let recentReleasesCache = RecentListCache<RepoReleaseSummary>()
    private let recentWorkflowRunsCache = RecentListCache<RepoWorkflowRunSummary>()
    private let recentCommitsCache = RecentListCache<RepoCommitSummary>()
    private let recentDiscussionsCache = RecentListCache<RepoDiscussionSummary>()
    private let recentTagsCache = RecentListCache<RepoTagSummary>()
    private let recentBranchesCache = RecentListCache<RepoBranchSummary>()
    private let recentContributorsCache = RecentListCache<RepoContributorSummary>()
    private var recentCommitCounts: [String: Int] = [:]

    init(
        github: GitHubClient,
        listLimit: Int = AppLimits.RecentLists.limit,
        previewLimit: Int = AppLimits.RecentLists.previewLimit,
        loadTimeout: TimeInterval = AppLimits.RecentLists.loadTimeout
    ) {
        self.github = github
        self.listLimit = listLimit
        self.previewLimit = previewLimit
        self.loadTimeout = loadTimeout
    }

    /// A different account (or none) is signed in: the lists painted while loading belonged to the last one.
    func resetAccountScope() {
        self.recentIssuesCache.clear()
        self.recentPullRequestsCache.clear()
        self.recentReleasesCache.clear()
        self.recentWorkflowRunsCache.clear()
        self.recentCommitsCache.clear()
        self.recentDiscussionsCache.clear()
        self.recentTagsCache.clear()
        self.recentBranchesCache.clear()
        self.recentContributorsCache.clear()
        self.recentCommitCounts = [:]
    }

    func descriptor(for kind: RepoRecentMenuKind) -> RecentMenuDescriptor? {
        self.descriptors()[kind]
    }

    func descriptors() -> [RepoRecentMenuKind: RecentMenuDescriptor] {
        let commitDescriptor = self.commitDescriptor()

        let descriptors: [RecentMenuDescriptor] = [
            commitDescriptor,
            self.makeDescriptor(RecentMenuDescriptorConfig(
                kind: .issues,
                headerTitle: "Open Issues",
                headerIcon: "exclamationmark.circle",
                emptyTitle: "No open issues",
                cache: self.recentIssuesCache,
                wrap: RecentMenuItems.issues,
                unwrap: { boxed in
                    if case let .issues(items) = boxed { return items }
                    return nil
                },
                fetch: { github, owner, name, limit in
                    try await github.recentIssues(owner: owner, name: name, limit: limit)
                }
            )),
            self.makeDescriptor(RecentMenuDescriptorConfig(
                kind: .pullRequests,
                headerTitle: "Open Pull Requests",
                headerIcon: "arrow.triangle.branch",
                emptyTitle: "No open pull requests",
                cache: self.recentPullRequestsCache,
                wrap: RecentMenuItems.pullRequests,
                unwrap: { boxed in
                    if case let .pullRequests(items) = boxed { return items }
                    return nil
                },
                fetch: { github, owner, name, limit in
                    try await github.recentPullRequests(owner: owner, name: name, limit: limit)
                }
            )),
            self.makeDescriptor(RecentMenuDescriptorConfig(
                kind: .releases,
                headerTitle: "Open Releases",
                headerIcon: "tag",
                emptyTitle: "No releases",
                cache: self.recentReleasesCache,
                wrap: RecentMenuItems.releases,
                unwrap: { boxed in
                    if case let .releases(items) = boxed { return items }
                    return nil
                },
                fetch: { github, owner, name, limit in
                    try await github.recentReleases(owner: owner, name: name, limit: limit)
                }
            )),
            self.makeDescriptor(RecentMenuDescriptorConfig(
                kind: .ciRuns,
                headerTitle: "Open Actions",
                headerIcon: "bolt",
                emptyTitle: "No CI runs",
                cache: self.recentWorkflowRunsCache,
                wrap: RecentMenuItems.workflowRuns,
                unwrap: { boxed in
                    if case let .workflowRuns(items) = boxed { return items }
                    return nil
                },
                fetch: { github, owner, name, limit in
                    try await github.recentWorkflowRuns(owner: owner, name: name, limit: limit)
                }
            )),
            self.makeDescriptor(RecentMenuDescriptorConfig(
                kind: .discussions,
                headerTitle: "Open Discussions",
                headerIcon: "bubble.left.and.bubble.right",
                emptyTitle: "No discussions",
                cache: self.recentDiscussionsCache,
                wrap: RecentMenuItems.discussions,
                unwrap: { boxed in
                    if case let .discussions(items) = boxed { return items }
                    return nil
                },
                fetch: { github, owner, name, limit in
                    try await github.recentDiscussions(owner: owner, name: name, limit: limit)
                }
            )),
            self.makeDescriptor(RecentMenuDescriptorConfig(
                kind: .tags,
                headerTitle: "Open Tags",
                headerIcon: "tag",
                emptyTitle: "No tags",
                cache: self.recentTagsCache,
                wrap: RecentMenuItems.tags,
                unwrap: { boxed in
                    if case let .tags(items) = boxed { return items }
                    return nil
                },
                fetch: { github, owner, name, limit in
                    try await github.recentTags(owner: owner, name: name, limit: limit)
                }
            )),
            self.makeDescriptor(RecentMenuDescriptorConfig(
                kind: .branches,
                headerTitle: "Open Branches",
                headerIcon: "point.topleft.down.curvedto.point.bottomright.up",
                emptyTitle: "No branches",
                cache: self.recentBranchesCache,
                wrap: RecentMenuItems.branches,
                unwrap: { boxed in
                    if case let .branches(items) = boxed { return items }
                    return nil
                },
                fetch: { github, owner, name, limit in
                    try await github.recentBranches(owner: owner, name: name, limit: limit)
                }
            )),
            self.makeDescriptor(RecentMenuDescriptorConfig(
                kind: .contributors,
                headerTitle: "Open Contributors",
                headerIcon: "person.2",
                emptyTitle: "No contributors",
                cache: self.recentContributorsCache,
                wrap: RecentMenuItems.contributors,
                unwrap: { boxed in
                    if case let .contributors(items) = boxed { return items }
                    return nil
                },
                fetch: { github, owner, name, limit in
                    try await github.topContributors(owner: owner, name: name, limit: limit)
                }
            ))
        ]

        return Dictionary(uniqueKeysWithValues: descriptors.map { ($0.kind, $0) })
    }

    func cachedRecentListCount(fullName: String, kind: RepoRecentMenuKind) -> Int? {
        guard let descriptor = self.descriptor(for: kind) else { return nil }
        return descriptor.lastShown(fullName)?.count
    }

    func cachedRecentCommitCount(fullName: String) -> Int? {
        if let total = self.recentCommitCounts[fullName] { return total }
        return self.recentCommitsCache.lastShown(for: fullName)?.count
    }

    func cachedCommits(fullName: String) -> [RepoCommitSummary]? {
        self.recentCommitsCache.lastShown(for: fullName)
    }

    func cachedCommitDigest(fullName: String) -> Int? {
        guard let commits = self.cachedCommits(fullName: fullName), commits.isEmpty == false else { return nil }
        var hasher = Hasher()
        for commit in commits {
            hasher.combine(commit.sha)
            hasher.combine(commit.authoredAt.timeIntervalSinceReferenceDate)
        }
        return hasher.finalize()
    }

    private func commitDescriptor() -> RecentMenuDescriptor {
        RecentMenuDescriptor(
            kind: .commits,
            headerTitle: "Open Commits",
            headerIcon: "arrow.turn.down.right",
            emptyTitle: "No commits",
            lastShown: { key in
                self.recentCommitsCache.lastShown(for: key).map(RecentMenuItems.commits)
            },
            load: { key, owner, name, limit in
                let task = self.recentCommitsCache.task(for: key) {
                    let list = try await self.github.recentCommits(owner: owner, name: name, limit: limit)
                    await MainActor.run {
                        self.recentCommitCounts[key] = list.totalCount ?? list.items.count
                    }
                    return list.items
                }
                defer { self.recentCommitsCache.clearInflight(for: key) }
                let items = try await AsyncTimeout.value(within: self.loadTimeout, task: task)
                self.recentCommitsCache.store(items, for: key)
                return RecentMenuItems.commits(items)
            }
        )
    }

    private func makeDescriptor(
        _ config: RecentMenuDescriptorConfig<some Sendable>
    ) -> RecentMenuDescriptor {
        let fetch = config.fetch

        return RecentMenuDescriptor(
            kind: config.kind,
            headerTitle: config.headerTitle,
            headerIcon: config.headerIcon,
            emptyTitle: config.emptyTitle,
            lastShown: { key in
                config.cache.lastShown(for: key).map(config.wrap)
            },
            load: { key, owner, name, limit in
                let task = config.cache.task(for: key) {
                    try await fetch(self.github, owner, name, limit)
                }
                defer { config.cache.clearInflight(for: key) }
                let items = try await AsyncTimeout.value(within: self.loadTimeout, task: task)
                config.cache.store(items, for: key)
                return config.wrap(items)
            }
        )
    }
}

struct RecentMenuDescriptorConfig<Item: Sendable> {
    let kind: RepoRecentMenuKind
    let headerTitle: String
    let headerIcon: String?
    let emptyTitle: String
    let cache: RecentListCache<Item>
    let wrap: ([Item]) -> RecentMenuItems
    let unwrap: (RecentMenuItems) -> [Item]?
    let fetch: @Sendable (GitHubClient, String, String, Int) async throws -> [Item]
}

struct RecentMenuDescriptor {
    let kind: RepoRecentMenuKind
    let headerTitle: String
    let headerIcon: String?
    let emptyTitle: String
    /// What this list showed the last time it loaded, for drawing something while it loads again.
    let lastShown: (String) -> RecentMenuItems?
    let load: @MainActor (String, String, String, Int) async throws -> RecentMenuItems
}

enum RecentMenuItems: Sendable {
    case commits([RepoCommitSummary])
    case issues([RepoIssueSummary])
    case pullRequests([RepoPullRequestSummary])
    case releases([RepoReleaseSummary])
    case workflowRuns([RepoWorkflowRunSummary])
    case discussions([RepoDiscussionSummary])
    case tags([RepoTagSummary])
    case branches([RepoBranchSummary])
    case contributors([RepoContributorSummary])

    var isEmpty: Bool {
        switch self {
        case let .commits(items): items.isEmpty
        case let .issues(items): items.isEmpty
        case let .pullRequests(items): items.isEmpty
        case let .releases(items): items.isEmpty
        case let .workflowRuns(items): items.isEmpty
        case let .discussions(items): items.isEmpty
        case let .tags(items): items.isEmpty
        case let .branches(items): items.isEmpty
        case let .contributors(items): items.isEmpty
        }
    }

    var count: Int {
        switch self {
        case let .commits(items): items.count
        case let .issues(items): items.count
        case let .pullRequests(items): items.count
        case let .releases(items): items.count
        case let .workflowRuns(items): items.count
        case let .discussions(items): items.count
        case let .tags(items): items.count
        case let .branches(items): items.count
        case let .contributors(items): items.count
        }
    }
}

/// What a recent-list menu last showed, plus the request currently loading it. Nothing here
/// decides whether to fetch: every open asks GitHub, and this only gives the menu something to
/// draw until the answer lands. Identical loads in flight at once share one request.
final class RecentListCache<Item: Sendable> {
    private var shown: [String: [Item]] = [:]
    private var inflight: [String: Task<[Item], Error>] = [:]

    func lastShown(for key: String) -> [Item]? {
        self.shown[key]
    }

    func task(for key: String, factory: @escaping @Sendable () async throws -> [Item]) -> Task<[Item], Error> {
        if let existing = self.inflight[key] { return existing }
        let task = Task { try await factory() }
        self.inflight[key] = task
        return task
    }

    /// Forgets what was shown, and drops the loads in flight so their answers aren't stored.
    func clear() {
        for task in self.inflight.values { task.cancel() }
        self.inflight = [:]
        self.shown = [:]
    }

    func clearInflight(for key: String) {
        self.inflight[key] = nil
    }

    func store(_ items: [Item], for key: String) {
        self.shown[key] = items
    }
}
