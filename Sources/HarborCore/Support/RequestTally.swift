import Foundation

/// Counts the network calls Harbor makes, by transport and endpoint, so a refresh can be
/// audited ("how many REST calls did that cost?"). Only counts and path templates are kept:
/// no tokens, no owner, repository, branch, tag or file names, no SHAs, no query strings.
/// A path segment survives only if it is a known GitHub endpoint word; every other one
/// becomes `{x}`. The set of keys is also capped, so it cannot grow without bound.
public actor RequestTally {
    public static let shared = RequestTally()

    public struct Snapshot: Sendable, Equatable {
        public var rest: [String: Int] = [:]
        public var graphQL: [String: Int] = [:]
        public init(rest: [String: Int] = [:], graphQL: [String: Int] = [:]) {
            self.rest = rest
            self.graphQL = graphQL
        }

        public var restTotal: Int { self.rest.values.reduce(0, +) }
        public var graphQLTotal: Int { self.graphQL.values.reduce(0, +) }
    }

    /// Most distinct keys per transport between drains; the rest count under `overflowKey`.
    public static let maxKeys = 64
    public static let overflowKey = "(other)"

    private var current = Snapshot()

    public func recordREST(path: String) {
        Self.add(Self.template(forPath: path), to: &self.current.rest)
    }

    public func recordGraphQL(label: String) {
        Self.add(label, to: &self.current.graphQL)
    }

    private static func add(_ key: String, to counts: inout [String: Int]) {
        let bounded = counts[key] != nil || counts.count < self.maxKeys ? key : self.overflowKey
        counts[bounded, default: 0] += 1
    }

    public func snapshot() -> Snapshot { self.current }

    /// Returns what was counted and starts again from zero.
    public func drain() -> Snapshot {
        defer { self.current = Snapshot() }
        return self.current
    }

    /// `/repos/octo/hello/pulls` becomes `/repos/{owner}/{repo}/pulls`, so counts group by endpoint.
    public static func template(forPath path: String) -> String {
        var parts = path.split(separator: "/", omittingEmptySubsequences: true).map(String.init)
        if parts.first == "repos", parts.count >= 3 {
            parts[1] = "{owner}"
            parts[2] = "{repo}"
        } else if parts.first == "users", parts.count >= 2 {
            parts[1] = "{user}"
        } else if parts.first == "orgs", parts.count >= 2 {
            parts[1] = "{org}"
        }
        let skipped: Set<Int> = Set(parts.indices.filter { parts[$0].hasPrefix("{") })
        for index in parts.indices where !skipped.contains(index) {
            if Int(parts[index]) != nil {
                parts[index] = "{n}"
            } else if !Self.endpointWords.contains(parts[index]) {
                parts[index] = "{x}"
            }
        }
        return "/" + parts.joined(separator: "/")
    }

    /// The fixed words of the GitHub REST paths Harbor calls. Anything else in a path is
    /// data (a branch, a tag, a SHA, a file or workflow name) and is not recorded.
    static let endpointWords: Set<String> = [
        "repos", "user", "users", "orgs", "search", "rate_limit", "graphql",
        "pulls", "issues", "reviews", "comments", "commits", "branches", "tags", "releases", "latest",
        "contents", "compare", "events", "forks", "readme", "languages", "contributors", "discussions",
        "actions", "runs", "workflows", "workflow", "jobs", "logs", "artifacts", "permissions", "timing",
        "rules", "protection", "stats", "commit_activity", "traffic", "views", "clones",
        "code-scanning", "secret-scanning", "dependabot", "alerts", "automated-security-fixes",
        "private-vulnerability-reporting", "check-runs", "check-suites", "status", "statuses",
        "git", "refs", "trees", "memberships", "starred", "subscriptions", "installations"
    ]

    /// One log line, for the debug log.
    public static func summary(_ snapshot: Snapshot) -> String {
        func lines(_ counts: [String: Int]) -> String {
            counts.sorted { $0.value == $1.value ? $0.key < $1.key : $0.value > $1.value }
                .map { "\($0.key)=\($0.value)" }.joined(separator: " ")
        }
        return "requests rest=\(snapshot.restTotal) graphql=\(snapshot.graphQLTotal) | REST \(lines(snapshot.rest)) | GQL \(lines(snapshot.graphQL))"
    }
}
