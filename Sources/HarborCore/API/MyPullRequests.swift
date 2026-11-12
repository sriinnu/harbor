import Foundation

/// Why one of the signed-in user's own open pull requests needs them.
public enum MyPullReason: String, Equatable, Sendable, CaseIterable {
    case changesRequested
    case checksFailing
    case conflict
    case readyToMerge

    /// The words a Needs-you row and a notification use.
    public var label: String {
        switch self {
        case .changesRequested: "changes requested"
        case .checksFailing: "checks failing"
        case .conflict: "merge conflict"
        case .readyToMerge: "ready to merge"
        }
    }
}

/// One open pull request of the signed-in user's, with only the facts Needs you is judged on.
public struct MyPullRequest: Identifiable, Equatable, Sendable {
    public let repoFullName: String
    public let number: Int
    public let title: String
    public let url: URL?
    public let headBranch: String?
    public let isDraft: Bool
    public let updatedAt: Date?
    /// GitHub's `reviewDecision`: APPROVED, CHANGES_REQUESTED, REVIEW_REQUIRED; nil when no review is required.
    public let reviewDecision: String?
    /// GitHub's `mergeable`: MERGEABLE, CONFLICTING, UNKNOWN (still being worked out).
    public let mergeable: String?
    /// The head commit's check rollup: SUCCESS, FAILURE, ERROR, PENDING, EXPECTED; nil when it has none.
    public let checksState: String?

    public var id: String { "\(self.repoFullName)#\(self.number)" }

    public init(
        repoFullName: String, number: Int, title: String, url: URL? = nil, headBranch: String? = nil,
        isDraft: Bool = false, updatedAt: Date? = nil, reviewDecision: String? = nil, mergeable: String? = nil,
        checksState: String? = nil
    ) {
        self.repoFullName = repoFullName
        self.number = number
        self.title = title
        self.url = url
        self.headBranch = headBranch
        self.isDraft = isDraft
        self.updatedAt = updatedAt
        self.reviewDecision = reviewDecision
        self.mergeable = mergeable
        self.checksState = checksState
    }

    /// The reasons this pull request needs its author, most urgent first; empty when it does not.
    /// Ready to merge means approved, not a draft, no conflict, and checks that passed or do not
    /// exist: an unknown mergeable state or a pending check is not ready yet.
    public var reasons: [MyPullReason] {
        var result: [MyPullReason] = []
        if self.reviewDecision == "CHANGES_REQUESTED" { result.append(.changesRequested) }
        if self.checksState == "FAILURE" || self.checksState == "ERROR" { result.append(.checksFailing) }
        if self.mergeable == "CONFLICTING" { result.append(.conflict) }
        let checksOK = self.checksState == nil || self.checksState == "SUCCESS"
        if !self.isDraft, self.reviewDecision == "APPROVED", checksOK, self.mergeable == "MERGEABLE" {
            result.append(.readyToMerge)
        }
        return result
    }

    /// "owner/repo #12 · changes requested, checks failing"
    public var detailLine: String {
        "\(self.repoFullName) #\(self.number) · " + self.reasons.map(\.label).joined(separator: ", ")
    }
}

/// The wire shape of the one search behind `GitHubClient.myPullRequests()`.
struct MyPullRequestsWire: Decodable {
    struct Repo: Decodable { let nameWithOwner: String }
    struct Rollup: Decodable { let state: String? }
    struct CommitBody: Decodable { let statusCheckRollup: Rollup? }
    struct CommitNode: Decodable { let commit: CommitBody? }
    struct Commits: Decodable { let nodes: [CommitNode?]? }
    struct Node: Decodable {
        let number: Int?
        let title: String?
        let url: URL?
        let updatedAt: Date?
        let isDraft: Bool?
        let headRefName: String?
        let reviewDecision: String?
        let mergeable: String?
        let repository: Repo?
        let commits: Commits?
    }

    struct Search: Decodable { let nodes: [Node?]? }
    struct DataBody: Decodable { let search: Search }
    let data: DataBody

    /// Search can return nodes that are not pull requests (empty objects); they are dropped.
    func pulls() -> [MyPullRequest] {
        (self.data.search.nodes ?? []).compactMap { node in
            guard let node, let number = node.number, let title = node.title, let repo = node.repository else { return nil }
            return MyPullRequest(
                repoFullName: repo.nameWithOwner, number: number, title: title, url: node.url,
                headBranch: node.headRefName, isDraft: node.isDraft ?? false, updatedAt: node.updatedAt,
                reviewDecision: node.reviewDecision, mergeable: node.mergeable,
                checksState: node.commits?.nodes?.compactMap { $0 }.last?.commit?.statusCheckRollup?.state
            )
        }
    }
}

