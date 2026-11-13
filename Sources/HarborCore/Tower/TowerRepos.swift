import Foundation

public enum TowerRepos {
    /// Repos the tower looks at: every repo under the configured project folders, plus every
    /// main checkout the ledger names (a repo has a `.git` directory; a linked worktree has a
    /// `.git` file). Real paths, deduplicated, existing only.
    ///
    /// A linked worktree that sits inside a project folder has a `.git` file and is found as a
    /// repo of its own. Each one is asked for its common git dir (`git rev-parse
    /// --git-common-dir`) and stands for the repo that owns it, so a repo and its worktrees are
    /// one entry. Without `git` the list is only deduplicated by path.
    public static func discover(rootPaths: [String], ledger: [String: LedgerWorktree], git: TowerGit? = nil) -> [String] {
        var found = LocalProjectsService().discoverRepoRoots(rootPaths: rootPaths).map(\.path)
        found += ledgerRepos(ledger)
        var seen = Set<String>()
        let paths = found.map(AgentLedger.normalizedPath).filter { seen.insert($0).inserted }
        guard let git else { return paths }
        var owners = Set<String>()
        return paths.map { owner(of: $0, git: git) }.filter { owners.insert($0).inserted }
    }

    /// The main checkout that owns `path`: `path` itself when its `.git` is a directory (or git
    /// can't say), else the parent of the common git dir. A common dir that is not some
    /// checkout's `.git` (a bare repo, `--separate-git-dir`) leaves the path as it is.
    static func owner(of path: String, git: TowerGit) -> String {
        var isDirectory: ObjCBool = false
        guard FileManager.default.fileExists(atPath: path + "/.git", isDirectory: &isDirectory), !isDirectory.boolValue,
              let common = git.output(["rev-parse", "--path-format=absolute", "--git-common-dir"], in: path)?
              .trimmingCharacters(in: .whitespacesAndNewlines),
              common.hasSuffix("/.git")
        else { return path }
        let main = AgentLedger.normalizedPath(String(common.dropLast("/.git".count)))
        return FileManager.default.fileExists(atPath: main + "/.git", isDirectory: &isDirectory) && isDirectory.boolValue ? main : path
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
