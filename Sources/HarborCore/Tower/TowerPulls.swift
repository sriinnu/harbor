import Foundation

/// Which local branches have an open pull request of the signed-in user's. The Tower's
/// "In review" lane is made from this: a worktree whose branch is named here is in review.
public enum TowerPulls {
    /// `owner/name`, lowercased, out of a remote URL: `git@github.com:o/r.git`,
    /// `https://github.com/o/r`, `ssh://git@host:22/o/r.git`. nil when the URL doesn't end in
    /// two path components.
    public static func slug(remoteURL: String) -> String? {
        var text = remoteURL.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return nil }
        if text.hasSuffix("/") { text.removeLast() }
        if text.hasSuffix(".git") { text.removeLast(4) }
        // scp-like `host:owner/name` has no scheme; the path starts after the colon.
        let path: Substring
        if let scheme = text.range(of: "://") {
            let rest = text[scheme.upperBound...]
            guard let slash = rest.firstIndex(of: "/") else { return nil }
            path = rest[rest.index(after: slash)...]
        } else if let colon = text.firstIndex(of: ":") {
            path = text[text.index(after: colon)...]
        } else {
            return nil
        }
        let parts = path.split(separator: "/", omittingEmptySubsequences: true)
        guard parts.count >= 2 else { return nil }
        return "\(parts[parts.count - 2])/\(parts[parts.count - 1])".lowercased()
    }

    /// The slugs of every `remote.<name>.url` line of `git config --get-regexp` output.
    public static func slugs(configLines: String) -> Set<String> {
        var result = Set<String>()
        for line in configLines.split(whereSeparator: \.isNewline) {
            let fields = line.split(separator: " ", maxSplits: 1, omittingEmptySubsequences: true)
            if fields.count == 2, let slug = Self.slug(remoteURL: String(fields[1])) { result.insert(slug) }
        }
        return result
    }

    /// Head branch names of the open pull requests filed against any of `slugs`.
    /// `open` is keyed by lowercased `owner/name`.
    public static func branches(forRemotes slugs: Set<String>, open: [String: Set<String>]) -> Set<String> {
        slugs.reduce(into: Set<String>()) { $0.formUnion(open[$1] ?? []) }
    }
}

/// The branch half of the one search behind `GitHubClient.myPullRequests()` (Needs you reads the rest).
struct OpenPullBranchesWire: Decodable {
    struct Repo: Decodable { let nameWithOwner: String }
    struct Node: Decodable {
        let headRefName: String?
        let repository: Repo?
    }

    struct Search: Decodable { let nodes: [Node?]? }
    struct DataBody: Decodable { let search: Search }
    let data: DataBody

    /// Lowercased `owner/name` to head branch names. Search can return nodes that are not pull
    /// requests (empty objects); they are dropped.
    func branches() -> [String: Set<String>] {
        var result: [String: Set<String>] = [:]
        for node in self.data.search.nodes ?? [] {
            guard let node, let branch = node.headRefName, let repo = node.repository else { continue }
            result[repo.nameWithOwner.lowercased(), default: []].insert(branch)
        }
        return result
    }
}

public extension GitHubClient {
    /// The signed-in user's open pull requests as `owner/name` (lowercased) to head branch names:
    /// one batched request for every repo.
    func openPullBranches() async throws -> [String: Set<String>] {
        let data = try await self.graphQL.execute(
            query: MyPullsGraphQL.query, variables: [:], label: "MyPullRequests"
        )
        return try JSONDecoder().decode(OpenPullBranchesWire.self, from: data).branches()
    }
}
