import Foundation

/// The five lists a repo's detail opens in the panel.
public enum RepoListKind: String, CaseIterable, Sendable, Hashable {
    case issues
    case pulls
    case releases
    case runs
    case branches

    public var title: String {
        switch self {
        case .issues: "Issues"
        case .pulls: "Pull requests"
        case .releases: "Releases"
        case .runs: "Workflow runs"
        case .branches: "Branches"
        }
    }

    public var emptyText: String {
        switch self {
        case .issues: "No open issues."
        case .pulls: "No open pull requests."
        case .releases: "No releases yet."
        case .runs: "No workflow runs on the default branch."
        case .branches: "No branches."
        }
    }

    /// The repo's own page for this list, as `repoPathURL` knows it.
    public var webPath: String {
        switch self {
        case .issues: "issues"
        case .pulls: "pulls"
        case .releases: "releases"
        case .runs: "actions"
        case .branches: "branches"
        }
    }
}

/// One row of a list: already worded, so the view only lays it out.
public struct RepoListRow: Identifiable, Equatable, Sendable {
    public enum Mark: Equatable, Sendable {
        case issue
        case pull
        case draftPull
        case release
        case prerelease
        case branch
        case defaultBranch
        case run(CIStatus)
    }

    public let id: String
    public let title: String
    public let subtitle: String
    /// Set for pull requests, which open the in-panel pane instead of the browser.
    public let pullNumber: Int?
    public let url: URL?
    public let mark: Mark

    public init(id: String, title: String, subtitle: String, pullNumber: Int? = nil, url: URL?, mark: Mark) {
        self.id = id
        self.title = title
        self.subtitle = subtitle
        self.pullNumber = pullNumber
        self.url = url
        self.mark = mark
    }
}

public struct RepoListPage: Equatable, Sendable {
    public let rows: [RepoListRow]
    /// The repo's own count when GitHub reports one; more than `rows.count` means truncated.
    public let total: Int?

    public init(rows: [RepoListRow], total: Int?) {
        self.rows = rows
        self.total = total
    }

    public var truncationNote: String? {
        guard let total, total > self.rows.count else { return nil }
        return "Showing \(self.rows.count) of \(total) · open on GitHub for the rest"
    }
}

/// A pull request somebody asked the signed-in user to review.
public struct ReviewRequest: Identifiable, Equatable, Sendable {
    public let repoFullName: String
    public let number: Int
    public let title: String
    public let url: URL?
    public let authorLogin: String?
    public let isDraft: Bool
    public let updatedAt: Date?

    public var id: String { "\(self.repoFullName)#\(self.number)" }

    public init(
        repoFullName: String, number: Int, title: String, url: URL?,
        authorLogin: String?, isDraft: Bool, updatedAt: Date?
    ) {
        self.repoFullName = repoFullName
        self.number = number
        self.title = title
        self.url = url
        self.authorLogin = authorLogin
        self.isDraft = isDraft
        self.updatedAt = updatedAt
    }

    /// "owner/repo #91 · @author · 2d"
    public func detailLine(now: Date) -> String {
        var parts = ["\(self.repoFullName) #\(self.number)"]
        if let authorLogin { parts.append("@\(authorLogin)") }
        if self.isDraft { parts.append("draft") }
        if let age = RepoListText.age(self.updatedAt, now: now) { parts.append(age) }
        return parts.joined(separator: " · ")
    }
}

/// The pull requests asking for the user's review: the first page, and how many there are in
/// all (GitHub's `issueCount`), so a longer list can say so instead of looking complete.
public struct ReviewRequestList: Equatable, Sendable {
    public let requests: [ReviewRequest]
    /// GitHub's total; nil when the response did not carry one.
    public let total: Int?

    public init(requests: [ReviewRequest], total: Int?) {
        self.requests = requests
        self.total = total
    }

    /// How many requests exist beyond the ones in `requests`.
    public var hiddenCount: Int {
        guard let total, total > self.requests.count else { return 0 }
        return total - self.requests.count
    }
}

/// The GraphQL documents behind the lists, pinned exactly by tests. One query per list, run
/// only when that list opens.
enum RepoListGraphQL {
    static let issues = """
    query RepoIssues($owner: String!, $name: String!) {
      repository(owner: $owner, name: $name) {
        issues(first: 30, states: OPEN, orderBy: {field: UPDATED_AT, direction: DESC}) {
          totalCount
          nodes {
            number
            title
            url
            updatedAt
            author { login }
            comments { totalCount }
          }
        }
      }
    }
    """

