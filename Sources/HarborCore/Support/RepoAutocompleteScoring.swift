import Foundation

public enum RepoAutocompleteScoring {
    private struct ComponentScoreWeights {
        let exact: Int
        let prefix: Int
        let substring: Int
        let subsequence: Int
    }

    public struct Scored {
        public let repo: Repository
        public let score: Int
        public let sourceRank: Int

        public init(repo: Repository, score: Int, sourceRank: Int) {
            self.repo = repo
            self.score = score
            self.sourceRank = sourceRank
        }
    }

    public static func scored(
        repos: [Repository],
        query: String,
        sourceRank: Int,
        bonus: Int = 0
    ) -> [Scored] {
        repos.compactMap { repo in
            guard let score = Self.score(repo: repo, query: query) else { return nil }
            return Scored(repo: repo, score: score + bonus, sourceRank: sourceRank)
        }
    }

    public static func sort(_ scored: [Scored]) -> [Scored] {
        scored.sorted {
            if $0.score != $1.score { return $0.score > $1.score }
            if $0.sourceRank != $1.sourceRank { return $0.sourceRank < $1.sourceRank }
            return $0.repo.fullName.localizedCaseInsensitiveCompare($1.repo.fullName) == .orderedAscending
        }
    }

    /// The repo picker's list: the user's own repos (theirs, their orgs', collaborations) that
    /// match `query`, best first, then public matches only when the user asked for them.
    /// Nothing matching means an empty list, never a stand-in. An empty query lists the
    /// user's own repos in their given order.
    public static func suggestions(mine: [Repository], public others: [Repository], query: String, limit: Int) -> [Repository] {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return Self.interleavedByProvider(mine, limit: limit) }
        let own = Self.sort(Self.scored(repos: mine, query: trimmed, sourceRank: 0)).map(\.repo)
        // By provider-qualified key: a GitHub repo and an Azure repo of the same name are two repos.
        let ownKeys = Set(mine.map(\.key.dedupeID))
        let rest = Self.sort(Self.scored(
            repos: others.filter { !ownKeys.contains($0.key.dedupeID) },
            query: trimmed,
            sourceRank: 1
        )).map(\.repo)
        return Array((own + rest).prefix(limit))
    }

    /// With nothing typed: each provider's repos in their given order, taken in turn, so a
    /// long GitHub list doesn't push every Azure repo past the limit.
    static func interleavedByProvider(_ repos: [Repository], limit: Int) -> [Repository] {
        let github = repos.filter { !$0.isAzure }
        let azure = repos.filter(\.isAzure)
        guard !github.isEmpty, !azure.isEmpty else { return Array(repos.prefix(limit)) }
        var out: [Repository] = []
        var index = 0
        while out.count < limit, index < max(github.count, azure.count) {
            if index < github.count { out.append(github[index]) }
            if out.count < limit, index < azure.count { out.append(azure[index]) }
            index += 1
        }
        return out
    }

    /// What text typed into the picker and committed with Return or Add stores: the shown
    /// suggestion it names exactly (by stored key, `project/name` or `org/project/name` for
    /// Azure, `owner/name` for GitHub), else a well-formed GitHub `owner/name` or Azure key as
    /// typed. Anything else (`a/b/c`, a bare word) is nil and is not stored, so an Azure name
    /// can never be saved as a GitHub pin.
    public static func resolveTyped(_ text: String, among suggestions: [Repository]) -> String? {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        let lower = trimmed.lowercased()
        if let match = suggestions.first(where: { Self.typedNames($0).contains(lower) }) { return match.fullName }
        guard let key = RepoKey(trimmed) else { return nil }
        return key.isGitHub ? trimmed : key.string
    }

    public static func merge(local: [Scored], remote: [Scored], limit: Int) -> [Repository] {
        var bestByKey: [String: Scored] = [:]
        let insert: (Scored) -> Void = { scored in
            let key = scored.repo.key.dedupeID
            if let existing = bestByKey[key] {
                if scored.score > existing.score {
                    bestByKey[key] = scored
                }
            } else {
                bestByKey[key] = scored
            }
        }
        local.forEach(insert)
        remote.forEach(insert)
        return Array(Self.sort(Array(bestByKey.values)).prefix(limit)).map(\.repo)
    }

    public static func score(repo: Repository, query: String) -> Int? {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        let lowerQuery = trimmed.lowercased()
        let hasSlash = lowerQuery.contains("/")
        if hasSlash {
            // An Azure repo answers to `project/name` and `org/project/name` as well as its key.
            if Self.typedNames(repo).contains(lowerQuery) { return 1000 }
            if Self.typedNames(repo).contains(where: { $0.hasPrefix(lowerQuery) }) { return 700 }
        }

        let parts = lowerQuery.split(separator: "/", omittingEmptySubsequences: false)
        let ownerQuery = parts.count > 1 ? String(parts[0]) : nil
        let repoQuery = parts.count > 1 ? String(parts[1]) : lowerQuery

        let ownerScore = Self.componentScore(
            query: ownerQuery ?? "",
            target: repo.azure?.project ?? repo.owner,
            weights: ComponentScoreWeights(
                exact: 200,
                prefix: 120,
                substring: 80,
                subsequence: 40
            )
        )
        let repoScore = Self.componentScore(
            query: repoQuery,
            target: repo.name,
            weights: ComponentScoreWeights(
                exact: 600,
                prefix: 420,
                substring: 260,
                subsequence: 160
            )
        )

        var score = 0
        if let ownerScore, ownerQuery != nil {
            score += ownerScore
        }
        if let repoScore {
            score += repoScore
        }

        if ownerQuery == nil {
            if repoScore == nil {
                let ownerFallback = Self.componentScore(
                    query: lowerQuery,
                    target: repo.azure?.project ?? repo.owner,
                    weights: ComponentScoreWeights(
                        exact: 120,
                        prefix: 80,
                        substring: 60,
                        subsequence: 30
                    )
                )
                guard let ownerFallback else { return nil }
                score += ownerFallback
            }
        } else if ownerScore == nil, repoScore == nil {
            return nil
        }

        if ownerScore != nil, repoScore != nil {
            score += 40
        }
        return score == 0 ? nil : score
    }

    /// The full names a person might type for this repo, lowercased.
    private static func typedNames(_ repo: Repository) -> [String] {
        guard let azure = repo.azure else { return [repo.fullName.lowercased()] }
        return [
            repo.fullName.lowercased(),
            repo.displayName.lowercased(),
            "\(azure.organization)/\(azure.project)/\(repo.name)".lowercased()
        ]
    }

    private static func componentScore(
        query: String,
        target: String,
        weights: ComponentScoreWeights
    ) -> Int? {
        guard !query.isEmpty else { return 0 }
        let lowerTarget = target.lowercased()
        if lowerTarget == query { return weights.exact }
        if lowerTarget.hasPrefix(query) { return weights.prefix }
        if lowerTarget.contains(query) { return weights.substring }
        if Self.isSubsequence(query, of: lowerTarget) { return weights.subsequence }
        return nil
    }

    private static func isSubsequence(_ needle: String, of haystack: String) -> Bool {
        var needleIndex = needle.startIndex
        var haystackIndex = haystack.startIndex

        while needleIndex < needle.endIndex, haystackIndex < haystack.endIndex {
            if needle[needleIndex] == haystack[haystackIndex] {
                needleIndex = needle.index(after: needleIndex)
            }
            haystackIndex = haystack.index(after: haystackIndex)
        }

        return needleIndex == needle.endIndex
    }
}
