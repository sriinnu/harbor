import Foundation

public enum TowerRepos {
    /// Repos the tower looks at: every repo under the configured project folders, plus every
    /// main checkout the ledger names (a repo has a `.git` directory; a linked worktree has a
    /// `.git` file). Real paths, deduplicated, existing only.
    public static func discover(rootPaths: [String], ledger: [String: LedgerWorktree]) -> [String] {
        var found = LocalProjectsService().discoverRepoRoots(rootPaths: rootPaths).map(\.path)
        found += ledgerRepos(ledger)
        var seen = Set<String>()
        return found.map(AgentLedger.normalizedPath).filter { seen.insert($0).inserted }
    }

    /// Main checkouts named by ledger rows.
    public static func ledgerRepos(_ ledger: [String: LedgerWorktree]) -> [String] {
        var seen = Set<String>()
        var result: [String] = []
        for repo in ledger.values.compactMap(\.repo) where seen.insert(repo).inserted {
            var isDirectory: ObjCBool = false
            if FileManager.default.fileExists(atPath: repo + "/.git", isDirectory: &isDirectory), isDirectory.boolValue {
                result.append(repo)
            }
        }
        return result.sorted()
    }
}
