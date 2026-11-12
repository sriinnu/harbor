import Foundation

/// Centralized constants so limits/TTLs stay obvious and discoverable.
public enum RepoListLimits {
    /// Upper bound for how many repos one `/user/repos` listing pulls for autocomplete.
    public static let maxRepositoriesToPrefetch = 1000
}

public enum LocalProjectsConstants {
    public static let defaultMaxDepth: Int = 2
    public static let defaultSnapshotConcurrencyLimit: Int = 8
    public static let dirtyFileLimit: Int = 10
}