enum MyPullsGraphQL {
    /// The one search for the user's own open pull requests, newest first, 100 at most. Needs you
    /// and the Tower's "In review" lane both read it. Nothing is kept between calls.
    static let query = """
    query MyPullRequests {
      search(query: "is:open is:pr author:@me archived:false sort:updated-desc", type: ISSUE, first: 100) {
        nodes {
          ... on PullRequest {
            number
            title
            url
            updatedAt
            isDraft
            headRefName
            reviewDecision
            mergeable
            repository { nameWithOwner }
            commits(last: 1) { nodes { commit { statusCheckRollup { state } } } }
          }
        }
      }
    }
    """
}

public extension GitHubClient {
    /// The signed-in user's open pull requests, in one search.
    func myPullRequests() async throws -> [MyPullRequest] {
        let data = try await self.graphQL.execute(query: MyPullsGraphQL.query, variables: [:], label: "MyPullRequests")
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return try decoder.decode(MyPullRequestsWire.self, from: data).pulls()
    }
}

/// The needs-you items that appeared since the last answer. The first answer after launch,
/// sign-in or `reset()` only sets the baseline, so nothing is announced for what was already
/// waiting. An item that leaves and comes back is new again. Memory only.
public struct NeedsYouWatcher: Sendable {
    public struct Item: Hashable, Sendable {
        /// Stable identity, one per pull request and reason: `review:o/r#1`, `mine:o/r#2:conflict`.
        public let key: String
        public let title: String
        public let detail: String

        public init(key: String, title: String, detail: String) {
            self.key = key
            self.title = title
            self.detail = detail
        }
    }

    private var seen: Set<String>?

    public init() {}

    /// The items in `current` not in the previous answer, in order; empty on the baseline.
    public mutating func observe(_ current: [Item]) -> [Item] {
        let keys = Set(current.map(\.key))
        defer { self.seen = keys }
        guard let seen = self.seen else { return [] }
        return current.filter { !seen.contains($0.key) }
    }

    /// `observe` for the user's own pull requests. GitHub answers `mergeable: UNKNOWN` for a
    /// while after every push to the base branch; that is "not worked out yet", not a change. For
    /// such a pull request the conflict and ready-to-merge keys seen before are kept, so the state
    /// coming back is not announced a second time.
    public mutating func observe(mine: [MyPullRequest]) -> [Item] {
        var carried = Set<String>()
        if let seen = self.seen {
            for pull in mine where pull.mergeable == "UNKNOWN" {
                for reason in [MyPullReason.conflict, .readyToMerge] {
                    let key = "mine:\(pull.id):\(reason.rawValue)"
                    if seen.contains(key) { carried.insert(key) }
                }
            }
        }
        let current = Self.items(mine: mine)
        let keys = Set(current.map(\.key)).union(carried)
        defer { self.seen = keys }
        guard let seen = self.seen else { return [] }
        return current.filter { !seen.contains($0.key) }
    }

    public mutating func reset() { self.seen = nil }

    /// The needs-you items of review requests: a pull request is one item.
    public static func items(reviews: [ReviewRequest]) -> [Item] {
        reviews.map { Item(key: "review:\($0.id)", title: $0.title, detail: "Review requested · \($0.repoFullName) #\($0.number)") }
    }

    /// One item per pull request and reason, so a new reason on a known pull request is news.
    public static func items(mine: [MyPullRequest]) -> [Item] {
        mine.flatMap { pull in
            pull.reasons.map {
                Item(key: "mine:\(pull.id):\($0.rawValue)", title: pull.title, detail: "\($0.label.capitalizedFirst) · \(pull.repoFullName) #\(pull.number)")
            }
        }
    }

    /// The words of one notification for what just entered; nil when nothing did.
    public static func message(for entered: [Item]) -> String? {
        switch entered.count {
        case 0: nil
        case 1: "\(entered[0].detail): \(entered[0].title)"
        default: "\(entered.count) new things need you"
        }
    }
}

private extension String {
    var capitalizedFirst: String { self.prefix(1).uppercased() + self.dropFirst() }
}