    static let pulls = """
    query RepoPulls($owner: String!, $name: String!) {
      repository(owner: $owner, name: $name) {
        pullRequests(first: 30, states: OPEN, orderBy: {field: UPDATED_AT, direction: DESC}) {
          totalCount
          nodes {
            number
            title
            url
            updatedAt
            isDraft
            author { login }
            headRefName
            baseRefName
          }
        }
      }
    }
    """

    static let releases = """
    query RepoReleases($owner: String!, $name: String!) {
      repository(owner: $owner, name: $name) {
        releases(first: 20, orderBy: {field: CREATED_AT, direction: DESC}) {
          totalCount
          nodes {
            name
            tagName
            url
            publishedAt
            createdAt
            isPrerelease
            author { login }
          }
        }
      }
    }
    """

    /// GraphQL has no workflow-run list; the check suites of the default branch's latest
    /// commits carry their workflow run, which is what the Actions tab shows for it.
    static let runs = """
    query RepoRuns($owner: String!, $name: String!) {
      repository(owner: $owner, name: $name) {
        defaultBranchRef {
          name
          target {
            ... on Commit {
              history(first: 10) {
                nodes {
                  checkSuites(first: 6) {
                    nodes {
                      status
                      conclusion
                      updatedAt
                      workflowRun { runNumber url event workflow { name } }
                    }
                  }
                }
              }
            }
          }
        }
      }
    }
    """

    static let branches = """
    query RepoBranches($owner: String!, $name: String!) {
      repository(owner: $owner, name: $name) {
        url
        defaultBranchRef { name }
        refs(refPrefix: "refs/heads/", first: 50, orderBy: {field: ALPHABETICAL, direction: ASC}) {
          totalCount
          nodes {
            name
            target { ... on Commit { committedDate } }
          }
        }
      }
    }
    """

    static func document(for kind: RepoListKind) -> String {
        switch kind {
        case .issues: self.issues
        case .pulls: self.pulls
        case .releases: self.releases
        case .runs: self.runs
        case .branches: self.branches
        }
    }

    static let reviewRequests = """
    query ReviewRequests {
      search(query: "is:open is:pr review-requested:@me archived:false", type: ISSUE, first: 20) {
        issueCount
        nodes {
          ... on PullRequest {
            number
            title
            url
            updatedAt
            isDraft
            author { login }
            repository { nameWithOwner }
          }
        }
      }
    }
    """
}

/// Wording shared by the list rows.
enum RepoListText {
    static func age(_ date: Date?, now: Date) -> String? {
        guard let date else { return nil }
        let seconds = max(0, Int(now.timeIntervalSince(date)))
        switch seconds {
        case ..<60: return "now"
        case ..<3600: return "\(seconds / 60)m"
        case ..<86400: return "\(seconds / 3600)h"
        case ..<(86400 * 14): return "\(seconds / 86400)d"
        case ..<(86400 * 365): return "\(seconds / (86400 * 7))w"
        default: return "\(seconds / (86400 * 365))y"
        }
    }

    static func plural(_ count: Int, _ noun: String) -> String {
        count == 1 ? "1 \(noun)" : "\(count) \(noun)s"
    }
}

// MARK: - Wire models

/// Every list's response, one shape: each document fills only its own field.
struct RepoListWire: Decodable {
    struct Login: Decodable { let login: String }
    struct Count: Decodable { let totalCount: Int }
    struct Nodes<T: Decodable>: Decodable {
        let totalCount: Int?
        let nodes: [T?]?
        var items: [T] { (self.nodes ?? []).compactMap { $0 } }
    }

    struct Issue: Decodable {
        let number: Int
        let title: String
        let url: URL?
        let updatedAt: Date?
        let author: Login?
        let comments: Count?
    }

    struct Pull: Decodable {
        let number: Int
        let title: String
        let url: URL?
        let updatedAt: Date?
        let isDraft: Bool
        let author: Login?
        let headRefName: String?
        let baseRefName: String?
    }

    struct Release: Decodable {
        let name: String?
        let tagName: String
        let url: URL?
        let publishedAt: Date?
        let createdAt: Date?
        let isPrerelease: Bool
        let author: Login?
    }

    struct Suite: Decodable {
        struct WorkflowRun: Decodable {
            struct Workflow: Decodable { let name: String }
            let runNumber: Int
            let url: URL?
            let event: String?
            let workflow: Workflow?
        }

        let status: String
        let conclusion: String?
        let updatedAt: Date?
        let workflowRun: WorkflowRun?
    }

    struct Commit: Decodable {
        struct Suites: Decodable { let nodes: [Suite?]? }
        let checkSuites: Suites?
    }

