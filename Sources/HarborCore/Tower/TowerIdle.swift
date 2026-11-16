import Foundation

/// The "idle, maybe waiting" guess for an agent process Tower can see but the ledger doesn't
/// speak for. It is a guess: a long model turn also leaves a worktree untouched. Only a ledger
/// `agent.waiting` event may say "waiting".
public enum TowerIdle {
    /// No file or git change this long, with a process inside, reads "idle, maybe waiting".
    public static let threshold: TimeInterval = 10 * 60
    /// Changed files looked at: the newest of a thousand is no newer than the newest of these.
    static let pathLimit = 300

    /// When anything in the worktree last changed: the newest modification time among its
    /// uncommitted files and the worktree's own `HEAD`, `index` and reflog (a commit, checkout
    /// or staging touches those). nil when none of them can be read.
    public static func lastChange(worktree: String, dirtyPaths: [String]) -> Date? {
        var times: [Date] = []
        for path in dirtyPaths.prefix(self.pathLimit) {
            if let date = modified(worktree + "/" + path) { times.append(date) }
        }
        if let gitDirectory = gitDirectory(of: worktree) {
            for name in ["HEAD", "index", "logs/HEAD"] {
                if let date = modified(gitDirectory + "/" + name) { times.append(date) }
            }
        }
        return times.max()
    }

    /// The worktree's own git directory: `.git` itself, or what a linked worktree's `.git` file names.
    static func gitDirectory(of worktree: String) -> String? {
        let dot = worktree + "/.git"
        var isDirectory: ObjCBool = false
        guard FileManager.default.fileExists(atPath: dot, isDirectory: &isDirectory) else { return nil }
        if isDirectory.boolValue { return dot }
        guard let text = try? String(contentsOfFile: dot, encoding: .utf8),
              let line = text.split(whereSeparator: \.isNewline).first(where: { $0.hasPrefix("gitdir:") }) else { return nil }
        let target = line.dropFirst("gitdir:".count).trimmingCharacters(in: .whitespaces)
        return target.hasPrefix("/") ? target : URL(fileURLWithPath: worktree).appendingPathComponent(target).standardized.path
    }

    private static func modified(_ path: String) -> Date? {
        (try? FileManager.default.attributesOfItem(atPath: path))?[.modificationDate] as? Date
    }
}
