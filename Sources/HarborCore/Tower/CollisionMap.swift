import Foundation

/// A file changed in two or more live worktrees of one repo.
public struct FileCollision: Equatable, Sendable {
    public let file: String
    /// Paths of the worktrees, sorted.
    public let worktrees: [String]
}

public enum CollisionMap {
    /// Lockfiles and the like change in every branch that touches dependencies; they would drown
    /// the real overlaps.
    public static let ignoredNames: Set<String> = [
        "pnpm-lock.yaml", "package-lock.json", "yarn.lock", "Package.resolved", "Cargo.lock", "Podfile.lock"
    ]

    /// `changes` maps a worktree path to every file it changes (committed since the merge base
    /// plus uncommitted). Files changed in at least two worktrees, sorted by file.
    public static func collisions(changes: [String: Set<String>]) -> [FileCollision] {
        var owners: [String: [String]] = [:]
        for (worktree, files) in changes {
            for file in files where !self.ignoredNames.contains((file as NSString).lastPathComponent) {
                owners[file, default: []].append(worktree)
            }
        }
        return owners
            .filter { $0.value.count >= 2 }
            .map { FileCollision(file: $0.key, worktrees: $0.value.sorted()) }
            .sorted { $0.file < $1.file }
    }
}