    struct History: Decodable { let nodes: [Commit?]? }
    struct Target: Decodable {
        let history: History?
        let committedDate: Date?
    }

    struct Ref: Decodable {
        let name: String
        let target: Target?
    }

    struct Repository: Decodable {
        struct DefaultRef: Decodable {
            let name: String
            let target: Target?
        }

        let url: URL?
        let issues: Nodes<Issue>?
        let pullRequests: Nodes<Pull>?
        let releases: Nodes<Release>?
        let defaultBranchRef: DefaultRef?
        let refs: Nodes<Ref>?
    }

    struct DataBody: Decodable { let repository: Repository? }
    let data: DataBody

    /// nil when the repository is not visible.
    func page(for kind: RepoListKind, now: Date) -> RepoListPage? {
        guard let repo = data.repository else { return nil }
        switch kind {
        case .issues:
            let list = repo.issues
            return RepoListPage(rows: (list?.items ?? []).map { Self.row($0, now: now) }, total: list?.totalCount)
        case .pulls:
            let list = repo.pullRequests
            return RepoListPage(rows: (list?.items ?? []).map { Self.row($0, now: now) }, total: list?.totalCount)
        case .releases:
            let list = repo.releases
            return RepoListPage(rows: (list?.items ?? []).map { Self.row($0, now: now) }, total: list?.totalCount)
        case .runs:
            return RepoListPage(rows: Self.runRows(repo, now: now), total: nil)
        case .branches:
            return RepoListPage(rows: Self.branchRows(repo, now: now), total: repo.refs?.totalCount)
        }
    }

    static func row(_ issue: Issue, now: Date) -> RepoListRow {
        var parts = ["#\(issue.number)"]
        if let author = issue.author?.login { parts.append("@\(author)") }
        if let age = RepoListText.age(issue.updatedAt, now: now) { parts.append(age) }
        if let comments = issue.comments?.totalCount, comments > 0 { parts.append(RepoListText.plural(comments, "comment")) }
        return RepoListRow(
            id: "issue:\(issue.number)", title: issue.title, subtitle: parts.joined(separator: " · "),
            url: issue.url, mark: .issue
        )
    }

    static func row(_ pull: Pull, now: Date) -> RepoListRow {
        var parts = ["#\(pull.number)"]
        if let author = pull.author?.login { parts.append("@\(author)") }
        if pull.isDraft { parts.append("draft") }
        if let age = RepoListText.age(pull.updatedAt, now: now) { parts.append(age) }
        if let head = pull.headRefName, let base = pull.baseRefName { parts.append("\(head) → \(base)") }
        return RepoListRow(
            id: "pull:\(pull.number)", title: pull.title, subtitle: parts.joined(separator: " · "),
            pullNumber: pull.number, url: pull.url, mark: pull.isDraft ? .draftPull : .pull
        )
    }

    static func row(_ release: Release, now: Date) -> RepoListRow {
        var parts = [release.tagName]
        if let author = release.author?.login { parts.append("@\(author)") }
        if let age = RepoListText.age(release.publishedAt ?? release.createdAt, now: now) { parts.append(age) }
        if release.isPrerelease { parts.append("pre-release") }
        let name = release.name.flatMap { $0.isEmpty ? nil : $0 } ?? release.tagName
        return RepoListRow(
            id: "release:\(release.tagName)", title: name, subtitle: parts.joined(separator: " · "),
            url: release.url, mark: release.isPrerelease ? .prerelease : .release
        )
    }

    /// Check suites that belong to no workflow (apps, status checks) are not runs and are
    /// left out; newest first, one row per run.
    static func runRows(_ repo: Repository, now: Date) -> [RepoListRow] {
        let commits = (repo.defaultBranchRef?.target?.history?.nodes ?? []).compactMap { $0 }
        let suites = commits.flatMap { ($0.checkSuites?.nodes ?? []).compactMap { $0 } }
        var seen = Set<Int>()
        let runs = suites
            .compactMap { suite in suite.workflowRun.map { (suite, $0) } }
            .filter { seen.insert($0.1.runNumber).inserted }
            .sorted { ($0.0.updatedAt ?? .distantPast) > ($1.0.updatedAt ?? .distantPast) }
        let branch = repo.defaultBranchRef?.name
        return runs.prefix(20).map { suite, run in
            let status = Self.ciStatus(status: suite.status, conclusion: suite.conclusion)
            var parts = ["#\(run.runNumber)"]
            if let event = run.event { parts.append(event) }
            if let branch { parts.append(branch) }
            if let age = RepoListText.age(suite.updatedAt, now: now) { parts.append(age) }
            parts.append(Self.outcome(status: suite.status, conclusion: suite.conclusion))
            return RepoListRow(
                id: "run:\(run.runNumber)", title: run.workflow?.name ?? "Workflow run",
                subtitle: parts.joined(separator: " · "), url: run.url, mark: .run(status)
            )
        }
    }

