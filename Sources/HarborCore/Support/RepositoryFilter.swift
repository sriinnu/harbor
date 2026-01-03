import Foundation

public enum RepositoryFilter {
    public static func apply(
        _ repos: [Repository],
        includeForks: Bool,
        includeArchived: Bool,
        pinned: Set<String> = [],
        onlyWith: RepositoryOnlyWith = .none
    ) -> [Repository] {
        let needsFilter = includeForks == false || includeArchived == false || onlyWith.isActive
        guard needsFilter else { return repos }

        return repos.filter { repo in
            if pinned.contains(repo.fullName) { return true }
            if includeForks == false, repo.isFork { return false }
            if includeArchived == false, repo.isArchived { return false }
            if onlyWith.isActive, onlyWith.matches(repo) == false { return false }
            return true
        }
    }
}
