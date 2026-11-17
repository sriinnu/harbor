import HarborCore

/// Stored and typed repository names, as harborcli reads them. harborcli talks to GitHub only,
/// so an Azure DevOps key (`azure:…`) is never turned into a GitHub owner and name.
enum CLIRepoNames {
    struct Lookup: Equatable {
        let index: Int
        let owner: String
        let name: String
    }

    /// The GitHub names in `names`, with their position kept; Azure keys and anything that
    /// isn't `owner/name` are left out.
    static func gitHubLookups(_ names: [String]) -> [Lookup] {
        names.enumerated().compactMap { index, stored in
            RepoKey.gitHubOwnerAndName(stored).map { Lookup(index: index, owner: $0.owner, name: $0.name) }
        }
    }

    static func invalidNameMessage(_ typed: String) -> String {
        RepoKey.isAzure(typed)
            ? "harborcli works with GitHub repositories only; \(typed) is an Azure DevOps repository"
            : "Repository must be in owner/name format"
    }
}