    static func ciStatus(status: String, conclusion: String?) -> CIStatus {
        guard status == "COMPLETED" else { return .pending }
        switch conclusion {
        case "SUCCESS": return .passing
        case "FAILURE", "TIMED_OUT", "STARTUP_FAILURE", "ACTION_REQUIRED": return .failing
        default: return .unknown
        }
    }

    static func outcome(status: String, conclusion: String?) -> String {
        guard status == "COMPLETED" else { return status == "IN_PROGRESS" ? "running" : "queued" }
        switch conclusion {
        case "SUCCESS": return "passed"
        case "FAILURE": return "failed"
        case "TIMED_OUT": return "timed out"
        case "STARTUP_FAILURE": return "failed to start"
        case "ACTION_REQUIRED": return "action required"
        case "CANCELLED": return "cancelled"
        case "SKIPPED": return "skipped"
        case "NEUTRAL": return "neutral"
        case "STALE": return "stale"
        default: return "finished"
        }
    }

    /// The default branch first, then by last commit, newest first.
    static func branchRows(_ repo: Repository, now: Date) -> [RepoListRow] {
        let defaultName = repo.defaultBranchRef?.name
        let refs = (repo.refs?.items ?? []).sorted { lhs, rhs in
            if lhs.name == defaultName { return true }
            if rhs.name == defaultName { return false }
            return (lhs.target?.committedDate ?? .distantPast) > (rhs.target?.committedDate ?? .distantPast)
        }
        return refs.map { ref in
            let isDefault = ref.name == defaultName
            var parts: [String] = []
            if isDefault { parts.append("default") }
            if let age = RepoListText.age(ref.target?.committedDate, now: now) { parts.append("updated \(age)") }
            let encoded = ref.name.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? ref.name
            return RepoListRow(
                id: "branch:\(ref.name)", title: ref.name, subtitle: parts.joined(separator: " · "),
                url: repo.url.flatMap { URL(string: "\($0.absoluteString)/tree/\(encoded)") }, mark: isDefault ? .defaultBranch : .branch
            )
        }
    }
}

struct ReviewRequestsWire: Decodable {
    struct Login: Decodable { let login: String }
    struct Repo: Decodable { let nameWithOwner: String }
    struct Node: Decodable {
        let number: Int?
        let title: String?
        let url: URL?
        let updatedAt: Date?
        let isDraft: Bool?
        let author: Login?
        let repository: Repo?
    }

    struct Search: Decodable {
        let issueCount: Int?
        let nodes: [Node?]?
    }
    struct DataBody: Decodable { let search: Search }
    let data: DataBody

    func list() -> ReviewRequestList {
        ReviewRequestList(requests: self.requests(), total: self.data.search.issueCount)
    }

    /// Search can also return nodes that are not pull requests (empty objects); they are dropped.
    func requests() -> [ReviewRequest] {
        (data.search.nodes ?? []).compactMap { node in
            guard let node, let number = node.number, let title = node.title, let repo = node.repository else { return nil }
            return ReviewRequest(
                repoFullName: repo.nameWithOwner, number: number, title: title, url: node.url,
                authorLogin: node.author?.login, isDraft: node.isDraft ?? false, updatedAt: node.updatedAt
            )
        }
    }
}

// MARK: - Client

public extension GitHubClient {
    func repoList(kind: RepoListKind, owner: String, name: String) async throws -> RepoListPage {
        let data = try await self.graphQL.execute(
            query: RepoListGraphQL.document(for: kind),
            variables: ["owner": .string(owner), "name": .string(name)],
            label: "RepoList.\(kind.rawValue)"
        )
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        guard let page = try decoder.decode(RepoListWire.self, from: data).page(for: kind, now: Date()) else {
            throw GitHubAPIError.badStatus(code: 404, message: "\(owner)/\(name) was not found.")
        }
        return page
    }

    /// One search for every open pull request that asks for the signed-in user's review: the
    /// first 20, and the total.
    func reviewRequests() async throws -> ReviewRequestList {
        let data = try await self.graphQL.execute(
            query: RepoListGraphQL.reviewRequests, variables: [:], label: "ReviewRequests"
        )
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return try decoder.decode(ReviewRequestsWire.self, from: data).list()
    }
}
