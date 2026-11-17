import Foundation

/// Putting the providers' repository lists together: GitHub's and Azure DevOps'.
public enum RepoListSources {
    /// GitHub's rows first, then every Azure row not already there. Rows are told apart by
    /// their provider-qualified key, so a GitHub `acme/site` and an Azure `acme`/`Web`/`site`
    /// are two rows, and a repeated key keeps its first row.
    public static func combine(github: [Repository], azure: [Repository]) -> [Repository] {
        var seen = Set<String>()
        return (github + azure).filter { seen.insert($0.key.dedupeID).inserted }
    }

    /// Both providers asked side by side. One failing answers nothing for that provider
    /// only; the other's rows still come back.
    public static func gather(
        github: @escaping @Sendable () async throws -> [Repository],
        azure: @escaping @Sendable () async throws -> [Repository]
    ) async -> [Repository] {
        async let fromGitHub = (try? await github()) ?? []
        async let fromAzure = (try? await azure()) ?? []
        return await Self.combine(github: fromGitHub, azure: fromAzure)
    }
}
